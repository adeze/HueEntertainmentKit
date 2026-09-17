import Foundation
import Network
import NIOCore
import NIOHTTP1
import NIOTransportServices
import Security

/// A native Swift-NIO HTTP/1.1 transport using `NIOTransportServices` and `NIOHTTP1`
/// with strict TLS root CA and bridge ID verification.
public final class NIOHueHTTPTransport: HueHTTPTransport, @unchecked Sendable {
    private let externalGroup: NIOTSEventLoopGroup?
    private let internalGroup: NIOTSEventLoopGroup?
    private let trustPolicy: HueBridgeTrustPolicy

    public init(group: NIOTSEventLoopGroup? = nil, trustPolicy: HueBridgeTrustPolicy = .system) {
        self.externalGroup = group
        if group == nil {
            self.internalGroup = NIOTSEventLoopGroup(loopCount: 1)
        } else {
            self.internalGroup = nil
        }
        self.trustPolicy = trustPolicy
    }

    deinit {
        try? internalGroup?.syncShutdownGracefully()
    }

    private var eventLoopGroup: NIOTSEventLoopGroup {
        externalGroup ?? internalGroup!
    }

    public func send(_ request: HueHTTPRequest) async throws -> HueHTTPResponse {
        guard let host = request.url.host() else {
            throw HueEntertainmentError.invalidEndpoint
        }
        let port = request.url.port ?? 443

        let tls = NWProtocolTLS.Options()
        let secOptions = tls.securityProtocolOptions

        switch trustPolicy {
        case .system:
            break
        case .hueBridge(let bridgeID):
            configureTLSVerification(
                options: secOptions,
                roots: HueBridgeCertificateAuthority.rootCertificates,
                expectedCommonName: bridgeID
            )
        case .pinnedRootCertificates(let roots, let expectedCommonName):
            configureTLSVerification(
                options: secOptions,
                roots: roots,
                expectedCommonName: expectedCommonName
            )
        }

        let promise = eventLoopGroup.next().makePromise(of: HueHTTPResponse.self)
        let responseHandler = NIOHTTPResponseAccumulator(promise: promise)

        let bootstrap = NIOTSConnectionBootstrap(group: eventLoopGroup)
            .tlsOptions(tls)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { channel in
                channel.pipeline.addHTTPClientHandlers(position: .first, leftOverBytesStrategy: .fireError).flatMap {
                    channel.pipeline.addHandler(responseHandler)
                }
            }

        let channel: Channel
        do {
            channel = try await bootstrap.connect(host: host, port: port).get()
        } catch {
            throw HueEntertainmentError.connectionFailed(String(describing: error))
        }

        // Build HTTP request head
        var headers = HTTPHeaders()
        headers.add(name: "Host", value: "\(host):\(port)")
        headers.add(name: "User-Agent", value: "HueEntertainmentKit/1.0")
        headers.add(name: "Connection", value: "close")
        for (key, value) in request.headers {
            headers.add(name: key, value: value)
        }

        let bodyBytes = request.body
        if let bodyBytes {
            headers.add(name: "Content-Length", value: "\(bodyBytes.count)")
        } else if request.method == .post || request.method == .put {
            headers.add(name: "Content-Length", value: "0")
        }

        let uri = request.url.path().isEmpty ? "/" : request.url.path()
        let requestHead = HTTPRequestHead(
            version: .http1_1,
            method: HTTPMethod(rawValue: request.method.rawValue),
            uri: uri,
            headers: headers
        )

        do {
            try await channel.write(HTTPClientRequestPart.head(requestHead)).get()
            if let bodyBytes, !bodyBytes.isEmpty {
                var buffer = channel.allocator.buffer(capacity: bodyBytes.count)
                buffer.writeBytes(bodyBytes)
                try await channel.write(HTTPClientRequestPart.body(.byteBuffer(buffer))).get()
            }
            try await channel.writeAndFlush(HTTPClientRequestPart.end(nil)).get()
        } catch {
            _ = try? await channel.close()
            throw error
        }

        do {
            let response = try await promise.futureResult.get()
            _ = try? await channel.close()
            return response
        } catch {
            _ = try? await channel.close()
            throw error
        }
    }

    private func configureTLSVerification(
        options: sec_protocol_options_t,
        roots: [Data],
        expectedCommonName: String
    ) {
        let verifyQueue = DispatchQueue(label: "com.adeze.HueEntertainmentKit.tls-verify")
        sec_protocol_options_set_verify_block(options, { (_, sec_trust, complete) in
            let trust = sec_trust_copy_ref(sec_trust).takeRetainedValue()
            let certificates = roots.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
            let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate]
            var leafCommonName: CFString?
            if let leaf = chain?.first { SecCertificateCopyCommonName(leaf, &leafCommonName) }

            guard !certificates.isEmpty,
                  let leafCommonName,
                  (leafCommonName as String).caseInsensitiveCompare(expectedCommonName) == .orderedSame,
                  SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
                  SecTrustSetPolicies(trust, SecPolicyCreateBasicX509()) == errSecSuccess,
                  SecTrustEvaluateWithError(trust, nil)
            else {
                complete(false)
                return
            }
            complete(true)
        }, verifyQueue)
    }
}

private final class NIOHTTPResponseAccumulator: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let promise: EventLoopPromise<HueHTTPResponse>
    private var responseHead: HTTPResponseHead?
    private var responseBody: ByteBuffer?

    init(promise: EventLoopPromise<HueHTTPResponse>) {
        self.promise = promise
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let part = unwrapInboundIn(data)
        switch part {
        case .head(let head):
            self.responseHead = head
            self.responseBody = context.channel.allocator.buffer(capacity: 1024)
        case .body(var buffer):
            if self.responseBody == nil {
                self.responseBody = buffer
            } else {
                self.responseBody?.writeBuffer(&buffer)
            }
        case .end:
            guard let head = self.responseHead else {
                promise.fail(HueEntertainmentError.malformedResponse)
                return
            }
            var headers: [String: String] = [:]
            for (name, value) in head.headers {
                headers[name.lowercased()] = value
            }
            let bodyData = responseBody.flatMap { buffer in
                buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes).map { Data($0) }
            } ?? Data()
            let response = HueHTTPResponse(
                statusCode: Int(head.status.code),
                headers: headers,
                body: bodyData
            )
            promise.succeed(response)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: any Error) {
        promise.fail(error)
        context.fireErrorCaught(error)
    }
}
