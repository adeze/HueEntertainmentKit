# Contributing to HueEntertainmentKit

Thank you for your interest in contributing to **HueEntertainmentKit**!

HueEntertainmentKit is an independent Swift implementation of the Philips Hue Entertainment API (CLIP v2 + HueStream v2) for Apple platforms. Our goal is to provide a clean, safe, reliable, and high-performance package with zero compromise on security or photosensitivity safety.

---

## Guiding Principles

1. **Safety First**:
   - The Hue light effects guidance emphasizes keeping rapid brightness changes below 5 Hz to protect photosensitive individuals.
   - Any animation, effect, or mixer addition must respect and support `HueSafeFrameLimiter` constraints.
   - Avoid strobing or uncontrolled bright flashing.

2. **Zero Compromise Security**:
   - All production HTTP communication uses strict certificate validation against official Signify root CAs. There is no insecure or trust-on-first-use mode.
   - Credentials (application key and client key) belong in the system Keychain or an application-controlled secure vault. They must never appear in command-line arguments, logs, test fixtures, receipts, or commits.

3. **Strict Concurrency (Swift 6)**:
   - The package is built with Swift 6 language mode enabled (`swiftLanguageModes: [.v6]`).
   - All public types, protocols, and closures must maintain strict concurrency safety (`Sendable`, actor isolation, and thread safety).

4. **Clean-Room Implementation**:
   - Implementation authority is strictly public documentation, open wire standards, and independent protocol observations.
   - The proprietary Philips Hue EDK is not copied, translated, linked, or redistributed. Contributors must not introduce proprietary Signify source code.

5. **Hardware-Independent Offline Tests**:
   - The continuous integration test suite must run and pass completely offline without access to a physical bridge.
   - Network interactions and transports must be mockable via `HueEntertainmentTesting`.

---

## Development Setup

### Requirements

- **macOS**: 15.0 or later
- **Xcode**: 16.0 or later (Swift 6.0+)
- **Command Line Tools**: SwiftPM CLI

### Building and Testing

Run the test suite:
```bash
swift test
```

Build the release configuration:
```bash
swift build -c release
```

Lint property lists:
```bash
find Examples -name '*.plist' -print0 | xargs -0 -n1 plutil -lint
```

Build the macOS AUv3 reference host and extension:
```bash
xcodebuild -quiet \
  -project Examples/HueAudioReactiveAUv3/HueAudioReactiveAUv3.xcodeproj \
  -scheme HueAudioReactiveMac \
  -destination 'platform=macOS' \
  CODE_SIGNING_ALLOWED=NO build
```

---

## Submitting Pull Requests

1. **Fork and Branch**: Create a feature branch from `main` (e.g. `feature/spatial-chase` or `fix/bonjour-ipv6`).
2. **Coding Standards**:
   - Maintain idiomatic Swift and doc comments for all public APIs.
   - Keep the codebase warning-free with Swift 6 concurrency checks.
   - Do not introduce external dependencies without prior discussion.
3. **Tests**:
   - Add unit tests for new behavior or regression tests for bug fixes.
   - Ensure `swift test` and `swift build -c release` pass cleanly.
4. **Pull Request**:
   - Open a PR against `main` using the PR template.
   - Provide a concise description of the motivation and changes made.

---

## Reporting Issues

- For bug reports or feature requests, please use our GitHub issue templates.
- **Security Vulnerabilities**: If you discover a security vulnerability, please follow the reporting process outlined in [SECURITY.md](SECURITY.md) rather than opening a public issue.

---

## License

By contributing to HueEntertainmentKit, you agree that your contributions will be licensed under the [Apache License, Version 2.0](LICENSE).
