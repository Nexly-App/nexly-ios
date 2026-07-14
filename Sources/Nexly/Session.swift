import Foundation

/// `UserDefaults`-backed visitor / session identifiers with a 30-minute idle
/// timeout on the session id. Mirrors `packages/react-native/src/session.ts`,
/// but synchronous end-to-end — `UserDefaults` reads/writes are synchronous on
/// iOS, so unlike the RN SDK there is no `prewarmIds` step.
enum Session {
    private static let lock = NSLock()

    private static let visitorKey = "nexly_visitor_id"
    private static let sessionKey = "nexly_session_id"
    private static let sessionTsKey = "nexly_session_ts"
    private static let sessionTimeout: TimeInterval = 30 * 60

    private static func generateId() -> String {
        UUID().uuidString.lowercased()
    }

    /// Persistent visitor id, generated and stored on first access.
    static func visitorId() -> String {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: visitorKey), !existing.isEmpty {
            return existing
        }
        let id = generateId()
        defaults.set(id, forKey: visitorKey)
        return id
    }

    /// Current session id. Rolls over to a new id after `sessionTimeout` of
    /// inactivity; otherwise extends the existing session by touching the
    /// timestamp. Every call is itself an activity signal.
    static func sessionId() -> String {
        lock.lock()
        defer { lock.unlock() }
        let defaults = UserDefaults.standard
        let now = Date().timeIntervalSince1970
        let lastTs = defaults.double(forKey: sessionTsKey)
        let existing = defaults.string(forKey: sessionKey)

        let id: String
        if let existing, !existing.isEmpty, lastTs > 0, now - lastTs < sessionTimeout {
            id = existing
        } else {
            id = generateId()
            defaults.set(id, forKey: sessionKey)
        }
        defaults.set(now, forKey: sessionTsKey)
        return id
    }

    /// Explicit activity signal used by the engagement heartbeat; extends the
    /// session or rolls a new one exactly like `sessionId()`.
    static func touch() {
        _ = sessionId()
    }
}
