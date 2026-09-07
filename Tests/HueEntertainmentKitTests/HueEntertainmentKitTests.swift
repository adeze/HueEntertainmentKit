import Foundation
import HueEntertainmentKit
import HueEntertainmentTesting
import NIOCore
import Security
import Testing

@Suite struct HueEntertainmentKitTests {
    @Test func packetGoldenBytesAndSequence() throws {
        let id = UUID(uuidString: "00112233-4455-6677-8899-aabbccddeeff")!
        let frame = try HueFrame(colors: [
            HueChannelColor(channelID: 2, color: try HueRGBColor(red: 1, green: 0.5, blue: 0)),
        ])
        var packet = HueStreamPacketEncoder().encode(configurationID: id, sequence: 255, frame: frame)
        #expect(packet.readString(length: 9) == "HueStream")
        #expect(packet.readBytes(length: 7) == [2, 0, 255, 0, 0, 0, 0])
        #expect(packet.readString(length: 36) == id.uuidString.lowercased())
        #expect(packet.readBytes(length: 7) == [2, 255, 255, 128, 0, 0, 0])
        let xy = try HueXYFrame(colors: [.init(channelID: 1, color: .init(x: 0.25, y: 0.5, brightness: 1))])
        var xyPacket = HueStreamPacketEncoder().encode(configurationID: id, sequence: 0, frame: xy)
        xyPacket.moveReaderIndex(forwardBy: 9)
        #expect(xyPacket.readBytes(length: 7) == [2, 0, 0, 0, 0, 1, 0])
        xyPacket.moveReaderIndex(forwardBy: 36)
        #expect(xyPacket.readBytes(length: 7) == [1, 64, 0, 128, 0, 255, 255])
    }

    @Test func validatesInputsAndRedactsCredentials() throws {
        #expect(throws: HueEntertainmentError.invalidColorComponent) { try HueRGBColor(red: 1.1, green: 0, blue: 0) }
        #expect(throws: HueEntertainmentError.invalidClientKey) { try HueCredentials(applicationKey: "app", clientKey: "xyz") }
        let credentials = try HueCredentials(applicationKey: "secret-app", clientKey: "00112233445566778899aabbccddeeff")
        #expect(credentials.description == "HueCredentials(redacted)")
        let store = KeychainHueCredentialStore(service: "com.adeze.HueEntertainmentKit.tests")
        let alias = UUID().uuidString
        defer { try? store.remove(alias: alias) }
        try store.save(credentials, alias: alias)
        #expect(try store.load(alias: alias)?.clientKey == credentials.clientKey)
        #expect(HueBridgeCertificateAuthority.rootCertificates.count == 2)
        #expect(HueBridgeCertificateAuthority.rootCertificates.allSatisfy {
            SecCertificateCreateWithData(nil, $0 as CFData) != nil
        })
        #expect(throws: HueEntertainmentError.invalidChannelIdentifier) {
            try HueFrame(colors: (0..<21).map {
                HueChannelColor(channelID: UInt8($0), color: .black)
            })
        }
    }

    @Test func bridgeClientDecodesConfiguration() async throws {
        let body = Data(#"{"data":[{"id":"00112233-4455-6677-8899-aabbccddeeff","metadata":{"name":"TV"},"status":"inactive","channels":[{"channel_id":1,"position":{"x":-0.5,"y":0.2,"z":1.0},"members":[{"service":{"rid":"light-1"}}]}]}],"errors":[]}"#.utf8)
        let transport = MockHueHTTPTransport(responses: [.init(statusCode: 200, body: body)])
        let credentials = try HueCredentials(applicationKey: "app", clientKey: "00112233445566778899aabbccddeeff", applicationID: "app-id")
        let client = HueBridgeClient(endpoint: try .init(host: "bridge.local"), credentials: credentials, transport: transport)
        let configurations = try await client.entertainmentConfigurations()
        #expect(configurations.count == 1)
        #expect(configurations[0].channels[0].memberResourceIDs == ["light-1"])
    }

    @Test func pairingHandlesPushlinkAndCapturesApplicationID() async throws {
        let endpoint = try HueBridgeEndpoint(host: "bridge.local")
        let waiting = MockHueHTTPTransport(responses: [
            .init(statusCode: 200, body: Data(#"[{"error":{"type":101,"description":"link button not pressed"}}]"#.utf8)),
        ])
        let waitingClient = HueBridgeClient(endpoint: endpoint, transport: waiting)
        await #expect(throws: HueEntertainmentError.linkButtonRequired) {
            try await waitingClient.pair(deviceType: "tests#local")
        }

        let paired = MockHueHTTPTransport(responses: [
            .init(statusCode: 200, body: Data(#"[{"success":{"username":"app-key","clientkey":"00112233445566778899aabbccddeeff"}}]"#.utf8)),
            .init(statusCode: 200, headers: ["hue-application-id": "app-id"], body: Data()),
        ])
        let result = try await HueBridgeClient(endpoint: endpoint, transport: paired).pair(deviceType: "tests#local")
        #expect(result.credentials.applicationID == "app-id")
        #expect(result.credentials.description == "HueCredentials(redacted)")
    }

    @Test func sessionRejectsBusyAndReleasesOwnedConfiguration() async throws {
        let channel = try HueEntertainmentChannel(id: 0, position: .zero)
        let busy = HueEntertainmentConfiguration(id: UUID(), name: "Busy", isActive: true, channels: [channel])
        let free = HueEntertainmentConfiguration(id: UUID(), name: "Free", isActive: false, channels: [channel])
        let control = MockHueEntertainmentControl()
        let transport = MockHueDatagramTransport()
        let session = HueEntertainmentSession(control: control, transport: transport)
        let endpoint = try HueBridgeEndpoint(host: "bridge.local")
        let credentials = try HueCredentials(applicationKey: "app", clientKey: "00112233445566778899aabbccddeeff", applicationID: "app-id")
        await #expect(throws: HueEntertainmentError.entertainmentConfigurationBusy) {
            try await session.start(configuration: busy, endpoint: endpoint, credentials: credentials)
        }
        try await session.start(configuration: free, endpoint: endpoint, credentials: credentials)
        try await session.submit(try HueFrame(colors: [.init(channelID: 0, color: .black)]))
        try await Task.sleep(for: .milliseconds(55))
        #expect(await transport.packets.count >= 2)
        try await session.stop()
        let transitions = await control.transitions
        #expect(transitions.map(\.1) == [true, false])
        #expect(await session.state == .idle)
    }
}
