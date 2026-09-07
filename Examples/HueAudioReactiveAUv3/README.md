# HueAudioReactiveAUv3

Reference macOS and tvOS containing apps plus AUv3 audio-effect extensions. The
Xcode project is included and reproducible from `project.yml` with XcodeGen. Assign
your own development team and replace
the placeholder App Group and Keychain group identifiers before signing.

```bash
cd Examples/HueAudioReactiveAUv3
xcodegen generate
xcodebuild -project HueAudioReactiveAUv3.xcodeproj -scheme HueAudioReactiveMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project HueAudioReactiveAUv3.xcodeproj -scheme HueAudioReactiveTV \
  -destination 'generic/platform=tvOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

The extension is pass-through. Its render callback computes bounded RMS, peak,
transient strength, eight-band energy, and spectral centroid values, then publishes
a fixed snapshot through `HueAudioFeatureMailbox`. It performs
no network, Keychain, filesystem, logging, actor, or UI operation. A non-real-time
controller may consume snapshots and send frames at no more than 50 Hz.

tvOS hosts expose only audio they explicitly route through the extension. This sample
cannot capture system-wide Apple TV audio.
