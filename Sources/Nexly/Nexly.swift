import Foundation

/// Wire identifier this SDK reports as `client`. Mirrors the `swift-ios`
/// entry in the `NexlyClient` enum (`packages/core/src/clients.ts`) and the
/// server-side allowlist (`cmd/public-api/main.go`).
enum NexlyClientIdentifier {
    static let swiftIOS = "swift-ios"
}

/// Nexly analytics client for iOS.
///
/// Call ``initialize(appId:key:collectUrl:privacyMode:autoEngagement:)`` once
/// (e.g. from the `@main` `App`'s `init`, or `AppDelegate.didFinishLaunching`),
/// then use the static tracking methods anywhere in the app:
///
/// ```swift
/// Nexly.initialize(appId: "app_...", key: "nx_...")
/// Nexly.pageview()
/// Nexly.customEvent("checkout_started", cdata: ["cart_value_cents": 4200])
/// ```
///
/// All methods are main-actor isolated: metadata collection touches
/// `UIScreen` / `UIDevice`, and engagement tracking hooks `UIApplication`
/// lifecycle notifications, both of which are main-thread APIs. Call from
/// UI code (SwiftUI actions, view lifecycle) without extra dispatching.
@MainActor
public final class Nexly {
    /// Nexly production ingest gateway. Override only for local development
    /// — do not surface `collectUrl` in application UI or public docs.
    public static let defaultCollectURL = "https://gate.nexly.to/v1/collect"

    private static var current: Nexly?

    private let collectUrl: String
    private let appId: String
    private let apiToken: String
    private var currentScreen = "/"
    private var sentSessionContextFor: String?
    private var engagement: Engagement?

    private init(collectUrl: String, appId: String, apiToken: String) {
        self.collectUrl = collectUrl
        self.appId = appId
        self.apiToken = apiToken
    }

    private var disabled: Bool { appId.isEmpty || apiToken.isEmpty }

    // MARK: - Setup

    /// Configures the shared client. Calling it again replaces the previous
    /// instance and stops any engagement tracking it had started.
    ///
    /// - Parameters:
    ///   - appId: App identifier from the dashboard.
    ///   - key: Ingest API token from the dashboard.
    ///   - collectUrl: Override the ingest endpoint. Defaults to the Nexly
    ///     production gateway — only override for local development.
    ///   - privacyMode: When `true`, the SDK never reads or writes
    ///     `UserDefaults` for visitor / session identifiers; the collector
    ///     derives a short-lived, daily-rotating visit fingerprint
    ///     server-side instead. Can be flipped later with
    ///     ``setPrivacyMode(_:)``.
    ///   - autoEngagement: Automatically tracks active seconds, a 60s
    ///     heartbeat, and `session_ping` / `session_end` driven by app
    ///     lifecycle notifications. Defaults to `true`.
    /// - Returns: `false` when `appId` or `key` is empty (tracking stays
    ///   disabled — every call is then a silent no-op).
    @discardableResult
    public static func initialize(
        appId: String,
        key: String,
        collectUrl: String = Nexly.defaultCollectURL,
        privacyMode: Bool = false,
        autoEngagement: Bool = true
    ) -> Bool {
        current?.engagement?.stop()
        Identity.configure(privacyMode: privacyMode)

        let instance = Nexly(
            collectUrl: collectUrl.trimmingCharacters(in: .whitespacesAndNewlines),
            appId: appId.trimmingCharacters(in: .whitespacesAndNewlines),
            apiToken: key.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        current = instance

        if instance.disabled {
            #if DEBUG
            if instance.appId.isEmpty { print("[Nexly] Missing appId — tracking is disabled.") }
            if instance.apiToken.isEmpty { print("[Nexly] Missing key — tracking is disabled.") }
            #endif
            return false
        }

        if autoEngagement {
            instance.restartEngagement()
        }
        return true
    }

    // MARK: - Screens

    /// Sets the current screen name used as `path` for subsequent events.
    public static func setScreen(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        current?.currentScreen = trimmed.isEmpty ? "/" : trimmed
    }

    /// Convenience: sets the screen and sends a pageview in one call.
    @discardableResult
    public static func screenview(_ name: String) -> Bool {
        setScreen(name)
        return pageview(current?.currentScreen)
    }

    // MARK: - Tracking

    /// Sends a page view (`event_name` / `event_type`: `pageview`) with full context.
    @discardableResult
    public static func pageview(_ path: String? = nil) -> Bool {
        guard let instance = current, !instance.disabled else { return false }
        let resolvedPath = path ?? instance.currentScreen
        var context = DeviceMeta.collectEventMeta()
        context["path"] = resolvedPath
        return instance.dispatch(eventName: "pageview", eventType: "pageview", context: context, data: [:], cdata: nil)
    }

    /// Sends a generic event. `context` is merged on top of the default
    /// platform context (current screen, visitor/session ids); application
    /// payload belongs in `cdata`. Prefer ``customEvent(_:cdata:context:)``
    /// for the ergonomic custom-analytics API.
    @discardableResult
    public static func event(
        name: String,
        type: String,
        cdata: CData? = nil,
        context: [String: Any]? = nil
    ) -> Bool {
        guard let instance = current, !instance.disabled else { return false }
        var defaultContext = DeviceMeta.collectEventMeta()
        defaultContext["path"] = instance.currentScreen
        let merged = (context ?? [:]).merging(defaultContext) { fromCaller, _ in fromCaller }
        return instance.dispatch(eventName: name, eventType: type, context: merged, data: [:], cdata: cdata)
    }

    /// Sends a custom analytics event. `cdata` carries the user-defined
    /// scalar payload validated server-side against the per-app "Custom
    /// data" registry. The optional `context` overrides standard
    /// attribution keys (`utm_*`, `gclid`, …) when the SDK cannot infer them
    /// (deep links, post-navigation clicks).
    @discardableResult
    public static func customEvent(
        _ name: String,
        cdata: CData? = nil,
        context: StandardContextOverride? = nil
    ) -> Bool {
        guard let instance = current, !instance.disabled else { return false }
        var defaultContext = DeviceMeta.collectEventMeta()
        defaultContext["path"] = instance.currentScreen
        let overrideContext = context?.asContext() ?? [:]
        let merged = overrideContext.merging(defaultContext) { fromCaller, _ in fromCaller }
        return instance.dispatch(eventName: name, eventType: "custom", context: merged, data: [:], cdata: cdata)
    }

    private func dispatch(eventName: String, eventType: String, context: [String: Any], data: [String: Any], cdata: CData?) -> Bool {
        let privacyMode = Identity.isPrivacyMode()
        let sessionId = (context["session_id"] as? String) ?? ""
        // In privacy mode the session id may be derived server-side, so the
        // SDK cannot key "session_context sent once" off it. Fall back to a
        // sentinel: send session_context once per client instance (≈ once
        // per app launch, or until `initialize` is called again).
        let sessionContextKey = !sessionId.isEmpty ? sessionId : (privacyMode ? "\u{0}privacy" : "")

        var sessionContext: [String: Any]?
        if !sessionContextKey.isEmpty, sessionContextKey != sentSessionContextFor {
            let collected = DeviceMeta.collectSessionMeta()
            if !collected.isEmpty {
                sessionContext = collected
                sentSessionContextFor = sessionContextKey
            }
        }

        let payload = buildCollectPayload(
            TrackEventInput(
                credentials: IngestCredentials(appId: appId, apiToken: apiToken),
                eventName: eventName,
                eventType: eventType,
                client: NexlyClientIdentifier.swiftIOS,
                privacyMode: privacyMode,
                context: context,
                data: data,
                cdata: cdata,
                sessionContext: sessionContext
            )
        )
        return Transport.send(url: collectUrl, payload: payload)
    }

    // MARK: - Engagement

    /// (Re)starts `UIApplication`-lifecycle-driven engagement tracking.
    /// Idempotent: calling it again stops the previous subscription first.
    /// Automatically started by ``initialize`` unless `autoEngagement` was
    /// passed as `false`.
    @discardableResult
    public static func startEngagement() -> Bool {
        guard let instance = current, !instance.disabled else { return false }
        instance.restartEngagement()
        return true
    }

    /// Stops engagement tracking started by ``startEngagement()`` or
    /// `initialize(autoEngagement: true)`.
    public static func stopEngagement() {
        current?.engagement?.stop()
        current?.engagement = nil
    }

    private func restartEngagement() {
        engagement?.stop()
        let instanceEngagement = Engagement(
            collectUrl: collectUrl, appId: appId, apiToken: apiToken, client: NexlyClientIdentifier.swiftIOS
        )
        engagement = instanceEngagement
        instanceEngagement.start()
    }

    // MARK: - Identity

    /// Enables or disables privacy mode at runtime — safe to flip from a
    /// settings toggle. See ``NexlyInit/privacyMode``-equivalent semantics
    /// in `Identity`.
    public static func setPrivacyMode(_ enabled: Bool) {
        Identity.setPrivacyMode(enabled)
    }

    /// `true` when privacy mode is currently enabled.
    public static func isPrivacyMode() -> Bool {
        Identity.isPrivacyMode()
    }

    /// Overrides the visitor id attached to subsequent events. Pass an
    /// empty string to clear the override and fall back to the stored (or,
    /// in privacy mode, absent) id.
    public static func setVisitorId(_ id: String) {
        Identity.setVisitorId(id)
    }

    /// Overrides the session id attached to subsequent events. Pass an
    /// empty string to clear the override.
    public static func setSessionId(_ id: String) {
        Identity.setSessionId(id)
    }

    /// The visitor id that would be attached to the next event right now —
    /// useful for displaying current identity state in debug UI.
    public static func currentVisitorId() -> String {
        Identity.resolvedVisitorId()
    }

    /// The session id that would be attached to the next event right now.
    public static func currentSessionId() -> String {
        Identity.resolvedSessionId()
    }
}
