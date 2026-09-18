# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-18

### Added

- Frame rate range lowered to support film and television cadences down to 20 Hz (20–60 Hz), supporting native 23.976, 24.0, 29.97, and 30.0 fps without motion judder.
- Adaptive deadband throttling in `HueEntertainmentSession`: detects sub-JND static frames and throttles UDP packet transmission down to a 2 Hz heartbeat keep-alive, reducing Bridge load and WiFi airtime by up to 90% while preventing connection timeout.
- Support for `HueXYFrame` and `HueXYChannelColor` in CIE 1931 xy space with official Gamut C boundary clamping.

## [0.1.0] - 2026-09-17

### Added

- Swift 6.0+ package supporting macOS 15+, iOS 18+, tvOS 18+, and visionOS 2+.
- `HueEntertainmentKit`:
  - Typed CLIP v2 models (`HueBridgeEndpoint`, `HueEntertainmentConfiguration`, `HueChannelColor`, `HueFrame`).
  - Bridge discovery via Bonjour mDNS, Philips Hue cloud broker, and manual IP/host.
  - Pushlink pairing workflow with physical link button polling and cancellation support.
  - Secure credential storage backed by macOS/iOS Keychain (`KeychainHueCredentialStore`).
  - Color interoperability with `CGColor`, SwiftUI `Color`, hex strings (`#FF5500`), and named presets (`.red`, `.green`, etc.).
  - CIE 1931 xy color space conversion with official Philips Hue Gamuts A, B, and C clamping.
  - Reactive `AsyncStream` live Bonjour discovery (`bonjourStream()`) and real-time session state observation (`stateUpdates`).
  - Unified logging integration via `swift-log` (`Logging.Logger`) across discovery, client, transport, and session lifecycle.
  - Swift-NIO Channel Pipeline support with `HueStreamChannelHandler: ChannelDuplexHandler` and `HueStreamMessage`.
  - Native Swift-NIO HTTP transport (`NIOHueHTTPTransport`) powered by `NIOHTTP1` and `NIOTransportServices` with Signify Hue root CA verification.
  - HueStream v2 packet encoder supporting RGB and XY+Brightness color spaces up to 20 channels.
  - DTLS 1.2 UDP datagram transport powered by Apple Network framework (`NIOTSDTLSTransport`).
  - Actor-isolated `HueEntertainmentSession` managing exclusive configuration ownership, DTLS handshake, 50 Hz frame pumping, and graceful cleanup.
- `HueEntertainmentEffects`:
  - Spatial effect primitives mapped to room coordinates (`HueAreaEffect`, `HueLightSourceEffect`, `HueMultiChannelEffect`, `HueLightIteratorEffect`).
  - Source-over alpha blending mixer and deterministic animation timelines (`HueTimeline`).
  - Allocation-free sliding window history using `Deque` from `swift-collections` in `HueSafeFrameLimiter`.
  - Frame pacing for asynchronous sequences via `AsyncSequence.paceForEntertainment(frameRate:)` using `swift-async-algorithms`.
  - Photosensitivity safety limiter (`HueSafeFrameLimiter`) capping transitions below 5 Hz and enforcing 80% maximum component limits by default.
- `HueEntertainmentAudio`:
  - Real-time C11 atomic seqlock mailbox (`HueAudioFeatureMailbox`) for zero-allocation, lock-free feature publication from audio render threads.
  - Snapshot extraction of RMS, peak, transient strength, and 8-band spectral energy.
- `HueEntertainmentTesting`:
  - Mock HTTP and DTLS transports (`MockHueHTTPTransport`, `MockHueDTLSTransport`) for offline unit testing without physical bridge hardware.
- `hue-entertainment-diagnostics`:
  - Read-only command-line tool for network bridge discovery and configuration inspection.
- Reference AUv3 audio-reactive example projects for macOS and tvOS.

### Security

- Strict TLS certificate chain validation using embedded Signify Hue Bridge root CAs.
- Certificate common name validation matching discovered bridge ID (no insecure trust mode or trust-on-first-use).
- Complete redaction of credentials in string descriptions and logs (`HueCredentials(redacted)`).
- Refusal to preempt active streams owned by other applications (`.failIfActive`).
