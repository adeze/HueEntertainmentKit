import Foundation

public struct HueBridgeDiscovery: Sendable {
    public init() {}

    public func discoverBonjour(for duration: Duration = .seconds(3)) async throws -> [HueBridgeEndpoint] {
        let resolver = await MainActor.run { BonjourResolver() }
        await MainActor.run { resolver.start() }
        try await Task.sleep(for: duration)
        return await MainActor.run { resolver.finish() }
    }

    public func discoverViaBroker(session: URLSession = .shared) async throws -> [HueBridgeEndpoint] {
        let url = URL(string: "https://discovery.meethue.com")!
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw HueEntertainmentError.malformedResponse
        }
        let bridges = try JSONDecoder().decode([BrokerBridge].self, from: data)
        return try bridges.map { try HueBridgeEndpoint(host: $0.internalipaddress, bridgeID: $0.id) }
    }

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
