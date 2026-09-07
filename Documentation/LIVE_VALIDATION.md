# Live validation gate

Live validation is not part of the offline test suite.

1. Inspect bridge identity and entertainment configurations read-only.
2. Obtain fresh approval before pushlink pairing or any light output.
3. Refuse an active configuration; never issue a speculative stop.
4. Stream a user-approved low-brightness pattern for at most five seconds.
5. Close DTLS, stop the owned configuration, and independently re-read inactive state.
6. Store a secret-free receipt containing bridge ID, configuration ID, timestamps,
   frame count, state transitions, and final readback. Do not store IPs or credentials.

Passing offline tests does not establish bridge compatibility, persistent release,
visual safety, AUv3 registration, or host interoperability.

The ignored local receipt dated 2026-09-02 records the first bounded bridge protocol
proof. It establishes authenticated HTTPS, exact stream ownership, DTLS delivery,
bounded frame submission, and independent release readback for that run only. It does
not establish subjective effect quality or AUv3 host behavior.
