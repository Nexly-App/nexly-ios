import Foundation

/// Central switchboard between the storage-backed identifiers (`Session`)
/// and privacy mode / manual overrides. Every code path that attaches
/// `visitor_id` / `session_id` to an event reads through this module.
///
/// Mirrors `packages/web/src/identity.ts`, with one deliberate difference:
/// `privacyMode` here is a **mutable, thread-safe flag** rather than a value
/// fixed at `init` time. On iOS `UserDefaults` access is cheap and
/// synchronous, so there is no prewarm step to invalidate — flipping the
/// flag at runtime (e.g. from a settings toggle) is safe and takes effect on
/// the very next event.
enum Identity {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var _privacyMode = false
    nonisolated(unsafe) private static var _manualVisitorId = ""
    nonisolated(unsafe) private static var _manualSessionId = ""

    /// Called from `Nexly.initialize`.
    static func configure(privacyMode: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _privacyMode = privacyMode
    }

    /// Enables or disables privacy mode at runtime. In privacy mode the SDK
    /// never reads or writes `UserDefaults` for visitor / session
    /// identifiers (unless a manual override is set); the collector derives
    /// a short-lived, daily-rotating visit fingerprint server-side instead.
    static func setPrivacyMode(_ enabled: Bool) {
        lock.lock()
        defer { lock.unlock() }
        _privacyMode = enabled
    }

    static func isPrivacyMode() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _privacyMode
    }

    /// Overrides the visitor id attached to subsequent events. Works in both
    /// modes; in privacy mode it is the only way to get a stable cross-visit
    /// visitor id. Pass an empty string to clear the override.
    static func setVisitorId(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        _manualVisitorId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Overrides the session id attached to subsequent events. Works in both
    /// modes; in privacy mode it is the only way to control visit grouping
    /// client-side. Pass an empty string to clear the override.
    static func setSessionId(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        _manualSessionId = id.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Resolved visitor id: manual override, else (outside privacy mode) the
    /// persistent `UserDefaults` id, else empty.
    static func resolvedVisitorId() -> String {
        lock.lock()
        let manual = _manualVisitorId
        let privacy = _privacyMode
        lock.unlock()
        if !manual.isEmpty { return manual }
        if privacy { return "" }
        return Session.visitorId()
    }

    /// Resolved session id: manual override, else (outside privacy mode) the
    /// 30-minute rolling `UserDefaults` session, else empty.
    static func resolvedSessionId() -> String {
        lock.lock()
        let manual = _manualSessionId
        let privacy = _privacyMode
        lock.unlock()
        if !manual.isEmpty { return manual }
        if privacy { return "" }
        return Session.sessionId()
    }
}
