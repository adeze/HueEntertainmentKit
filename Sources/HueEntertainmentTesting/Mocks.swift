import Foundation
import HueEntertainmentKit
import NIOCore

public actor MockHueHTTPTransport: HueHTTPTransport {
    public var responses: [HueHTTPResponse]
    public private(set) var requests: [HueHTTPRequest] = []

    public init(responses: [HueHTTPResponse]) { self.responses = responses }

    public func send(_ request: HueHTTPRequest) async throws -> HueHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw HueEntertainmentError.connectionFailed("No mock response") }
        return responses.removeFirst()
    }
}

public actor MockHueEntertainmentControl: HueEntertainmentControl {
    public private(set) var transitions: [(UUID, Bool)] = []
    public var error: HueEntertainmentError?
    public var applicationID: String
    private var active = false
    public init(error: HueEntertainmentError? = nil, applicationID: String = "app-id") {
        self.error = error
        self.applicationID = applicationID
    }
    public func setStreamActive(configurationID: UUID, active: Bool) async throws {
        if let error { throw error }
        transitions.append((configurationID, active))
        self.active = active
    }
    public func streamStatus(configurationID: UUID) async throws -> HueStreamStatus {
        active ? .active(applicationID: applicationID) : .inactive
    }
}

public actor MockHueDatagramTransport: HueDatagramTransport {
    public private(set) var packets: [ByteBuffer] = []
    public private(set) var connected = false
    public var connectionError: HueEntertainmentError?
    public init(connectionError: HueEntertainmentError? = nil) { self.connectionError = connectionError }
    public func connect(endpoint: HueBridgeEndpoint, credentials: HueCredentials) async throws {
        if let connectionError { throw connectionError }
        connected = true
    }
    public func send(_ packet: ByteBuffer) async throws { packets.append(packet) }
    public func close() async { connected = false }
}
