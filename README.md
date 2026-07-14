# Nexly

Native Swift SDK for [Nexly](https://nexly.to) analytics on iOS. SwiftPM only,
iOS 15+, no external dependencies.

## Install

Add the package by git URL in Xcode (File → Add Package Dependencies…), or in
`Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/<org>/nexly-ios", from: "0.1.0")
]
```

## Setup

Call `Nexly.initialize` once, e.g. from your `@main` `App`'s initializer:

```swift
import Nexly

@main
struct MyApp: App {
    init() {
        Nexly.initialize(appId: "app_...", key: "nx_...")
    }

    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
```

`appId` and `key` come from the Nexly dashboard. By default the SDK also
starts engagement tracking (active seconds, a 60s heartbeat, and
`session_ping` / `session_end` around app backgrounding) — pass
`autoEngagement: false` to opt out and call `Nexly.startEngagement()` /
`Nexly.stopEngagement()` manually.

Add `nexlyswift://device` to the app's **Allowed origins** in the Nexly
dashboard so the collector accepts events from this SDK.

## Usage

```swift
Nexly.setScreen("Settings")
Nexly.pageview()

// Or in one call:
Nexly.screenview("Pricing")

Nexly.customEvent("checkout_started", cdata: ["cart_value_cents": 4200])

Nexly.event(name: "search_submitted", type: "engagement", cdata: ["query_length": 7])
```

### Privacy mode

When enabled, the SDK never reads or writes `UserDefaults` for visitor /
session identifiers; the collector derives a short-lived, daily-rotating
visit fingerprint server-side instead.

```swift
Nexly.initialize(appId: "app_...", key: "nx_...", privacyMode: true)

// Can also be toggled at runtime, e.g. from a settings switch:
Nexly.setPrivacyMode(true)
```

### Custom visitor / session id

Works in both modes. In privacy mode this is the only way to get a stable
visitor id or control visit grouping client-side.

```swift
Nexly.setVisitorId("user_42")
Nexly.setSessionId("checkout-flow-1")

// Clear an override:
Nexly.setVisitorId("")
```

## Development

```bash
swift test
# or, for a real iOS Simulator run:
xcodebuild test -scheme Nexly -destination 'platform=iOS Simulator,name=iPhone 17'
```

There is no bundled example app in this repository — the reference SwiftUI
example lives in the `trackers` monorepo at `examples/nexly-ios-example` and
consumes this package via a local path dependency during development.
