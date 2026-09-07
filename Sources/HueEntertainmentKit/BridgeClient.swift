import Foundation

public struct HuePairingProgress: Sendable, Equatable {
    public enum State: Sendable, Equatable { case waitingForLinkButton, paired }
    public let state: State
    public let message: String
}

public struct HuePairingResult: Sendable {
    public let credentials: HueCredentials
    public let applicationID: String?
}

public protocol HueEntertainmentControl: Sendable {
    func setStreamActive(configurationID: UUID, active: Bool) async throws
    func streamStatus(configurationID: UUID) async throws -> HueStreamStatus
}

public enum HueStreamStatus: Sendable, Equatable {
    case inactive
    case active(applicationID: String?)
}

public struct HueBridgeClient: HueEntertainmentControl, Sendable {
    private let endpoint: HueBridgeEndpoint
    private let credentials: HueCredentials?
    private let transport: any HueHTTPTransport
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    public init(
        endpoint: HueBridgeEndpoint,
        credentials: HueCredentials? = nil,
        transport: any HueHTTPTransport
    ) {
        self.endpoint = endpoint
        self.credentials = credentials
        self.transport = transport
    }

    public func pair(deviceType: String) async throws -> HuePairingResult {
        guard !deviceType.isEmpty else { throw HueEntertainmentError.malformedResponse }
        let body = try encoder.encode(PairRequest(devicetype: deviceType, generateclientkey: true))
        let response = try await transport.send(HueHTTPRequest(
            method: .post,
            url: endpoint.baseURL.appending(path: "api"),
            headers: ["content-type": "application/json"],
            body: body
        ))
        try Self.validate(response)
        let entries = try decoder.decode([PairEntry].self, from: response.body)
        if let error = entries.compactMap(\.error).first {
            if error.type == 101 { throw HueEntertainmentError.linkButtonRequired }
            throw HueEntertainmentError.bridge(error.description)
        }
        guard let success = entries.compactMap(\.success).first else {
            throw HueEntertainmentError.malformedResponse
        }
        let provisional = try HueCredentials(applicationKey: success.username, clientKey: success.clientkey)
        let auth = try await transport.send(HueHTTPRequest(
            method: .get,
            url: endpoint.baseURL.appending(path: "auth/v1"),
            headers: ["hue-application-key": provisional.applicationKey]
        ))
        try Self.validate(auth)
        let applicationID = auth.headers["hue-application-id"]
        let credentials = try HueCredentials(
            applicationKey: provisional.applicationKey,
            clientKey: provisional.clientKey,
            applicationID: applicationID
        )
        return HuePairingResult(credentials: credentials, applicationID: applicationID)
    }

    public func pairWaitingForLinkButton(
        deviceType: String,
        timeout: Duration = .seconds(30),
        retryInterval: Duration = .seconds(1),
        progress: @Sendable (HuePairingProgress) -> Void
    ) async throws -> HuePairingResult {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            do {
                let result = try await pair(deviceType: deviceType)
                progress(.init(state: .paired, message: "Bridge linked"))
                return result
            } catch HueEntertainmentError.linkButtonRequired {
                progress(.init(state: .waitingForLinkButton, message: "Press the bridge link button"))
                try await Task.sleep(for: retryInterval)
            }
        }
        throw HueEntertainmentError.connectionFailed("Timed out waiting for bridge link button")
    }

    public func entertainmentConfigurations() async throws -> [HueEntertainmentConfiguration] {
        let response = try await authenticatedRequest(
            method: .get,
            path: "clip/v2/resource/entertainment_configuration"
        )
        let envelope = try decoder.decode(ConfigurationEnvelope.self, from: response.body)
        try Self.throwBridgeErrors(envelope.errors)
        return try Self.configurations(from: envelope.data)
    }

    public func streamStatus(configurationID: UUID) async throws -> HueStreamStatus {
        let response = try await authenticatedRequest(
            method: .get,
            path: "clip/v2/resource/entertainment_configuration/\(configurationID.uuidString.lowercased())"
        )
        let envelope = try decoder.decode(ConfigurationEnvelope.self, from: response.body)
        try Self.throwBridgeErrors(envelope.errors)
        guard let raw = envelope.data.first else { throw HueEntertainmentError.invalidConfigurationIdentifier }
        return raw.status == "active" ? .active(applicationID: raw.activeStreamer?.rid) : .inactive
    }

    private static func configurations(from data: [RawConfiguration]) throws -> [HueEntertainmentConfiguration] {
        try data.map { raw in
            guard let id = UUID(uuidString: raw.id) else {
                throw HueEntertainmentError.invalidConfigurationIdentifier
            }
            let channels = try raw.channels.map { channel in
                try HueEntertainmentChannel(
                    id: channel.channelID,
                    position: SIMD3(
                        channel.position.x,
                        channel.position.y,
                        channel.position.z
                    ),
                    memberResourceIDs: channel.members.map { $0.service.rid }
                )
            }
            return HueEntertainmentConfiguration(
                id: id,
                name: raw.metadata.name,
                isActive: raw.status == "active",
                channels: channels
            )
        }
    }

    public func setStreamActive(configurationID: UUID, active: Bool) async throws {
        let body = try encoder.encode(StreamAction(action: active ? "start" : "stop"))
        let response = try await authenticatedRequest(
            method: .put,
            path: "clip/v2/resource/entertainment_configuration/\(configurationID.uuidString.lowercased())",
            body: body
        )
        let envelope = try decoder.decode(ActionEnvelope.self, from: response.body)
        try Self.throwBridgeErrors(envelope.errors)
    }

    private func authenticatedRequest(
        method: HueHTTPRequest.Method,
        path: String,
        body: Data? = nil
    ) async throws -> HueHTTPResponse {
        guard let credentials else { throw HueEntertainmentError.authenticationRequired }
        let response = try await transport.send(HueHTTPRequest(
            method: method,
            url: endpoint.baseURL.appending(path: path),
            headers: [
                "hue-application-key": credentials.applicationKey,
                "content-type": "application/json",
            ],
            body: body
        ))
        try Self.validate(response)
        return response
    }

    private static func validate(_ response: HueHTTPResponse) throws {
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw HueEntertainmentError.authenticationRequired
            }
            throw HueEntertainmentError.httpStatus(response.statusCode)
        }
    }

    private static func throwBridgeErrors(_ errors: [BridgeError]) throws {
        guard let error = errors.first else { return }
        if error.description.localizedCaseInsensitiveContains("active") {
            throw HueEntertainmentError.entertainmentConfigurationBusy
        }
        throw HueEntertainmentError.bridge(error.description)
    }
}

private struct PairRequest: Encodable { let devicetype: String; let generateclientkey: Bool }
private struct PairEntry: Decodable { let success: PairSuccess?; let error: PairError? }
private struct PairSuccess: Decodable { let username: String; let clientkey: String }
private struct PairError: Decodable { let type: Int; let description: String }
private struct StreamAction: Encodable { let action: String }
private struct ActionEnvelope: Decodable { let errors: [BridgeError] }
private struct BridgeError: Decodable { let description: String }
private struct ConfigurationEnvelope: Decodable { let data: [RawConfiguration]; let errors: [BridgeError] }
private struct RawConfiguration: Decodable {
    let id: String
    let metadata: Metadata
    let status: String
    let channels: [RawChannel]
    let activeStreamer: ResourceReference?
    enum CodingKeys: String, CodingKey {
        case id, metadata, status, channels
        case activeStreamer = "active_streamer"
    }
}
private struct Metadata: Decodable { let name: String }
private struct RawChannel: Decodable {
    let channelID: Int
    let position: Position
    let members: [Member]
    enum CodingKeys: String, CodingKey { case channelID = "channel_id", position, members }
}
private struct Position: Decodable { let x: Double; let y: Double; let z: Double }
private struct Member: Decodable { let service: ResourceReference }
private struct ResourceReference: Decodable { let rid: String }
