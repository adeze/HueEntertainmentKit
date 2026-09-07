import Foundation

public enum HueEntertainmentError: Error, Equatable, Sendable {
    case invalidEndpoint
    case invalidBridgeIdentifier
    case invalidConfigurationIdentifier
    case invalidChannelIdentifier
    case invalidColorComponent
    case invalidClientKey
    case missingApplicationID
    case untrustedBridge
    case authenticationRequired
    case linkButtonRequired
    case entertainmentConfigurationBusy
    case malformedResponse
    case httpStatus(Int)
    case bridge(String)
    case invalidState
    case connectionFailed(String)
}

public struct HueBridgeEndpoint: Hashable, Codable, Sendable {
    public let host: String
    public let port: Int
    public let bridgeID: String?

    public init(host: String, port: Int = 443, bridgeID: String? = nil) throws {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port == 443 ? nil : port
        guard !host.isEmpty, (1...65_535).contains(port), components.url != nil else {
            throw HueEntertainmentError.invalidEndpoint
        }
        if let bridgeID {
            guard Self.isValidBridgeID(bridgeID) else { throw HueEntertainmentError.invalidBridgeIdentifier }
        }
        self.host = host
        self.port = port
        self.bridgeID = bridgeID?.uppercased()
    }

    private static func isValidBridgeID(_ value: String) -> Bool {
        value.count == 16 && value.allSatisfy(\.isHexDigit)
    }

    public var baseURL: URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.port = port == 443 ? nil : port
        return components.url!
    }
}

public struct HueBridgeIdentity: Hashable, Codable, Sendable {
    public let id: String
    public let endpoint: HueBridgeEndpoint

    public init(id: String, endpoint: HueBridgeEndpoint) throws {
        let normalized = id.uppercased()
        guard normalized.count == 16, normalized.allSatisfy(\.isHexDigit) else {
            throw HueEntertainmentError.invalidBridgeIdentifier
        }
        self.id = normalized
        self.endpoint = endpoint
    }
}

public struct HueCredentials: Codable, Sendable, CustomStringConvertible {
    public let applicationKey: String
    public let clientKey: String
    public let applicationID: String?

    public init(applicationKey: String, clientKey: String, applicationID: String? = nil) throws {
        guard !applicationKey.isEmpty else { throw HueEntertainmentError.authenticationRequired }
        guard clientKey.count == 32, clientKey.allSatisfy(\.isHexDigit) else {
            throw HueEntertainmentError.invalidClientKey
        }
        self.applicationKey = applicationKey
        self.clientKey = clientKey
        self.applicationID = applicationID
    }

    public var description: String { "HueCredentials(redacted)" }
}

public struct HueEntertainmentChannel: Hashable, Codable, Sendable {
    public let id: UInt8
    public let position: SIMD3<Double>
    public let memberResourceIDs: [String]

    public init(id: Int, position: SIMD3<Double>, memberResourceIDs: [String] = []) throws {
        guard (0..<20).contains(id), let id = UInt8(exactly: id) else {
            throw HueEntertainmentError.invalidChannelIdentifier
        }
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            throw HueEntertainmentError.invalidChannelIdentifier
        }
        self.id = id
        self.position = position
        self.memberResourceIDs = memberResourceIDs
    }
}

public struct HueEntertainmentConfiguration: Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let isActive: Bool
    public let channels: [HueEntertainmentChannel]

    public init(id: UUID, name: String, isActive: Bool, channels: [HueEntertainmentChannel]) {
        self.id = id
        self.name = name
        self.isActive = isActive
        self.channels = channels.sorted { $0.id < $1.id }
    }
}

public struct HueRGBColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) throws {
        guard [red, green, blue].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw HueEntertainmentError.invalidColorComponent
        }
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let black = try! HueRGBColor(red: 0, green: 0, blue: 0)
}

public enum HueColorSpace: UInt8, Codable, Sendable {
    case rgb = 0x00
    case xyBrightness = 0x01
}

public struct HueXYBrightness: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let brightness: Double

    public init(x: Double, y: Double, brightness: Double) throws {
        guard [x, y, brightness].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw HueEntertainmentError.invalidColorComponent
        }
        self.x = x
        self.y = y
        self.brightness = brightness
    }
}

public struct HueXYChannelColor: Hashable, Codable, Sendable {
    public let channelID: UInt8
    public let color: HueXYBrightness

    public init(channelID: UInt8, color: HueXYBrightness) {
        self.channelID = channelID
        self.color = color
    }
}

public struct HueXYFrame: Hashable, Codable, Sendable {
    public let colors: [HueXYChannelColor]

    public init(colors: [HueXYChannelColor]) throws {
        let ids = colors.map(\.channelID)
        guard colors.count <= 20, Set(ids).count == ids.count else {
            throw HueEntertainmentError.invalidChannelIdentifier
        }
        self.colors = colors.sorted { $0.channelID < $1.channelID }
    }
}

public struct HueChannelColor: Hashable, Codable, Sendable {
    public let channelID: UInt8
    public let color: HueRGBColor

    public init(channelID: UInt8, color: HueRGBColor) {
        self.channelID = channelID
        self.color = color
    }
}

public struct HueFrame: Hashable, Codable, Sendable {
    public let colors: [HueChannelColor]

    public init(colors: [HueChannelColor]) throws {
        guard colors.count <= 20 else { throw HueEntertainmentError.invalidChannelIdentifier }
        let ids = colors.map(\.channelID)
        guard Set(ids).count == ids.count else { throw HueEntertainmentError.invalidChannelIdentifier }
        self.colors = colors.sorted { $0.channelID < $1.channelID }
    }
}
