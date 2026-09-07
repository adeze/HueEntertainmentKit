# HueEntertainmentKit

Independent Swift 6.3 implementation of the Philips Hue Entertainment API for
Apple platforms. CLIP v2 uses `URLSession`; HueStream v2 uses DTLS/UDP through
NIOTransportServices. No bridge address or credential is embedded in the package.

The package bundles both Hue Bridge root CAs published by Signify and validates the
device certificate common name against the discovered bridge ID. It never falls back
to HTTP or trust-on-first-use.

> Status: 0.x development. Offline tests and one supervised, bounded bridge protocol
> proof pass. Visual confirmation, tvOS host build, and AUv3 signing/installation
> remain outstanding.

## Products

- `HueEntertainmentKit`: discovery, authentication, CLIP v2, HueStream packets,
  NIOTS DTLS transport, and actor-owned session lifecycle.
- `HueEntertainmentEffects`: deterministic spatial effects and animation mixer.
- `HueEntertainmentAudio`: allocation-free real-time feature publication.
- `HueEntertainmentTesting`: injectable mocks.
- `hue-entertainment-diagnostics`: read-only discovery and configuration inspection.

## Read-only start

```bash
swift run hue-entertainment-diagnostics discover
swift run hue-entertainment-diagnostics inspect \
  --host bridge.local \
  --bridge-id 001788FFFE112233 \
  --credential-alias my-bridge
```

`inspect` reads credentials from Keychain. Command-line secrets are deliberately
unsupported. Pairing and streaming require an application-controlled consent flow.

```swift
let endpoint = try HueBridgeEndpoint(host: "bridge.local", bridgeID: bridgeID)
let transport = URLSessionHueHTTPTransport(
    trustPolicy: .hueBridge(bridgeID: bridgeID)
)
let client = HueBridgeClient(
    endpoint: endpoint,
    credentials: credentials,
    transport: transport
)
let configurations = try await client.entertainmentConfigurations()
```

See [SECURITY.md](SECURITY.md), [Architecture](Documentation/ARCHITECTURE.md), and
the [effect-design guidance](Documentation/EFFECT_DESIGN.md) and
[AUv3 example](Examples/HueAudioReactiveAUv3/README.md).

## Provenance

Implementation authority is public Hue documentation and independent wire fixtures.
The restricted Philips Hue EDK is not copied, translated, linked, or redistributed.
See [NOTICE](NOTICE) for reviewed MIT references.
