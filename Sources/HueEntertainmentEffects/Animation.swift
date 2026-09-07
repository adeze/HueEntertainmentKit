import Foundation

public indirect enum HueAnimation: Sendable {
    case constant(Double)
    case curve([(time: Duration, value: Double)])
    case tween(from: Double, to: Double, duration: Duration, easing: Easing)
    case sequence([HueAnimation], repeatCount: Int?)
    case seededRandom(min: Double, max: Double, interval: Duration, seed: UInt64)

    public enum Easing: Sendable { case linear, quadraticInOut, sineInOut }

    public func value(at time: Duration) -> Double {
        switch self {
        case .constant(let value): return value
        case .curve(let points): return Self.curve(points, at: time)
        case .tween(let from, let to, let duration, let easing):
            let progress = duration > .zero ? min(max(time.seconds / duration.seconds, 0), 1) : 1
            return from + (to - from) * easing.apply(progress)
        case .sequence(let animations, let repeatCount):
            guard !animations.isEmpty else { return 0 }
            let durations = animations.map(\.duration)
            let cycle = durations.reduce(.zero, +)
            guard cycle > .zero else { return animations.last?.value(at: .zero) ?? 0 }
            let completed = Int(time.seconds / cycle.seconds)
            if let repeatCount, completed >= repeatCount { return animations.last?.value(at: animations.last!.duration) ?? 0 }
            var cursor = Duration.seconds(time.seconds.truncatingRemainder(dividingBy: cycle.seconds))
            for (animation, duration) in zip(animations, durations) {
                if cursor <= duration { return animation.value(at: cursor) }
                cursor -= duration
            }
            return animations.last?.value(at: animations.last!.duration) ?? 0
        case .seededRandom(let min, let max, let interval, let seed):
            guard interval > .zero else { return min }
            let bucket = UInt64(Swift.max(0, floor(time.seconds / interval.seconds)))
            var value = seed &+ bucket &* 0x9E3779B97F4A7C15
            value ^= value >> 30; value &*= 0xBF58476D1CE4E5B9
            value ^= value >> 27; value &*= 0x94D049BB133111EB
            value ^= value >> 31
            return min + (max - min) * Double(value) / Double(UInt64.max)
        }
    }

    public var duration: Duration {
        switch self {
        case .constant: return .zero
        case .curve(let points): return points.map(\.time).max() ?? .zero
        case .tween(_, _, let duration, _): return duration
        case .sequence(let animations, let repeatCount):
            let cycle = animations.map(\.duration).reduce(.zero, +)
            return repeatCount.map { cycle * $0 } ?? cycle
        case .seededRandom(_, _, let interval, _): return interval
        }
    }

    private static func curve(_ points: [(time: Duration, value: Double)], at time: Duration) -> Double {
        let sorted = points.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return 0 }
        if time <= first.time { return first.value }
        guard let upperIndex = sorted.firstIndex(where: { $0.time >= time }) else { return sorted.last!.value }
        let lower = sorted[upperIndex - 1], upper = sorted[upperIndex]
        let fraction = (time - lower.time).seconds / (upper.time - lower.time).seconds
        return lower.value + (upper.value - lower.value) * fraction
    }
}

private extension HueAnimation.Easing {
    func apply(_ x: Double) -> Double {
        switch self {
        case .linear: return x
        case .quadraticInOut: return x < 0.5 ? 2 * x * x : 1 - pow(-2 * x + 2, 2) / 2
        case .sineInOut: return -(cos(.pi * x) - 1) / 2
        }
    }
}

private extension Duration {
    var seconds: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
