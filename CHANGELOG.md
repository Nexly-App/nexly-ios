# Nexly (Swift/iOS)

## 1.0.0

### Major Changes

- First release. Version aligned with the `@nexly/*` JS packages (which
  shipped `1.0.0` with privacy mode support) — see the "Versioning" section
  in `README.md` for the lockstep policy this repo follows going forward.

  - Full port of the wire contract from `@nexly/core`: `buildCollectPayload`,
    session/dispatch semantics, `client: "swift-ios"`.
  - `Nexly.initialize`, `pageview`, `event`, `customEvent`, screen tracking
    (`setScreen` / `screenview`).
  - Privacy mode (`privacyMode`), toggleable at runtime via
    `Nexly.setPrivacyMode(_:)` — unlike the JS SDKs, this is mutable after
    init, matching the dynamic toggle in `examples/nexly-ios-example`.
  - Manual visitor/session id overrides (`setVisitorId`, `setSessionId`),
    `UserDefaults`-backed session id with a 30-minute idle timeout.
  - Engagement tracking: active-seconds counting, 60s heartbeat,
    `session_ping` / `session_end` around app backgrounding
    (`autoEngagement`, `startEngagement`, `stopEngagement`).
