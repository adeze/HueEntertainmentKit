# HueEntertainmentKit

[![Swift 6.0+](https://img.shields.io/badge/Swift-6.0%2B-F05138.svg?style=flat&logo=swift)](https://swift.org)
[![Platforms](https://img.shields.io/badge/Platforms-macOS%2015+%20|%20iOS%2018+%20|%20tvOS%2018+%20|%20visionOS%202+-blue.svg?style=flat&logo=apple)](https://developer.apple.com)
[![License](https://img.shields.io/badge/License-Apache%202.0-green.svg)](LICENSE)
[![CI](https://github.com/adeze/HueEntertainmentKit/actions/workflows/ci.yml/badge.svg)](https://github.com/adeze/HueEntertainmentKit/actions/workflows/ci.yml)

An independent, clean-room Swift implementation of the **Philips Hue Entertainment API** for Apple platforms.

HueEntertainmentKit provides high-performance, real-time spatial lighting synchronization with strict security guarantees:
- **CLIP v2 HTTP**: Built on native `URLSession` with strict TLS certificate chain validation against official Hue Bridge root CAs.
- **HueStream v2 DTLS**: UDP streaming powered by Apple Network framework via `NIOTransportServices` with TLS 1.2 PSK encryption.
- **Photosensitivity Safety**: Built-in `HueSafeFrameLimiter` enforcing Philips Hue guidance to keep rapid brightness transitions under 5 Hz.
- **Real-Time Audio**: Lock-free, zero-allocation C11 atomic seqlock mailbox for high-frequency audio render callbacks and AUv3 plug-ins.
- **Swift 6 Strict Concurrency**: Data-race free, actor-isolated session lifecycle and `Sendable` types throughout.

---

## Products

HueEntertainmentKit is modularized into focused Swift Package libraries:

| Product | Description |
|---|---|
| `HueEntertainmentKit` | Core discovery (Bonjour/Broker/Manual), pushlink authentication, CLIP v2 client, DTLS transport, packet encoder, and actor-owned session lifecycle. |
| `HueEntertainmentEffects` | Spatial coordinate effect primitives (area, radial, chases), animation timelines, source-over alpha blending, and photosensitivity safety limiting. |
| `HueEntertainmentAudio` | Lock-free audio feature mailbox (`HueAudioFeatureMailbox`) exposing RMS, peak, transient strength, and 8-band spectral energy. |
| `HueEntertainmentTesting` | In-memory mocks (`MockHueHTTPTransport`, `MockHueDTLSTransport`, fixtures) for hardware-free unit testing. |
| `hue-entertainment-diagnostics` | Read-only CLI executable for discovering bridges and inspecting entertainment configurations without pairing. |

---

## Requirements

- **Swift**: 6.0 or later
- **Xcode**: 16.0 or later
- **Supported Platforms**:
  - macOS 15.0+ (Sequoia)
  - iOS 18.0+
  - tvOS 18.0+
  - visionOS 2.0+

---

## Installation

### Swift Package Manager (Package.swift)

Add `HueEntertainmentKit` as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/adeze/HueEntertainmentKit.git", from: "0.1.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "HueEntertainmentKit", package: "HueEntertainmentKit"),
            .product(name: "HueEntertainmentEffects", package: "HueEntertainmentKit"),
            // Optional: for AUv3 / real-time audio analysis
            .product(name: "HueEntertainmentAudio", package: "HueEntertainmentKit"),
        ]
    )
]
```

### Xcode Project

1. In Xcode, select **File > Add Package Dependencies...**
2. Enter the repository URL: `https://github.com/adeze/HueEntertainmentKit.git`
3. Select the version rule (e.g. Up to Next Major `0.1.0`) and choose the products needed for your target.

---

## Quickstart Guide

### 1. Discover Bridges

Find Hue bridges on the local network via Bonjour mDNS, cloud broker lookup, or manual host entry:

```swift
import HueEntertainmentKit

let discovery = HueBridgeDiscovery()

// Discover via Bonjour (mDNS)
let bridges = try await discovery.discoverBonjour(for: .seconds(3))

// Or manual configuration if IP/Host is already known:
let endpoint = try discovery.manual(host: "192.168.1.50", bridgeID: "001788FFFE112233")
```

### 2. Pair and Store Credentials

Pairing requests user consent via the physical bridge link button. Store credentials safely in Keychain:

```swift
import HueEntertainmentKit

let transport = URLSessionHueHTTPTransport(
    trustPolicy: .hueBridge(bridgeID: endpoint.bridgeID)
)
let client = HueBridgeClient(endpoint: endpoint, transport: transport)

// Poll for pushlink button press (with progress callback)
let result = try await client.pairWaitingForLinkButton(
    deviceType: "MyEntertainmentApp#MacBook",
    timeout: .seconds(30)
) { progress in
    switch progress.state {
    case .waitingForLinkButton:
        print("Please press the link button on your Hue bridge...")
    case .paired:
        print("Bridge linked successfully!")
    }
}

// Persist credentials in macOS/iOS Keychain:
let store = KeychainHueCredentialStore()
try store.save(result.credentials, alias: "living-room-bridge")
```

### 3. Query Entertainment Configurations

```swift
guard let credentials = try store.load(alias: "living-room-bridge") else { return }

let authenticatedClient = HueBridgeClient(
    endpoint: endpoint,
    credentials: credentials,
    transport: transport
)

let configs = try await authenticatedClient.entertainmentConfigurations()
for config in configs {
    print("Configuration: \(config.name) (\(config.channels.count) channels)")
}
```

### 4. Stream Live Frames with Safety Limiting

`HueEntertainmentSession` manages the exclusive stream claim, DTLS handshake, 50 Hz frame pumping, and graceful cleanup:

```swift
import HueEntertainmentKit
import HueEntertainmentEffects

guard let config = configs.first else { return }

let dtlsTransport = try NIOTSDTLSTransport()
let session = HueEntertainmentSession(
    control: authenticatedClient,
    transport: dtlsTransport,
    frameRate: 50
)

// Acquire ownership and establish DTLS stream
try await session.start(
    configuration: config,
    endpoint: endpoint,
    credentials: credentials
)

// Apply safety limiting to protect against rapid strobing
var limiter = HueSafeFrameLimiter()

for frameIndex in 0..<250 { // ~5 seconds at 50Hz
    let redColor = try HueRGBColor(red: 0.8, green: 0.1, blue: 0.2)
    let channel0 = HueChannelColor(channelID: 0, color: redColor)
    let candidateFrame = try HueFrame(colors: [channel0])

    // Respect photosensitivity limits (< 5 Hz transitions)
    let safeFrame = try limiter.limit(candidateFrame, at: .milliseconds(frameIndex * 20))
    try await session.submit(safeFrame)

    try await Task.sleep(for: .milliseconds(20))
}

// Graceful release of bridge stream
try await session.stop()
```

### 5. Real-Time Audio Mailbox (AUv3 / CoreAudio)

Publish features in non-allocating render threads and consume them safely in a 50 Hz control loop:

```swift
import HueEntertainmentAudio

let mailbox = HueAudioFeatureMailbox()

// Inside CoreAudio / AUv3 render thread (no locks, no heap allocations):
func processAudioRender(hostTime: UInt64, rms: Float, peak: Float) {
    let features = HueAudioFeatures(
        hostTime: hostTime,
        rms: rms,
        peak: peak,
        spectralCentroid: 1200.0,
        transientStrength: 0.5,
        bandEnergy: (0.1, 0.2, 0.4, 0.8, 0.3, 0.2, 0.1, 0.05)
    )
    mailbox.publish(features)
}

// Inside your 50 Hz visualizer update loop:
if let latestSnapshot = mailbox.latest() {
    // Map audio energy to light effects...
}
```

---

## Read-Only CLI Diagnostics

Run the bundled diagnostic CLI without pairing or changing bridge state:

```bash
# Discover bridges on the local network
swift run hue-entertainment-diagnostics discover

# Inspect bridge configuration (reads credentials from Keychain)
swift run hue-entertainment-diagnostics inspect \
  --host bridge.local \
  --bridge-id 001788FFFE112233 \
  --credential-alias living-room-bridge
```

---

## Security & Privacy Architecture

- **Root CA Validation**: The package embeds both official Signify Hue Bridge root certificate authorities and verifies the certificate common name matches the bridge ID. No self-signed overrides or insecure trust modes exist.
- **Credential Hygiene**: Credentials are stored in Keychain. Raw credentials cannot be passed via CLI arguments and are redacted from string representations (`HueCredentials.description` outputs `HueCredentials(redacted)`).
- **Non-Takeover Guarantee**: By default, `HueEntertainmentSession` refuses to preempt an active stream owned by another application (`.failIfActive`).
- **Clean State Teardown**: Closing a session guarantees that DTLS is shut down, the stream is released on the bridge, and configuration state is verified inactive.

For further details, see [SECURITY.md](SECURITY.md) and [ARCHITECTURE.md](Documentation/ARCHITECTURE.md).

---

## Documentation

- [Architecture & Protocol Design](Documentation/ARCHITECTURE.md)
- [Spatial Effect Design Guide](Documentation/EFFECT_DESIGN.md)
- [Live Bridge Validation Protocol](Documentation/LIVE_VALIDATION.md)
- [AUv3 Example Project](Examples/HueAudioReactiveAUv3/README.md)
- [Security Policy](SECURITY.md)
- [Contributing Guidelines](CONTRIBUTING.md)

---

## Provenance & Disclaimer

- HueEntertainmentKit is an independent clean-room implementation based solely on publicly available Philips Hue documentation and network protocol observations.
- No source code or binaries from the proprietary Philips Hue Entertainment Development Kit (EDK) are included, referenced, or redistributed.
- Philips Hue is a trademark of Signify Holding. This project is not affiliated with, endorsed by, or sponsored by Signify.
- See [NOTICE](NOTICE) for third-party design references.

---

## License

This project is licensed under the **Apache License, Version 2.0**. See the [LICENSE](LICENSE) file for details.
