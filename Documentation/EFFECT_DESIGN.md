# Effect design

`HueEntertainmentEffects` maps effects to normalized room coordinates instead of
assuming a particular lamp count or placement. Choose the primitive by intent:

- `HueAreaEffect` when showing an effect in the wrong region would be misleading.
- `HueMultiChannelEffect` when preserving as many authored channels as possible is
  more important than exact physical proximity.
- `HueLightSourceEffect` for distance-weighted sources with animated position and
  radius, such as explosions or moving energy.
- `HueLightIteratorEffect` for ordered chases across actual channels.
- `HueTimeline` for deterministic scheduled composition.

The mixer uses ordered source-over alpha blending. Apply `HueSafeFrameLimiter`
before session submission: its defaults cap components at 80 percent and accept no
more than four perceptible brightness changes per second. These are conservative
SDK defaults, not a substitute for content review. Avoid strobing, warn users about
flashing content, keep peripheral brightness changes gentle, and synchronize effect
starts and ends to the media event. Prefer more saturated screen-adjacent color and
less saturated ambient light near or behind the viewer.

Sources:

- [Hue light-effects experience guide](https://developers.meethue.com/develop/hue-entertainment/light-effects-experience-guide-book/)
- [Hue EDK effect-creation concepts](https://developers.meethue.com/develop/hue-entertainment/hue-edk-effect-creation/)
- [Hue Entertainment API](https://developers.meethue.com/develop/hue-entertainment/hue-entertainment-api/)
