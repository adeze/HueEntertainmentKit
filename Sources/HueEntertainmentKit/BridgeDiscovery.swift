import Foundation
import Network
import dnssd

public struct HueBridgeDiscovery: Sendable {
    public init() {}

    /// Discovers Hue bridges on the local network via Bonjour mDNS for the specified duration.
    public func discoverBonjour(for duration: Duration = .seconds(3)) async throws -> [HueBridgeEndpoint] {
        HueLog.discovery.debug("Starting Bonjour discovery for \(duration)")
        let resolver = BonjourBrowser()
        resolver.start()
        defer { resolver.stop() }
        try await Task.sleep(for: duration)
        let endpoints = try resolver.finish()
        HueLog.discovery.debug("Bonjour discovery finished with \(endpoints.count) bridges")
        return endpoints
    }

    /// Returns an `AsyncStream` streaming discovered bridge endpoints in real time as they resolve on the local network.
    /// Discovery terminates automatically when the stream is cancelled.
    public func bonjourStream() -> AsyncStream<HueBridgeEndpoint> {
        AsyncStream { continuation in
            let resolver = BonjourBrowser(
                onEndpoint: { endpoint in continuation.yield(endpoint) },
                onFailure: { continuation.finish() }
            )
            continuation.onTermination = { @Sendable _ in
                resolver.stop()
            }
            resolver.start()
        }
    }

    /// Discovers Hue bridges using the Philips Hue cloud discovery broker service (`https://discovery.meethue.com`).
    public func discoverViaBroker(session: URLSession = .shared) async throws -> [HueBridgeEndpoint] {
        HueLog.discovery.debug("Querying cloud discovery broker")
        let url = URL(string: "https://discovery.meethue.com")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HueEntertainmentError.malformedResponse
        }
        let bridges = try JSONDecoder().decode([BrokerBridge].self, from: data)
        let endpoints = try bridges.map { try HueBridgeEndpoint(host: $0.internalipaddress, bridgeID: $0.id) }
        HueLog.discovery.debug("Broker discovery found \(endpoints.count) bridges")
        return endpoints
    }

    /// Creates an endpoint manually from a known host IP or domain and optional bridge identifier.
    public func manual(host: String, port: Int = 443, bridgeID: String? = nil) throws -> HueBridgeEndpoint {
        try HueBridgeEndpoint(host: host, port: port, bridgeID: bridgeID)
    }

    static func resolvedBonjourEndpoint(host: String, networkPort: UInt16, bridgeID: String?) -> HueBridgeEndpoint? {
        let normalizedHost = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return try? HueBridgeEndpoint(
            host: normalizedHost, port: Int(UInt16(bigEndian: networkPort)), bridgeID: bridgeID
        )
    }
}

private struct BrokerBridge: Decodable { let id: String; let internalipaddress: String }

// Browser callbacks and DNS-SD references share one serial queue.
private final class BonjourBrowser: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.adeze.HueEntertainmentKit.bonjour")
    private let browser = NWBrowser(for: .bonjour(type: "_hue._tcp", domain: "local."), using: .tcp)
    private var services = Set<NWEndpoint>()
    private var resolutions: [NWEndpoint: (reference: DNSServiceRef, token: UUID)] = [:]
    private var endpoints = Set<HueBridgeEndpoint>()
    private var onEndpoint: (@Sendable (HueBridgeEndpoint) -> Void)?
    private var onFailure: (@Sendable () -> Void)?
    private var failure: NWError?
    private var stopped = false

    init(
        onEndpoint: (@Sendable (HueBridgeEndpoint) -> Void)? = nil,
        onFailure: (@Sendable () -> Void)? = nil
    ) {
        self.onEndpoint = onEndpoint
        self.onFailure = onFailure
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.update(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.handleFailure(error)
            }
        }
    }

    func start() {
        browser.start(queue: queue)
    }

    func finish() throws -> [HueBridgeEndpoint] {
        try queue.sync {
            stopOnQueue()
            if let failure { throw failure }
            return endpoints.sorted {
                ($0.host, $0.port, $0.bridgeID ?? "") < ($1.host, $1.port, $1.bridgeID ?? "")
            }
        }
    }

    func stop() {
        queue.async { self.stopOnQueue() }
    }

    private func stopOnQueue() {
        guard !stopped else { return }
        stopped = true
        browser.cancel()
        for resolution in resolutions.values {
            DNSServiceRefDeallocate(resolution.reference)
        }
        resolutions.removeAll()
        services.removeAll()
        onEndpoint = nil
        onFailure = nil
    }

    private func handleFailure(_ error: NWError) {
        guard !stopped else { return }
        HueLog.discovery.error("Bonjour browser failed: \(error)")
        failure = error
        onFailure?()
        stopOnQueue()
    }

    private func update(_ results: Set<NWBrowser.Result>) {
        guard !stopped else { return }
        let current = Set(results.map(\.endpoint))
        for endpoint in services.subtracting(current) {
            if let resolution = resolutions.removeValue(forKey: endpoint) {
                DNSServiceRefDeallocate(resolution.reference)
            }
        }
        for endpoint in current.subtracting(services) {
            resolve(endpoint)
        }
        services = current
    }

    private func resolve(_ endpoint: NWEndpoint) {
        guard case let .service(name, type, domain, interface) = endpoint else { return }
        var reference: DNSServiceRef?
        let status = DNSServiceResolve(
            &reference, 0, UInt32(interface?.index ?? 0), name, type, domain,
            { service, _, _, error, _, host, port, txtLength, txt, context in
                guard let context else { return }
                let owner = Unmanaged<BonjourBrowser>.fromOpaque(context).takeUnretainedValue()
                var bridgeID: String?
                if error == kDNSServiceErr_NoError, let txt, txtLength > 0 {
                    var valueLength: UInt8 = 0
                    if let value = TXTRecordGetValuePtr(txtLength, txt, "bridgeid", &valueLength) {
                        bridgeID = String(data: Data(bytes: value, count: Int(valueLength)), encoding: .utf8)
                    }
                }
                let hostname = error == kDNSServiceErr_NoError ? host.map { String(cString: $0) } : nil
                owner.didResolve(
                    service: service, error: error, host: hostname, port: port, bridgeID: bridgeID
                )
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        guard status == kDNSServiceErr_NoError, let reference else {
            HueLog.discovery.warning("Bonjour service resolution failed: \(status)")
            return
        }
        guard DNSServiceSetDispatchQueue(reference, queue) == kDNSServiceErr_NoError else {
            DNSServiceRefDeallocate(reference)
            return
        }
        let token = UUID()
        resolutions[endpoint] = (reference, token)
        queue.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.expire(endpoint, token: token)
        }
    }

    private func expire(_ endpoint: NWEndpoint, token: UUID) {
        guard let resolution = resolutions[endpoint], resolution.token == token else { return }
        resolutions.removeValue(forKey: endpoint)
        DNSServiceRefDeallocate(resolution.reference)
    }

    private func didResolve(
        service: DNSServiceRef?, error: DNSServiceErrorType, host: String?,
        port: UInt16, bridgeID: String?
    ) {
        guard let service, let endpoint = resolutions.first(where: { $0.value.reference == service })?.key,
              let resolution = resolutions.removeValue(forKey: endpoint)
        else { return }
        let bridge: HueBridgeEndpoint?
        if error == kDNSServiceErr_NoError, let host {
            bridge = HueBridgeDiscovery.resolvedBonjourEndpoint(
                host: host, networkPort: port, bridgeID: bridgeID
            )
        } else {
            bridge = nil
        }
        DNSServiceRefDeallocate(resolution.reference)
        guard let bridge else { return }
        if endpoints.insert(bridge).inserted {
            HueLog.discovery.debug("Bonjour resolved new bridge: \(bridge.host)")
            onEndpoint?(bridge)
        }
    }
}
