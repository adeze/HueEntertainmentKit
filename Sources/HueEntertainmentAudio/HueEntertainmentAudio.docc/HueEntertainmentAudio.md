# ``HueEntertainmentAudio``

Real-time audio feature publication and lock-free thread-safe mailbox.

## Overview

`HueEntertainmentAudio` bridges high-frequency CoreAudio and AUv3 audio render threads with real-time lighting visualization:
- **Lock-Free Seqlock Mailbox**: Backed by C11 atomic seqlock (`HueAudioFeatureMailbox`), providing zero memory allocations and no thread priority inversion.
- **Audio Feature Extraction**: Publishes RMS, peak level, transient strength, spectral centroid, and 8-band frequency band energy.

## Topics

### Mailbox & Features
- ``HueAudioFeatureMailbox``
- ``HueAudioFeatures``
