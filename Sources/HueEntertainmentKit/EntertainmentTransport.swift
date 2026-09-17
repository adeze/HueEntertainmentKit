import Dispatch
import Foundation
import Network
import NIOCore
import NIOTransportServices
import Security

/// Outbound carrier for entertainment stream frames in the Swift-NIO pipeline.
public struct HueStreamMessage: Sendable {
    public let configurationID: UUID
    public let sequence: UInt8
    public let frame: HueFrame

    public init(configurationID: UUID, sequence: UInt8, frame: HueFrame) {
        self.configurationID = configurationID
        self.sequence = sequence
        self.frame = frame
    }
}

public protocol HueDatagramTransport: Sendable {
    func connect(endpoint: HueBridgeEndpoint, credentials: HueCredentials) async throws
    func send(_ packet: ByteBuffer) async throws
    func send(_ message: HueStreamMessage) async throws
    func close() async
}

extension HueDatagramTransport {
    public func send(_ message: HueStreamMessage) async throws {
        let packet = HueStreamPacketEncoder().encode(
            configurationID: message.configurationID,
            sequence: message.sequence,
            frame: message.frame
        )
        try await send(packet)
    }
}

/// A Swift-NIO `ChannelDuplexHandler` that encodes high-level `HueStreamMessage` frames into DTLS datagrams
/// and monitors channel lifecycle events (inactivity, DTLS alerts, socket errors).
public final class HueStreamChannelHandler: ChannelDuplexHandler, @unchecked Sendable {
    public typealias InboundIn = ByteBuffer
    public typealias InboundOut = ByteBuffer
    public typealias OutboundIn = HueStreamMessage
    public typealias OutboundOut = ByteBuffer

    private let encoder: HueStreamPacketEncoder
    private let onActive: (@Sendable () -> Void)?
    private let onInactive: (@Sendable () -> Void)?
    private let onError: (@Sendable (any Error) -> Void)?

    public init(
        encoder: HueStreamPacketEncoder = .init(),
        onActive: (@Sendable () -> Void)? = nil,
        onInactive: (@Sendable () -> Void)? = nil,
        onError: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.encoder = encoder
        self.onActive = onActive
        self.onInactive = onInactive
        self.onError = onError
    }

    public func write(context: ChannelHandlerContext, data: NIOAny, promise: EventLoopPromise<Void>?) {
        let message = unwrapOutboundIn(data)
        let byteBuffer = encoder.encode(
            configurationID: message.configurationID,
            sequence: message.sequence,
            frame: message.frame
        )
        context.write(wrapOutboundOut(byteBuffer), promise: promise)
    }

    public func channelActive(context: ChannelHandlerContext) {
        HueLog.transport.debug("DTLS datagram channel active: \(String(describing: context.remoteAddress))")
        onActive?()
        context.fireChannelActive()
    }

    public func channelInactive(context: ChannelHandlerContext) {
        HueLog.transport.notice("DTLS datagram channel inactive: \(String(describing: context.remoteAddress))")
        onInactive?()
        context.fireChannelInactive()
    }

    public func errorCaught(context: ChannelHandlerContext, error: any Error) {
        HueLog.transport.error("DTLS datagram channel error: \(error)")
        onError?(error)
        context.fireErrorCaught(error)
    }
}

public actor NIOTSDTLSTransport: HueDatagramTransport {
    private var group: NIOTSEventLoopGroup?
    private let externalGroup: NIOTSEventLoopGroup?
    private var channel: Channel?
    private let onInactive: (@Sendable () -> Void)?
    private let onError: (@Sendable (any Error) -> Void)?

    public init(
        group: NIOTSEventLoopGroup? = nil,
        onInactive: (@Sendable () -> Void)? = nil,
        onError: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.externalGroup = group
        self.onInactive = onInactive
        self.onError = onError
    }

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

        let targetGroup = externalGroup ?? NIOTSEventLoopGroup(loopCount: 1)
        if externalGroup == nil {
            self.group = targetGroup
        }

        let pipelineHandler = HueStreamChannelHandler(
            onInactive: onInactive,
            onError: onError
        )

        do {
            channel = try await NIOTSDatagramConnectionBootstrap(group: targetGroup)
                .tlsOptions(tls)
                .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
                .channelInitializer { channel in
                    channel.pipeline.addHandler(pipelineHandler)
                }
                .connect(host: endpoint.host, port: 2100)
                .get()
        } catch {
            if externalGroup == nil {
                try? await targetGroup.shutdownGracefully()
                self.group = nil
            }
            throw HueEntertainmentError.connectionFailed(String(describing: error))
        }
    }

    public func send(_ packet: ByteBuffer) async throws {
        guard let channel, channel.isActive else { throw HueEntertainmentError.invalidState }
        try await channel.writeAndFlush(packet).get()
    }

    public func send(_ message: HueStreamMessage) async throws {
        guard let channel, channel.isActive else { throw HueEntertainmentError.invalidState }
        try await channel.writeAndFlush(message).get()
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
