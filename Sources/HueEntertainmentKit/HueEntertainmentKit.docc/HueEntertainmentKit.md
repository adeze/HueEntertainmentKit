# ``HueEntertainmentKit``

An independent, clean-room Swift implementation of the **Philips Hue Entertainment API** for Apple platforms.

## Overview

HueEntertainmentKit provides high-performance, real-time spatial lighting synchronization with strict security guarantees:
- **CLIP v2 HTTP**: Native `URLSession` or high-throughput Swift-NIO HTTP/1.1 (`NIOHueHTTPTransport`) with strict TLS certificate chain validation against official Signify Hue root CAs.
- **HueStream v2 DTLS**: UDP streaming powered by Apple Network framework via `NIOTransportServices` with TLS 1.2 PSK encryption and Swift-NIO channel duplex pipelines (`HueStreamChannelHandler`).
- **Photosensitivity Safety**: Built-in `HueSafeFrameLimiter` enforcing Philips Hue guidance to keep rapid brightness transitions under 5 Hz.
- **Real-Time Audio**: Lock-free, zero-allocation C11 atomic seqlock mailbox (`HueAudioFeatureMailbox`) for high-frequency audio render callbacks and AUv3 plug-ins.
- **Swift 6 Strict Concurrency**: Data-race free, actor-isolated session lifecycle and `Sendable` types throughout.

## Topics

### Core Session & Client
- ``HueEntertainmentSession``
- ``HueBridgeClient``
- ``HueBridgeDiscovery``
- ``HueSessionState``
- ``HueCredentials``
- ``KeychainHueCredentialStore``

### Color Models & Gamuts
- ``HueRGBColor``
- ``HueGamut``
- ``HueXYBrightness``
- ``HueChannelColor``
- ``HueFrame``

### Network Pipeline & Transports
- ``NIOHueHTTPTransport``
- ``URLSessionHueHTTPTransport``
- ``NIOTSDTLSTransport``
- ``HueStreamChannelHandler``
- ``HueStreamMessage``
- ``HueStreamPacketEncoder``
