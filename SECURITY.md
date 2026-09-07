# Security

- Production HTTPS must use system trust or explicitly supplied official Hue roots.
  There is no insecure trust mode.
- Application and DTLS client keys belong in Keychain and must never enter logs,
  command-line arguments, receipts, fixtures, or Git.
- Pairing requires a physical pushlink action. Applications must surface this action
  and support cancellation.
- Session ownership defaults to refusing active configurations. The SDK never stops
  another application's stream to acquire ownership.
- Live diagnostics are read-only. Pairing and light output require a separate,
  explicit user-approved application flow.

Report vulnerabilities privately to the repository owner. Do not include credentials,
bridge addresses, packet captures containing secrets, or household topology.
