import Foundation
import HueEntertainmentKit

public struct HueEffectSafetyPolicy: Sendable, Equatable {
    public let maximumComponent: Double
    public let maximumBrightnessChangeFrequency: Double

    public init(maximumComponent: Double = 0.8, maximumBrightnessChangeFrequency: Double = 4) {
        self.maximumComponent = min(max(maximumComponent, 0), 1)
        self.maximumBrightnessChangeFrequency = min(max(maximumBrightnessChangeFrequency, 0.1), 4.9)
    }
}

/// Holds the last accepted frame between brightness transitions while the transport
/// repeats that frame at its independent 50 Hz delivery cadence.
public struct HueSafeFrameLimiter: Sendable {
    public let policy: HueEffectSafetyPolicy
    private var previous: HueFrame?
    private var previousChangeTime: Duration?

    public init(policy: HueEffectSafetyPolicy = .init()) { self.policy = policy }

    public mutating func limit(_ candidate: HueFrame, at time: Duration) throws -> HueFrame {
        let clamped = try HueFrame(colors: candidate.colors.map { entry in
            HueChannelColor(channelID: entry.channelID, color: try HueRGBColor(
                red: min(entry.color.red, policy.maximumComponent),
                green: min(entry.color.green, policy.maximumComponent),
                blue: min(entry.color.blue, policy.maximumComponent)
            ))
        })
        guard let previous, let previousChangeTime else {
            self.previous = clamped
            self.previousChangeTime = time
            return clamped
        }
        guard brightnessChanged(previous, clamped) else { return previous }
        let minimumInterval = Duration.seconds(1 / policy.maximumBrightnessChangeFrequency)
        guard time - previousChangeTime >= minimumInterval else { return previous }
        self.previous = clamped
        self.previousChangeTime = time
        return clamped
    }

    private func brightnessChanged(_ lhs: HueFrame, _ rhs: HueFrame) -> Bool {
        guard lhs.colors.count == rhs.colors.count else { return true }
        return zip(lhs.colors, rhs.colors).contains { left, right in
            left.channelID != right.channelID || abs(luminance(left.color) - luminance(right.color)) > 0.01
        }
    }

    private func luminance(_ color: HueRGBColor) -> Double {
        0.2126 * color.red + 0.7152 * color.green + 0.0722 * color.blue
    }
}
