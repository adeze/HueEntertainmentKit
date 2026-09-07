import HueEntertainmentAudio
import Testing

@Suite struct HueEntertainmentAudioTests {
    @Test func mailboxPublishesLatestCompleteSnapshot() {
        let mailbox = HueAudioFeatureMailbox()
        #expect(mailbox.latest() == nil)
        let first = HueAudioFeatures(hostTime: 1, rms: 0.1, peak: 0.2, spectralCentroid: 400,
            transientStrength: 0.3, bandEnergy: (0, 1, 2, 3, 4, 5, 6, 7))
        let latest = HueAudioFeatures(hostTime: 2, rms: 0.4, peak: 0.5, spectralCentroid: 800,
            transientStrength: 0.6, bandEnergy: (7, 6, 5, 4, 3, 2, 1, 0))
        mailbox.publish(first)
        mailbox.publish(latest)
        #expect(mailbox.latest() == latest)
    }
}
