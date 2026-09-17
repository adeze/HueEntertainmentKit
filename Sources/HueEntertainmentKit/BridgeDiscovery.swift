import Foundation

public struct HueBridgeDiscovery: Sendable {
    public init() {}

    /// Discovers Hue bridges on the local network via Bonjour mDNS for the specified duration.
    public func discoverBonjour(for duration: Duration = .seconds(3)) async throws -> [HueBridgeEndpoint] {
        HueLog.discovery.debug("Starting Bonjour discovery for \(duration)")
        let resolver = await MainActor.run { BonjourResolver() }
        await MainActor.run { resolver.start() }
        try await Task.sleep(for: duration)
        let endpoints = await MainActor.run { resolver.finish() }
        HueLog.discovery.debug("Bonjour discovery finished with \(endpoints.count) bridges")
        return endpoints
    }

    /// Returns an `AsyncStream` streaming discovered bridge endpoints in real time as they resolve on the local network.
    /// Discovery terminates automatically when the stream is cancelled.
    public func bonjourStream() -> AsyncStream<HueBridgeEndpoint> {
        AsyncStream { continuation in
            let resolver = BonjourStreamingResolver { endpoint in
                continuation.yield(endpoint)
            }
            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    resolver.stop()
                }
            }
            Task { @MainActor in
                resolver.start()
            }
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
}

private struct BrokerBridge: Decodable { let id: String; let internalipaddress: String }

private final class BonjourResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private let lock = NSLock()
    private var services: [NetService] = []
    private var resolved: [HueBridgeEndpoint] = []

    override init() {
        super.init()
        browser.delegate = self
    }

    func start() { browser.searchForServices(ofType: "_hue._tcp.", inDomain: "local.") }

    func finish() -> [HueBridgeEndpoint] {
        browser.stop()
        lock.lock()
        services.forEach { $0.stop() }
        let output = Array(Set(resolved)).sorted { $0.host < $1.host }
        lock.unlock()
        return output
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
        services.append(service)
        lock.unlock()
        service.delegate = self
        service.resolve(withTimeout: 2)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let bridgeID = sender.txtRecordData().flatMap { data in
            NetService.dictionary(fromTXTRecord: data)["bridgeid"]
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty,
              let endpoint = try? HueBridgeEndpoint(
                host: host,
                port: sender.port > 0 ? sender.port : 443,
                bridgeID: bridgeID
              )
        else { return }
        lock.lock()
        resolved.append(endpoint)
        lock.unlock()
    }
}

private final class BonjourStreamingResolver: NSObject, NetServiceBrowserDelegate, NetServiceDelegate, @unchecked Sendable {
    private let browser = NetServiceBrowser()
    private let lock = NSLock()
    private var services: [NetService] = []
    private var seen = Set<HueBridgeEndpoint>()
    private let onEndpoint: @Sendable (HueBridgeEndpoint) -> Void

    init(onEndpoint: @escaping @Sendable (HueBridgeEndpoint) -> Void) {
        self.onEndpoint = onEndpoint
        super.init()
        browser.delegate = self
    }

    func start() {
        HueLog.discovery.debug("Starting Bonjour streaming discovery")
        browser.searchForServices(ofType: "_hue._tcp.", inDomain: "local.")
    }

    func stop() {
        browser.stop()
        lock.lock()
        services.forEach { $0.stop() }
        services.removeAll()
        lock.unlock()
        HueLog.discovery.debug("Stopped Bonjour streaming discovery")
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        lock.lock()
        services.append(service)
        lock.unlock()
        service.delegate = self
        service.resolve(withTimeout: 2)
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        let bridgeID = sender.txtRecordData().flatMap { data in
            NetService.dictionary(fromTXTRecord: data)["bridgeid"]
                .flatMap { String(data: $0, encoding: .utf8) }
        }
        guard let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")), !host.isEmpty,
              let endpoint = try? HueBridgeEndpoint(
                host: host,
                port: sender.port > 0 ? sender.port : 443,
                bridgeID: bridgeID
              )
        else { return }

        lock.lock()
        let isNew = seen.insert(endpoint).inserted
        lock.unlock()

        if isNew {
            HueLog.discovery.debug("Bonjour resolved new bridge: \(endpoint.host)")
            onEndpoint(endpoint)
        }
    }
}
