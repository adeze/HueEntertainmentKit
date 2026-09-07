import Dispatch
import Foundation
import Network
import NIOCore
import NIOTransportServices
import Security

public protocol HueDatagramTransport: Sendable {
    func connect(endpoint: HueBridgeEndpoint, credentials: HueCredentials) async throws
    func send(_ packet: ByteBuffer) async throws
    func close() async
}

public actor NIOTSDTLSTransport: HueDatagramTransport {
    private var group: NIOTSEventLoopGroup?
    private var channel: Channel?

    public init() {}

    public func connect(endpoint: HueBridgeEndpoint, credentials: HueCredentials) async throws {
        guard channel == nil else { throw HueEntertainmentError.invalidState }
        guard let key = Data(hex: credentials.clientKey) else { throw HueEntertainmentError.invalidClientKey }
        guard let identityText = credentials.applicationID, !identityText.isEmpty else {
            throw HueEntertainmentError.missingApplicationID
        }
        guard let identity = identityText.data(using: .utf8) else { throw HueEntertainmentError.invalidClientKey }

        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        sec_protocol_options_set_max_tls_protocol_version(options, .TLSv12)
        let cipher = tls_ciphersuite_t(rawValue: 0x00A8)!
        sec_protocol_options_append_tls_ciphersuite(options, cipher)
        let psk = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let pskIdentity = identity.withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(options, psk as dispatch_data_t, pskIdentity as dispatch_data_t)

        let group = NIOTSEventLoopGroup(loopCount: 1)
        self.group = group
        do {
            channel = try await NIOTSDatagramConnectionBootstrap(group: group)
                .tlsOptions(tls)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .connect(host: endpoint.host, port: 2100)
                .get()
        } catch {
            try? await group.shutdownGracefully()
            self.group = nil
            throw HueEntertainmentError.connectionFailed(String(describing: error))
        }
    }

    public func send(_ packet: ByteBuffer) async throws {
        guard let channel, channel.isActive else { throw HueEntertainmentError.invalidState }
        try await channel.writeAndFlush(packet).get()
    }

    public func close() async {
        if let channel { try? await channel.close().get() }
        channel = nil
        if let group { try? await group.shutdownGracefully() }
        group = nil
    }
}

private extension Data {
    init?(hex: String) {
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
