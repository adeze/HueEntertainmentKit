# ``HueEntertainmentEffects``

Spatial coordinate effect primitives, animation timelines, and photosensitivity safety limiting.

## Overview

`HueEntertainmentEffects` maps spatial room positions to light channel outputs:
- **Spatial Primitives**: Area effects, radial light sources, channel sweeps, and multi-channel composites.
- **Blending & Mixing**: Source-over alpha blending and deterministic animation evaluation.
- **Safety Limiter**: Photosensitivity limiter (`HueSafeFrameLimiter`) preventing high-frequency flashing (> 5 Hz) using an allocation-free sliding window.
- **Async Pacing**: Throttle async sequences of frames directly to the bridge cadence via `paceForEntertainment(frameRate:)`.

## Topics

### Spatial Effects
- ``HueEffect``
- ``HueAreaEffect``
- ``HueLightSourceEffect``
- ``HueMultiChannelEffect``
- ``HueLightIteratorEffect``
- ``HueEffectMixer``

### Animations & Timelines
- ``HueTimeline``
- ``HueAnimation``
- ``HueAnimatedColor``

### Photosensitivity Safety
- ``HueSafeFrameLimiter``
- ``HueEffectSafetyPolicy``
