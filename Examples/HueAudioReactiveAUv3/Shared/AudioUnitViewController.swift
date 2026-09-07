import AudioToolbox
#if os(macOS)
import CoreAudioKit
public typealias HuePlatformAudioUnitViewController = AUViewController
#else
import UIKit
public typealias HuePlatformAudioUnitViewController = UIViewController
#endif

public final class AudioUnitViewController: HuePlatformAudioUnitViewController, AUAudioUnitFactory {
    nonisolated public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        try HueAudioReactiveUnit(componentDescription: componentDescription)
    }
}
