# AGENTS.md

Instructions and architectural guidelines for AI coding assistants and autonomous agents working in this repository.

## Project Overview

`HueEntertainmentKit` is an independent, clean-room Swift package providing high-performance, real-time spatial lighting synchronization with the **Philips Hue Entertainment API** for Apple platforms (macOS 15+, iOS 18+, tvOS 18+, visionOS 2+).

The repository contains three primary libraries, an AUv3-compatible audio realtime core, an offline test fixture target, and a CLI tool:
- `HueEntertainmentKit`: Core bridge discovery, CLIP v2 client, DTLS 1.2 UDP streaming transport, Swift-NIO pipeline, packet encoder, and actor-isolated session lifecycle.
- `HueEntertainmentEffects`: Spatial coordinate effect primitives, animation timelines, alpha blending, and photosensitivity safety limiting.
- `HueEntertainmentAudioRT` / `HueEntertainmentAudio`: C11 atomic seqlock lock-free mailbox for zero-allocation audio render threads (AUv3/CoreAudio) and feature extraction.
- `HueEntertainmentTesting`: Offline in-memory mocks (`MockHueHTTPTransport`, `MockHueDatagramTransport`).
- `HueEntertainmentDiagnostics`: Read-only CLI discovery and inspection tool.

---

## Non-Negotiable Rules & Invariants

1. **Swift 6 Strict Concurrency**:
   - The package is configured with `swiftLanguageModes: [.v6]`.
   - All shared types must be `Sendable` or actor-isolated (`HueEntertainmentSession`).
   - Global state is prohibited unless isolated or proven constant (`public static let`).
   - Zero data races and zero compiler warnings under Swift 6.

2. **Photosensitivity Safety Invariant**:
   - Rapid brightness transitions must **never** exceed 5 Hz (per Philips Hue guidance and IEC 62471 / IEEE 1789 standards).
   - Any modifications to `HueSafeFrameLimiter` must preserve the allocation-free sliding window (backed by `Deque` from `swift-collections`).

3. **Offline Test Independence**:
   - Unit tests (`swift test`) must **never** require a physical Hue bridge or local network connection.
   - Always use `MockHueHTTPTransport`, `MockHueDatagramTransport`, or embedded NIO channels (`EmbeddedChannel`, `NIOEmbedded`) for tests.

4. **Security & Credential Protection**:
   - Never commit raw credentials, IP addresses, application keys, or bridge client keys.
   - Credentials must use `KeychainHueCredentialStore` or mock values.
   - `HueCredentials.description` must always redact secrets (`HueCredentials(redacted)`).
   - Bridge communication must enforce Signify Hue root CA certificate validation.

5. **Tooling Rule**:
   - Always use standard Swift Package Manager commands and official plugins.
   - Never use ad-hoc shell scripts for file edits or builds.

---

## Build, Test & Lint Commands

```bash
# Build debug
swift build

# Build release
swift build -c release

# Run all test suites (4 suites, 17+ tests)
swift test

# Lint with SwiftLint command plugin (strict mode)
swift package --allow-writing-to-package-directory swiftlint lint Sources Tests --strict

# Build DocC documentation archives
swift package generate-documentation --target HueEntertainmentKit
swift package generate-documentation --target HueEntertainmentEffects
swift package generate-documentation --target HueEntertainmentAudio

# Local DocC documentation preview server
swift package --disable-sandbox preview-documentation --target HueEntertainmentKit
```

---

## Architecture & Module Layout

```
Sources/
├── HueEntertainmentKit/          # Core bridge connection & streaming
│   ├── BridgeClient.swift        # CLIP v2 REST client & pushlink pairing
│   ├── BridgeDiscovery.swift     # Bonjour mDNS (async stream) & broker discovery
│   ├── Color+Interop.swift       # CGColor, SwiftUI Color, Hex, Presets
│   ├── CredentialStore.swift     # Keychain-backed secure storage
│   ├── EntertainmentSession.swift# Actor-isolated 50 Hz streaming lifecycle
│   ├── EntertainmentTransport.swift # Swift-NIO Channel & DTLS 1.2 PSK transport
│   ├── HTTPTransport.swift       # URLSession transport with Root CA pinning
│   ├── HueColorGamut.swift       # CIE 1931 xy Gamut A/B/C projection
│   ├── HueStreamPacketEncoder.swift # Binary protocol v2 encoder
│   ├── Logging.swift             # swift-log structured logging
│   ├── Models.swift              # Strongly-typed configuration & frame models
│   ├── NIOHTTPTransport.swift    # Swift-NIO HTTP/1.1 transport
│   └── HueEntertainmentKit.docc/ # DocC landing documentation
├── HueEntertainmentEffects/      # Spatial effects & safety
│   ├── Animation.swift           # Deterministic animators (tween, noise, pulse)
│   ├── Effects.swift             # Area, LightSource, and MultiChannel primitives
│   ├── Safety.swift              # HueSafeFrameLimiter (< 5 Hz) & frame pacing
│   ├── Timeline.swift            # Timeline sequencing & alpha blending
│   └── HueEntertainmentEffects.docc/ # DocC landing documentation
├── HueEntertainmentAudioRT/      # C11 atomic seqlock ring buffer (real-time safe)
├── HueEntertainmentAudio/        # High-level Swift audio mailbox
│   └── HueEntertainmentAudio.docc/ # DocC landing documentation
├── HueEntertainmentDiagnostics/  # CLI tool
└── HueEntertainmentTesting/      # In-memory test doubles
```

---

## Conventions

- **Identifier Naming**: In mathematical/color coordinate calculations, short symbols (`x`, `y`, `z`, `r`, `g`, `b`, `cx`, `cy`, `cz`, `X`, `Y`, `Z`, `xy`) are explicitly allowed per `.swiftlint.yml`.
- **Public API Documentation**: All public types, functions, and properties must include triple-slash (`///`) docstrings compatible with DocC.
- **Git Commits**: Follow Conventional Commits style (e.g. `feat: ...`, `fix: ...`, `docs: ...`).
