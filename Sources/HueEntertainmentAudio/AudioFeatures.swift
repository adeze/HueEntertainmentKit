import HueEntertainmentAudioRT

public struct HueAudioFeatures: Sendable, Equatable {
    public let hostTime: UInt64
    public let rms: Float
    public let peak: Float
    public let spectralCentroid: Float
    public let transientStrength: Float
    public let bandEnergy: (Float, Float, Float, Float, Float, Float, Float, Float)

    public init(
        hostTime: UInt64,
        rms: Float,
        peak: Float,
        spectralCentroid: Float,
        transientStrength: Float,
        bandEnergy: (Float, Float, Float, Float, Float, Float, Float, Float)
    ) {
        self.hostTime = hostTime; self.rms = rms; self.peak = peak
        self.spectralCentroid = spectralCentroid; self.transientStrength = transientStrength
        self.bandEnergy = bandEnergy
    }

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.hostTime == rhs.hostTime && lhs.rms == rhs.rms && lhs.peak == rhs.peak &&
        lhs.spectralCentroid == rhs.spectralCentroid && lhs.transientStrength == rhs.transientStrength &&
        lhs.bands == rhs.bands
    }

    public var bands: [Float] {
        [bandEnergy.0, bandEnergy.1, bandEnergy.2, bandEnergy.3, bandEnergy.4, bandEnergy.5, bandEnergy.6, bandEnergy.7]
    }
}

public final class HueAudioFeatureMailbox: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<hue_feature_mailbox_t>

    public init() {
        storage = .allocate(capacity: 1)
        hue_feature_mailbox_init(storage)
    }

    deinit { storage.deallocate() }

    /// Allocation-free and lock-free after mailbox initialization.
    public func publish(_ features: HueAudioFeatures) {
        withUnsafePointer(to: features.bandEnergy) { tuplePointer in
            tuplePointer.withMemoryRebound(to: Float.self, capacity: 8) { bandPointer in
                hue_feature_mailbox_publish(storage, features.hostTime, features.rms, features.peak,
                    features.spectralCentroid, features.transientStrength, bandPointer)
            }
        }
    }

    public func latest() -> HueAudioFeatures? {
        var hostTime: UInt64 = 0
        var rms: Float = 0, peak: Float = 0, centroid: Float = 0, transient: Float = 0
        var bands = [Float](repeating: 0, count: 8)
        let available = bands.withUnsafeMutableBufferPointer { pointer in
            hue_feature_mailbox_read(storage, &hostTime, &rms, &peak, &centroid, &transient, pointer.baseAddress!)
        }
        guard available != 0 else { return nil }
        return HueAudioFeatures(hostTime: hostTime, rms: rms, peak: peak, spectralCentroid: centroid,
            transientStrength: transient, bandEnergy: (bands[0], bands[1], bands[2], bands[3], bands[4], bands[5], bands[6], bands[7]))
    }
}
