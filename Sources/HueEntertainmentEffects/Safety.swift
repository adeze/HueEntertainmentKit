import Collections
import Foundation
import HueEntertainmentKit

#if canImport(AsyncAlgorithms)
import AsyncAlgorithms
#endif

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
///
/// Uses an allocation-free `Deque` sliding window from `swift-collections` to enforce
/// photosensitivity limits below 5 Hz.
public struct HueSafeFrameLimiter: Sendable {
    public let policy: HueEffectSafetyPolicy
    private var previous: HueFrame?
    private var transitionHistory = Deque<Duration>()

    public init(policy: HueEffectSafetyPolicy = .init()) {
        self.policy = policy
    }

    public mutating func limit(_ candidate: HueFrame, at time: Duration) throws -> HueFrame {
        let clamped = try HueFrame(colors: candidate.colors.map { entry in
            HueChannelColor(channelID: entry.channelID, color: try HueRGBColor(
                red: min(entry.color.red, policy.maximumComponent),
                green: min(entry.color.green, policy.maximumComponent),
                blue: min(entry.color.blue, policy.maximumComponent)
            ))
        })

        guard let previous else {
            self.previous = clamped
            transitionHistory.append(time)
            return clamped
        }

        guard brightnessChanged(previous, clamped) else {
            return previous
        }

        // Purge timestamps older than 1 second from the sliding window
        while let oldest = transitionHistory.first, time - oldest >= .seconds(1) {
            transitionHistory.removeFirst()
        }

        // Check if adding this transition would exceed the maximum frequency in the last second
        let maxAllowed = Int(policy.maximumBrightnessChangeFrequency)
        if transitionHistory.count >= maxAllowed {
            return previous
        }

        // Enforce minimum interval between consecutive transitions
        let minimumInterval = Duration.seconds(1 / policy.maximumBrightnessChangeFrequency)
        if let lastTransition = transitionHistory.last, time - lastTransition < minimumInterval {
            return previous
        }

        self.previous = clamped
        transitionHistory.append(time)
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

#if canImport(AsyncAlgorithms)
extension AsyncSequence where Element == HueFrame, Self: Sendable {
    /// Paces an asynchronous sequence of candidate frames to the entertainment frame rate (default 50 Hz).
    public func paceForEntertainment(frameRate: Double = 50) -> some AsyncSequence<HueFrame, Failure> {
        let interval = Duration.seconds(1.0 / Swift.min(Swift.max(frameRate, 25), 60))
        return self._throttle(for: interval, latest: true)
    }
}
#endif
