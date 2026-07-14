import Foundation

/// Fire-and-forget JSON POST to the collector. Errors are swallowed —
/// analytics must not crash or block the host app. Mirrors
/// `packages/react-native/src/transport.ts`.
enum Transport {
    /// Synthetic `Origin` header — native apps don't send one by default,
    /// but the collector enforces an allowlist. Add this origin once per
    /// app in the dashboard to authorize native events from this SDK.
    static let nativeOrigin = "nexlyswift://device"

    static func send(url: String, payload: [String: Any]) -> Bool {
        guard let endpoint = URL(string: url) else { return false }
        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return false }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(nativeOrigin, forHTTPHeaderField: "Origin")
        request.httpBody = body

        let task = URLSession.shared.dataTask(with: request) { _, _, _ in }
        task.resume()
        return true
    }
}
