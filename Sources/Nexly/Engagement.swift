import Foundation
#if canImport(UIKit)
import UIKit
#endif

/// `active_seconds` counter, 60s heartbeat, and `session_ping` / `session_end`
/// driven by app lifecycle notifications. Mirrors
/// `packages/react-native/src/engagement.ts`.
///
/// Uses `Timer` + `NotificationCenter` target-action APIs (rather than
/// closures) so the whole class can be safely main-actor isolated without
/// fighting `Sendable` closure requirements around `self`.
@MainActor
final class Engagement: NSObject {
    private let collectUrl: String
    private let appId: String
    private let apiToken: String
    private let client: String?

    private var activeSeconds: Int = 0
    private var sessionContextSent = false
    private var tickTimer: Timer?
    private var heartbeatTimer: Timer?
    private var observing = false

    private static let tickInterval: TimeInterval = 1
    private static let heartbeatInterval: TimeInterval = 60

    init(collectUrl: String, appId: String, apiToken: String, client: String?) {
        self.collectUrl = collectUrl
        self.appId = appId
        self.apiToken = apiToken
        self.client = client
    }

    func start() {
        stop()

        tickTimer = Timer.scheduledTimer(
            timeInterval: Self.tickInterval, target: self, selector: #selector(tick), userInfo: nil, repeats: true
        )
        heartbeatTimer = Timer.scheduledTimer(
            timeInterval: Self.heartbeatInterval, target: self, selector: #selector(sendHeartbeat), userInfo: nil,
            repeats: true
        )
        sendHeartbeat()

        #if canImport(UIKit)
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(handleWillResignActive), name: UIApplication.willResignActiveNotification,
            object: nil
        )
        center.addObserver(
            self, selector: #selector(handleDidBecomeActive), name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        observing = true
        #endif
    }

    func stop() {
        tickTimer?.invalidate()
        tickTimer = nil
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if observing {
            NotificationCenter.default.removeObserver(self)
            observing = false
        }
        if activeSeconds > 0 {
            send(eventName: "session_end", eventType: "lifecycle", data: ["active_seconds": activeSeconds])
            activeSeconds = 0
        }
    }

    @objc private func tick() {
        activeSeconds += 1
    }

    @objc private func sendHeartbeat() {
        send(eventName: "heartbeat", eventType: "lifecycle", data: ["active_seconds": activeSeconds], includeSessionContext: true)
    }

    @objc private func handleWillResignActive() {
        if activeSeconds > 0 {
            send(eventName: "session_ping", eventType: "lifecycle", data: ["active_seconds": activeSeconds])
        }
    }

    @objc private func handleDidBecomeActive() {
        if !Identity.isPrivacyMode() {
            Session.touch()
        }
    }

    private func send(eventName: String, eventType: String, data: [String: Any], includeSessionContext: Bool = false) {
        var sessionContext: [String: Any]?
        if includeSessionContext, !sessionContextSent {
            sessionContextSent = true
            sessionContext = DeviceMeta.collectSessionMeta()
        }
        let payload = buildCollectPayload(
            TrackEventInput(
                credentials: IngestCredentials(appId: appId, apiToken: apiToken),
                eventName: eventName,
                eventType: eventType,
                client: client,
                privacyMode: Identity.isPrivacyMode(),
                context: DeviceMeta.collectEventMeta(),
                data: data,
                cdata: nil,
                sessionContext: sessionContext
            )
        )
        Transport.send(url: collectUrl, payload: payload)
    }
}
