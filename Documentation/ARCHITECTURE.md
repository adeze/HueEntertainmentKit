# Architecture

`HueBridgeClient` performs low-rate CLIP v2 operations through an injected HTTPS
transport. `HueEntertainmentSession` exclusively owns claim, DTLS connection,
frame sequencing, stale-frame replacement, and release. It refuses already-active
configurations and attempts release if DTLS setup fails after a successful claim.

`NIOTSDTLSTransport` uses `NIOTSDatagramConnectionBootstrap` with DTLS 1.2 and
`TLS_PSK_WITH_AES_128_GCM_SHA256`. The PSK identity must be the exact application
ID returned by `/auth/v1`; the transport fails closed when that value is missing.

Packets support the documented RGB and device-independent XY+brightness encodings,
with no more than 20 channel slots. The session waits until `active_streamer` equals
its own application ID before opening DTLS. It then repeats the latest frame at 50 Hz
so lossy UDP does not leave stale output.

Effects are pure functions of time and entertainment-channel coordinates. The mixer
orders layers, applies source-over alpha blending, clamps output, and emits the typed
frame consumed by the packet encoder.
`HueSafeFrameLimiter` defaults to four brightness changes per second and 80% maximum
components, following Hue guidance to keep rapid brightness changes below 5 Hz.

The audio module is deliberately independent from AVFAudio. A C11 atomic seqlock
stores one fixed feature snapshot. Publishing does not allocate or acquire a lock;
networking and effect rendering belong on a non-real-time worker capped at 50 Hz.

The AUv3 sample shows this boundary. It can process only buffers supplied by its host;
it is not a system-wide tvOS capture mechanism.
