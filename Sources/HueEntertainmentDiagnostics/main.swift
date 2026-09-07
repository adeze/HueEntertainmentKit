import Foundation
import HueEntertainmentKit

@main
enum Diagnostics {
    static func main() async {
        do {
            let arguments = Array(CommandLine.arguments.dropFirst())
            switch arguments.first {
            case "discover":
                let endpoints = try await HueBridgeDiscovery().discoverBonjour()
                for endpoint in endpoints { print(endpoint.host) }
            case "inspect":
                try await inspect(arguments: Array(arguments.dropFirst()))
            default:
                print("Usage: hue-entertainment-diagnostics discover | inspect --host HOST --bridge-id ID --credential-alias ALIAS")
            }
        } catch {
            fputs("error: \(String(describing: error))\n", stderr)
            Foundation.exit(EXIT_FAILURE)
        }
    }

    private static func inspect(arguments: [String]) async throws {
        guard let host = value(after: "--host", in: arguments),
              let bridgeID = value(after: "--bridge-id", in: arguments),
              let alias = value(after: "--credential-alias", in: arguments)
        else { throw HueEntertainmentError.invalidEndpoint }
        let store = KeychainHueCredentialStore()
        guard let credentials = try store.load(alias: alias) else {
            throw HueEntertainmentError.authenticationRequired
        }
        let endpoint = try HueBridgeEndpoint(host: host, bridgeID: bridgeID)
        let client = HueBridgeClient(
            endpoint: endpoint,
            credentials: credentials,
            transport: URLSessionHueHTTPTransport(trustPolicy: .hueBridge(bridgeID: bridgeID))
        )
        let configurations = try await client.entertainmentConfigurations()
        for configuration in configurations {
            print("\(configuration.id.uuidString)\t\(configuration.isActive ? "active" : "inactive")\t\(configuration.channels.count) channels\t\(configuration.name)")
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
