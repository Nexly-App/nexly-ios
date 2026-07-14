import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// Device / session metadata collection. Mirrors
/// `packages/react-native/src/device-meta.ts`.
enum DeviceMeta {
    /// Session-stable metadata: OS, screen, locale, timezone. Collected once
    /// per session and sent as `session_context`. Touches `UIScreen` /
    /// `UIDevice`, so it must run on the main actor.
    @MainActor
    static func collectSessionMeta() -> [String: Any] {
        var out: [String: Any] = [:]

        out["platform"] = "ios"

        #if canImport(UIKit)
        let device = UIDevice.current
        out["os_version"] = device.systemVersion

        let screen = UIScreen.main
        let scale = screen.scale
        out["screen_width"] = Int((screen.bounds.width * scale).rounded())
        out["screen_height"] = Int((screen.bounds.height * scale).rounded())
        out["viewport_width"] = Int(screen.bounds.width.rounded())
        out["viewport_height"] = Int(screen.bounds.height.rounded())
        out["device_pixel_ratio"] = scale
        out["user_agent"] = "nexly-swift-ios/\(device.systemVersion)"
        #endif

        let locale = Locale.current.identifier
        out["language"] = locale
        out["locale"] = locale
        out["timezone"] = TimeZone.current.identifier

        return out
    }

    /// Per-event volatile metadata: resolved visitor / session ids. `path`
    /// is set by the caller from the current screen name.
    static func collectEventMeta() -> [String: Any] {
        var out: [String: Any] = [:]
        let visitorId = Identity.resolvedVisitorId()
        let sessionId = Identity.resolvedSessionId()
        if !visitorId.isEmpty { out["visitor_id"] = visitorId }
        if !sessionId.isEmpty { out["session_id"] = sessionId }
        return out
    }
}
