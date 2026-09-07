import SwiftUI

@main
struct HueAudioReactiveHost: App {
    var body: some Scene {
        WindowGroup {
            VStack(spacing: 16) {
                Text("Hue Audio Reactive AUv3")
                    .font(.title)
                Text("Pairing and entertainment-area selection belong in this containing app. The extension never accesses Keychain on its render thread.")
                    .multilineTextAlignment(.center)
            }
            .padding()
        }
    }
}
