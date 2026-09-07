import Foundation
import HueEntertainmentKit

public struct HueTimelineAction: Sendable {
    public let start: Duration
    public let end: Duration?
    public let effect: any HueEffect

    public init(start: Duration, end: Duration? = nil, effect: any HueEffect) {
        self.start = start
        self.end = end
        self.effect = effect
    }
}

public struct HueTimeline: Sendable {
    public let actions: [HueTimelineAction]

    public init(actions: [HueTimelineAction]) {
        self.actions = actions.sorted { $0.start < $1.start }
    }

    public func render(
        at time: Duration,
        channels: [HueEntertainmentChannel],
        mixer: HueEffectMixer = .init()
    ) throws -> HueFrame {
        let effects: [any HueEffect] = actions.compactMap { action in
            guard time >= action.start, action.end.map({ time < $0 }) ?? true else { return nil }
            return OffsetEffect(base: action.effect, offset: action.start)
        }
        return try mixer.render(effects: effects, channels: channels, at: time)
    }
}

private struct OffsetEffect: HueEffect {
    let base: any HueEffect
    let offset: Duration
    var layer: Int { base.layer }
    func color(at time: Duration, for channel: HueEntertainmentChannel) -> HueRGBA {
        base.color(at: time - offset, for: channel)
    }
}
