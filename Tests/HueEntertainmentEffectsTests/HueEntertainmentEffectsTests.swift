import HueEntertainmentEffects
import HueEntertainmentKit
import Testing

@Suite struct HueEntertainmentEffectsTests {
    @Test func deterministicMixingAndSafetyLimit() throws {
        let channel = try HueEntertainmentChannel(id: 3, position: SIMD3(-0.5, 0, 0))
        let red = HueAnimatedColor(red: .constant(1), green: .constant(0), blue: .constant(0))
        let overlay = HueAnimatedColor(red: .constant(0), green: .constant(0), blue: .constant(1), alpha: .constant(0.5))
        let effects: [any HueEffect] = [
            HueAreaEffect(layer: 0, minimum: SIMD2(-1, -1), maximum: SIMD2(1, 1), color: red),
            HueLightSourceEffect(layer: 1, location: SIMD2(-0.5, 0), radius: .constant(1), color: overlay),
        ]
        let frame = try HueEffectMixer(maximumComponent: 0.8).render(effects: effects, channels: [channel], at: .zero)
        #expect(frame.colors[0].color.red == 0.5)
        #expect(frame.colors[0].color.blue == 0.5)
    }

    @Test func animationsAreDeterministic() {
        let tween = HueAnimation.tween(from: 0, to: 1, duration: .seconds(2), easing: .linear)
        #expect(tween.value(at: .seconds(1)) == 0.5)
        let random = HueAnimation.seededRandom(min: 0, max: 1, interval: .seconds(1), seed: 42)
        #expect(random.value(at: .seconds(5)) == random.value(at: .seconds(5)))
    }

    @Test func safetyLimiterKeepsBrightnessChangesBelowFiveHertz() throws {
        var limiter = HueSafeFrameLimiter(policy: .init(maximumComponent: 0.8, maximumBrightnessChangeFrequency: 4))
        let black = try HueFrame(colors: [.init(channelID: 0, color: .black)])
        let white = try HueFrame(colors: [.init(channelID: 0, color: try .init(red: 1, green: 1, blue: 1))])
        _ = try limiter.limit(black, at: .zero)
        #expect(try limiter.limit(white, at: .milliseconds(100)) == black)
        let accepted = try limiter.limit(white, at: .milliseconds(250))
        #expect(accepted.colors[0].color.red == 0.8)
    }

    @Test func framePacingThrottlesBurst() async throws {
        let (stream, continuation) = AsyncStream.makeStream(of: HueFrame.self)
        let black = try HueFrame(colors: [.init(channelID: 0, color: .black)])
        let white = try HueFrame(colors: [.init(channelID: 0, color: try .init(red: 1, green: 1, blue: 1))])

        let pacedStream = stream.paceForEntertainment(frameRate: 50)
        let collectorTask = Task { () -> [HueFrame] in
            var results: [HueFrame] = []
            for await frame in pacedStream {
                results.append(frame)
                if results.count >= 2 { break }
            }
            return results
        }

        continuation.yield(black)
        try await Task.sleep(for: .milliseconds(30))
        continuation.yield(white)
        continuation.finish()

        let collected = await collectorTask.value
        #expect(collected.count == 2)
        #expect(collected[0] == black)
        #expect(collected[1] == white)
    }
}
