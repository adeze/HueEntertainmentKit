# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-17

### Added

- Swift 6.0+ package supporting macOS 15+, iOS 18+, tvOS 18+, and visionOS 2+.
- `HueEntertainmentKit`:
  - Typed CLIP v2 models (`HueBridgeEndpoint`, `HueEntertainmentConfiguration`, `HueChannelColor`, `HueFrame`).
  - Bridge discovery via Bonjour mDNS, Philips Hue cloud broker, and manual IP/host.
  - Pushlink pairing workflow with physical link button polling and cancellation support.
  - Secure credential storage backed by macOS/iOS Keychain (`KeychainHueCredentialStore`).
  - HueStream v2 packet encoder supporting RGB and XY+Brightness color spaces up to 20 channels.
  - DTLS 1.2 UDP datagram transport powered by Apple Network framework (`NIOTSDTLSTransport`).
  - Actor-isolated `HueEntertainmentSession` managing exclusive configuration ownership, DTLS handshake, 50 Hz frame pumping, and graceful cleanup.
- `HueEntertainmentEffects`:
  - Spatial effect primitives mapped to room coordinates (`HueAreaEffect`, `HueLightSourceEffect`, `HueMultiChannelEffect`, `HueLightIteratorEffect`).
  - Source-over alpha blending mixer and deterministic animation timelines (`HueTimeline`).
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
