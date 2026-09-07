import Foundation
import HueEntertainmentKit

public struct HueRGBA: Sendable, Equatable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    public static let clear = HueRGBA(red: 0, green: 0, blue: 0, alpha: 0)
}

public protocol HueEffect: Sendable {
    var layer: Int { get }
    func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA
}

public struct HueAnimatedColor: Sendable {
    public let red: HueAnimation, green: HueAnimation, blue: HueAnimation, alpha: HueAnimation
    public init(red: HueAnimation, green: HueAnimation, blue: HueAnimation, alpha: HueAnimation = .constant(1)) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    func value(at time: Duration) -> HueRGBA {
        HueRGBA(red: red.value(at: time), green: green.value(at: time), blue: blue.value(at: time), alpha: alpha.value(at: time))
    }
}

public struct HueAreaEffect: HueEffect {
    public let layer: Int
    public let minimum: SIMD2<Double>
    public let maximum: SIMD2<Double>
    public let color: HueAnimatedColor
    public init(layer: Int, minimum: SIMD2<Double>, maximum: SIMD2<Double>, color: HueAnimatedColor) {
        self.layer = layer; self.minimum = minimum; self.maximum = maximum; self.color = color
    }
    public func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA {
        guard (minimum.x...maximum.x).contains(channel.position.x),
              (minimum.y...maximum.y).contains(channel.position.y) else { return .clear }
        return color.value(at: time)
    }
}

public struct HueLightSourceEffect: HueEffect {
    public let layer: Int
    public let locationX: HueAnimation
    public let locationY: HueAnimation
    public let radius: HueAnimation
    public let color: HueAnimatedColor
    public init(
        layer: Int, locationX: HueAnimation, locationY: HueAnimation,
        radius: HueAnimation, color: HueAnimatedColor
    ) {
        self.layer = layer; self.locationX = locationX; self.locationY = locationY
        self.radius = radius; self.color = color
    }
    public init(layer: Int, location: SIMD2<Double>, radius: HueAnimation, color: HueAnimatedColor) {
        self.init(layer: layer, locationX: .constant(location.x), locationY: .constant(location.y),
            radius: radius, color: color)
    }
    public func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA {
        let location = SIMD2(locationX.value(at: time), locationY.value(at: time))
        let delta = SIMD2(channel.position.x, channel.position.y) - location
        let distance = sqrt(delta.x * delta.x + delta.y * delta.y)
        let currentRadius = max(radius.value(at: time), 0.000_001)
        guard distance < currentRadius else { return .clear }
        var value = color.value(at: time)
        value.alpha *= 1 - distance / currentRadius
        return value
    }
}

public struct HueMultiChannelEffect: HueEffect {
    public struct Source: Sendable {
        public let location: SIMD2<Double>
        public let color: HueAnimatedColor
        public init(location: SIMD2<Double>, color: HueAnimatedColor) { self.location = location; self.color = color }
    }
    public let layer: Int
    public let sources: [Source]
    private let assignments: [UInt8: Int]
    public init(layer: Int, sources: [Source], channels: [HueEntertainmentChannel]) {
        self.layer = layer
        self.sources = sources
        self.assignments = Self.assign(sources: sources, channels: channels)
    }
    public func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA {
        guard let sourceIndex = assignments[channel.id], sources.indices.contains(sourceIndex) else { return .clear }
        let source = sources[sourceIndex]
        return source.color.value(at: time)
    }

    private static func distance(_ location: SIMD2<Double>, _ channel: HueEntertainmentChannel) -> Double {
        hypot(location.x - channel.position.x, location.y - channel.position.y)
    }

    private static func assign(sources: [Source], channels: [HueEntertainmentChannel]) -> [UInt8: Int] {
        guard !sources.isEmpty else { return [:] }
        var remaining = channels
        var output: [UInt8: Int] = [:]
        for sourceIndex in sources.indices where !remaining.isEmpty {
            let best = remaining.indices.min {
                distance(sources[sourceIndex].location, remaining[$0]) < distance(sources[sourceIndex].location, remaining[$1])
            }!
            output[remaining[best].id] = sourceIndex
            remaining.remove(at: best)
        }
        for channel in remaining {
            let sourceIndex = sources.indices.min {
                distance(sources[$0].location, channel) < distance(sources[$1].location, channel)
            }!
            output[channel.id] = sourceIndex
        }
        return output
    }
}

public struct HueLightIteratorEffect: HueEffect {
    public enum Mode: Sendable { case single, cycle, bounce }
    public let layer: Int
    public let orderedChannelIDs: [UInt8]
    public let offset: Duration
    public let mode: Mode
    public let color: HueAnimatedColor
    public init(layer: Int, orderedChannelIDs: [UInt8], offset: Duration, mode: Mode, color: HueAnimatedColor) {
        self.layer = layer; self.orderedChannelIDs = orderedChannelIDs; self.offset = offset; self.mode = mode; self.color = color
    }
    public func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA {
        guard let rawIndex = orderedChannelIDs.firstIndex(of: channel.id), !orderedChannelIDs.isEmpty else { return .clear }
        let index: Int
        switch mode {
        case .single: index = rawIndex
        case .cycle: index = rawIndex
        case .bounce:
            let period = max(1, orderedChannelIDs.count * 2 - 2)
            let phase = rawIndex % period
            index = phase < orderedChannelIDs.count ? phase : period - phase
        }
        let local = time - offset * index
        guard local >= .zero else { return .clear }
        if mode == .single, color.red.duration > .zero, local > color.red.duration { return .clear }
        return color.value(at: local)
    }
}

public struct HueEffectMixer: Sendable {
    public let maximumComponent: Double
    public init(maximumComponent: Double = 0.8) { self.maximumComponent = min(max(maximumComponent, 0), 1) }

    public func render(
        effects: [any HueEffect],
        channels: [HueEntertainmentChannel],
        at time: Duration
    ) throws -> HueFrame {
        let sorted = effects.sorted { $0.layer < $1.layer }
        let colors = try channels.map { channel in
            var mixed = SIMD3<Double>.zero
            for effect in sorted {
                let color = effect.color(at: time, for: channel)
                let alpha = min(max(color.alpha, 0), 1)
                let top = SIMD3(color.red, color.green, color.blue)
                mixed = top * alpha + mixed * (1 - alpha)
            }
            return HueChannelColor(channelID: channel.id, color: try HueRGBColor(
                red: min(max(mixed.x, 0), maximumComponent),
                green: min(max(mixed.y, 0), maximumComponent),
                blue: min(max(mixed.z, 0), maximumComponent)
            ))
        }
        return try HueFrame(colors: colors)
    }
}
