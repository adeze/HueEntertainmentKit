### Description

<!-- Provide a concise description of the changes proposed in this pull request and the motivation behind them. -->

### Changes Made

- 

### Verification Checklist

- [ ] `swift test` passes cleanly with all tests green.
- [ ] `swift build -c release` builds without errors or warnings.
- [ ] Conforms to Swift 6 strict concurrency requirements (`Sendable`, actors, no data races).
- [ ] No credentials, bridge tokens, private IP addresses, or household topology are committed.
- [ ] Does not include or link any proprietary Philips Hue EDK source code.
- [ ] Follows photosensitivity safety guidelines (respects `HueSafeFrameLimiter` limits).
