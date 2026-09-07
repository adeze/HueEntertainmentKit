import AudioToolbox
import AVFAudio
import HueEntertainmentAudio

public final class HueAudioReactiveUnit: AUAudioUnit {
    private var inputBus: AUAudioUnitBus!
    private var outputBus: AUAudioUnitBus!
    private var inputs: AUAudioUnitBusArray!
    private var outputs: AUAudioUnitBusArray!
    private let mailbox = HueAudioFeatureMailbox()
    private let featureExtractor = RealtimeFeatureExtractor(sampleRate: 48_000)

    public override init(
        componentDescription: AudioComponentDescription,
        options: AudioComponentInstantiationOptions = []
    ) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        try super.init(componentDescription: componentDescription, options: options)
        inputBus = try AUAudioUnitBus(format: format)
        outputBus = try AUAudioUnitBus(format: format)
        inputs = AUAudioUnitBusArray(audioUnit: self, busType: .input, busses: [inputBus])
        outputs = AUAudioUnitBusArray(audioUnit: self, busType: .output, busses: [outputBus])
    }

    public override var inputBusses: AUAudioUnitBusArray { inputs }
    public override var outputBusses: AUAudioUnitBusArray { outputs }

    public override var internalRenderBlock: AUInternalRenderBlock {
        let mailbox = mailbox
        let featureExtractor = featureExtractor
        return { flags, timestamp, frameCount, _, outputData, _, pullInput in
            guard let pullInput else { return kAudioUnitErr_NoConnection }
            let status = pullInput(flags, timestamp, frameCount, 0, outputData)
            guard status == noErr else { return status }
            let buffers = UnsafeMutableAudioBufferListPointer(outputData)
            mailbox.publish(featureExtractor.extract(
                buffers: buffers,
                frameCount: Int(frameCount),
                hostTime: timestamp.pointee.mHostTime
            ))
            return noErr
        }
    }
}

/// Fixed-storage Goertzel bank. All arrays allocate during AU initialization, never on the render thread.
private final class RealtimeFeatureExtractor: @unchecked Sendable {
    private let centers: [Float] = [63, 125, 250, 500, 1_000, 2_000, 4_000, 8_000]
    private let coefficients: [Float]
    private var q1 = [Float](repeating: 0, count: 8)
    private var q2 = [Float](repeating: 0, count: 8)
    private var previousRMS: Float = 0

    init(sampleRate: Float) {
        coefficients = centers.map { 2 * cos(2 * .pi * $0 / sampleRate) }
    }

    func extract(
        buffers: UnsafeMutableAudioBufferListPointer,
        frameCount: Int,
        hostTime: UInt64
    ) -> HueAudioFeatures {
        for band in 0..<8 { q1[band] = 0; q2[band] = 0 }
        var sumSquares: Float = 0
        var peak: Float = 0
        var sampleCount = 0
        for buffer in buffers {
            guard let samples = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let count = min(frameCount, Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
            for index in 0..<count {
                let sample = samples[index]
                sumSquares += sample * sample
                peak = max(peak, abs(sample))
                for band in 0..<8 {
                    let q0 = sample + coefficients[band] * q1[band] - q2[band]
                    q2[band] = q1[band]
                    q1[band] = q0
                }
            }
            sampleCount += count
        }

        let divisor = Float(max(sampleCount, 1))
        let rms = min(sqrt(sumSquares / divisor), 1)
        var energy = (Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0), Float(0))
        withUnsafeMutablePointer(to: &energy) { tuplePointer in
            tuplePointer.withMemoryRebound(to: Float.self, capacity: 8) { values in
                for band in 0..<8 {
                    let power = max(0, q1[band] * q1[band] + q2[band] * q2[band]
                        - coefficients[band] * q1[band] * q2[band])
                    values[band] = min(sqrt(power) / divisor, 1)
                }
            }
        }
        let weighted = centers[0] * energy.0 + centers[1] * energy.1 + centers[2] * energy.2
            + centers[3] * energy.3 + centers[4] * energy.4 + centers[5] * energy.5
            + centers[6] * energy.6 + centers[7] * energy.7
        let total = energy.0 + energy.1 + energy.2 + energy.3 + energy.4 + energy.5 + energy.6 + energy.7
        let centroid = total > 0 ? weighted / total : 0
        let transient = min(max((rms - previousRMS) * 4, 0), 1)
        previousRMS = rms
        return HueAudioFeatures(
            hostTime: hostTime,
            rms: rms,
            peak: min(peak, 1),
            spectralCentroid: centroid,
            transientStrength: transient,
            bandEnergy: energy
        )
    }
}
