import Foundation

public enum HueTakeoverPolicy: Sendable { case failIfActive }

public enum HueSessionState: Sendable, Equatable {
    case idle
    case claiming
    case handshaking
    case streaming
    case releasing
    case failed(String)
}

public actor HueEntertainmentSession {
    public private(set) var state: HueSessionState = .idle
    private let control: any HueEntertainmentControl
    private let transport: any HueDatagramTransport
    private let encoder: HueStreamPacketEncoder
    private var configuration: HueEntertainmentConfiguration?
    private var sequence: UInt8 = 0
    private var latestFrame: HueFrame?
    private var pumpTask: Task<Void, Never>?
    private let frameInterval: Duration
    private var ownsConfiguration = false

    public init(
        control: any HueEntertainmentControl,
        transport: any HueDatagramTransport,
        encoder: HueStreamPacketEncoder = .init(),
        frameRate: Double = 50
    ) {
        self.control = control
        self.transport = transport
        self.encoder = encoder
        self.frameInterval = .seconds(1 / min(max(frameRate, 25), 60))
    }

    public func start(
        configuration: HueEntertainmentConfiguration,
        endpoint: HueBridgeEndpoint,
        credentials: HueCredentials,
        takeoverPolicy: HueTakeoverPolicy = .failIfActive
    ) async throws {
        guard state == .idle else { throw HueEntertainmentError.invalidState }
        if configuration.isActive { throw HueEntertainmentError.entertainmentConfigurationBusy }
        guard let applicationID = credentials.applicationID, !applicationID.isEmpty else {
            throw HueEntertainmentError.missingApplicationID
        }
        state = .claiming
        do {
            try await control.setStreamActive(configurationID: configuration.id, active: true)
            try await waitForOwnership(configurationID: configuration.id, applicationID: applicationID)
            ownsConfiguration = true
            state = .handshaking
            try await transport.connect(endpoint: endpoint, credentials: credentials)
            self.configuration = configuration
            sequence = 0
            state = .streaming
            pumpTask = Task { await self.pump() }
        } catch {
            await transport.close()
            if ownsConfiguration { try? await control.setStreamActive(configurationID: configuration.id, active: false) }
            ownsConfiguration = false
            state = .failed(String(describing: error))
            throw error
        }
    }

    /// Replaces any unsent frame. At most one stale frame is retained.
    public func submit(_ frame: HueFrame) throws {
        guard state == .streaming else { throw HueEntertainmentError.invalidState }
        latestFrame = frame
    }

    public func stop() async throws {
        guard let configuration else {
            await transport.close()
            state = .idle
            return
        }
        state = .releasing
        latestFrame = nil
        pumpTask?.cancel()
        await pumpTask?.value
        pumpTask = nil
        await transport.close()
        if ownsConfiguration {
            do {
                try await control.setStreamActive(configurationID: configuration.id, active: false)
                try await waitForRelease(configurationID: configuration.id)
            } catch {
                ownsConfiguration = false
                self.configuration = nil
                state = .failed(String(describing: error))
                throw error
            }
        }
        ownsConfiguration = false
        self.configuration = nil
        state = .idle
    }

    private func pump() async {
        while !Task.isCancelled, let configuration {
            guard let frame = latestFrame else {
                try? await Task.sleep(for: frameInterval)
                continue
            }
            let packet = encoder.encode(configurationID: configuration.id, sequence: sequence, frame: frame)
            sequence &+= 1
            do {
                try await transport.send(packet)
            } catch {
                state = .failed(String(describing: error))
                latestFrame = nil
                await transport.close()
                if ownsConfiguration { try? await control.setStreamActive(configurationID: configuration.id, active: false) }
                ownsConfiguration = false
                self.configuration = nil
                break
            }
            try? await Task.sleep(for: frameInterval)
        }
        pumpTask = nil
    }

    private func waitForOwnership(configurationID: UUID, applicationID: String) async throws {
        for _ in 0..<20 {
            switch try await control.streamStatus(configurationID: configurationID) {
            case .inactive:
                try await Task.sleep(for: .milliseconds(100))
            case .active(let activeApplicationID):
                guard activeApplicationID == applicationID else {
                    throw HueEntertainmentError.entertainmentConfigurationBusy
                }
                return
            }
        }
        throw HueEntertainmentError.connectionFailed("Timed out waiting for entertainment ownership")
    }

    private func waitForRelease(configurationID: UUID) async throws {
        for _ in 0..<20 {
            if case .inactive = try await control.streamStatus(configurationID: configurationID) { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        throw HueEntertainmentError.connectionFailed("Timed out confirming entertainment release")
    }
}
