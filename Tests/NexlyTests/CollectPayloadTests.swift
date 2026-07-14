import Testing
@testable import Nexly

@Suite("buildCollectPayload")
struct CollectPayloadTests {
    private func credentials() -> IngestCredentials {
        IngestCredentials(appId: "app_123", apiToken: "nx_secret")
    }

    @Test("includes core fields and duplicates context.path to top-level path")
    func includesCoreFieldsAndPath() {
        let input = TrackEventInput(
            credentials: credentials(),
            eventName: "pageview",
            eventType: "pageview",
            client: "swift-ios",
            privacyMode: false,
            context: ["path": "/settings", "visitor_id": "v1"],
            data: [:],
            cdata: nil,
            sessionContext: nil
        )
        let body = buildCollectPayload(input)

        #expect(body["app_id"] as? String == "app_123")
        #expect(body["api_token"] as? String == "nx_secret")
        #expect(body["event_name"] as? String == "pageview")
        #expect(body["event_type"] as? String == "pageview")
        #expect(body["client"] as? String == "swift-ios")
        #expect(body["path"] as? String == "/settings")
        #expect(body["privacy_mode"] == nil)
        #expect(body["cdata"] == nil)
        #expect(body["session_context"] == nil)
    }

    @Test("drops empty cdata and session_context")
    func dropsEmptySlots() {
        let input = TrackEventInput(
            credentials: credentials(),
            eventName: "custom_event",
            eventType: "custom",
            client: "swift-ios",
            privacyMode: false,
            context: [:],
            data: [:],
            cdata: [:],
            sessionContext: [:]
        )
        let body = buildCollectPayload(input)

        #expect(body["cdata"] == nil)
        #expect(body["session_context"] == nil)
        #expect(body["path"] == nil)
    }

    @Test("includes non-empty cdata and session_context")
    func includesNonEmptySlots() {
        let input = TrackEventInput(
            credentials: credentials(),
            eventName: "checkout_started",
            eventType: "custom",
            client: "swift-ios",
            privacyMode: false,
            context: [:],
            data: [:],
            cdata: ["cart_value_cents": 4200, "currency": "usd"],
            sessionContext: ["platform": "ios"]
        )
        let body = buildCollectPayload(input)

        let cdata = body["cdata"] as? [String: Any]
        #expect(cdata?["cart_value_cents"] as? Int == 4200)
        #expect(cdata?["currency"] as? String == "usd")

        let sessionContext = body["session_context"] as? [String: Any]
        #expect(sessionContext?["platform"] as? String == "ios")
    }

    @Test("sets privacy_mode only when true")
    func setsPrivacyModeOnlyWhenTrue() {
        let disabled = buildCollectPayload(
            TrackEventInput(
                credentials: credentials(), eventName: "e", eventType: "custom", client: nil,
                privacyMode: false, context: [:], data: [:], cdata: nil, sessionContext: nil
            )
        )
        #expect(disabled["privacy_mode"] == nil)

        let enabled = buildCollectPayload(
            TrackEventInput(
                credentials: credentials(), eventName: "e", eventType: "custom", client: nil,
                privacyMode: true, context: [:], data: [:], cdata: nil, sessionContext: nil
            )
        )
        #expect(enabled["privacy_mode"] as? Bool == true)
    }

    @Test("omits client when nil or blank")
    func omitsBlankClient() {
        let bodyNil = buildCollectPayload(
            TrackEventInput(
                credentials: credentials(), eventName: "e", eventType: "custom", client: nil,
                privacyMode: false, context: [:], data: [:], cdata: nil, sessionContext: nil
            )
        )
        #expect(bodyNil["client"] == nil)

        let bodyBlank = buildCollectPayload(
            TrackEventInput(
                credentials: credentials(), eventName: "e", eventType: "custom", client: "   ",
                privacyMode: false, context: [:], data: [:], cdata: nil, sessionContext: nil
            )
        )
        #expect(bodyBlank["client"] == nil)
    }
}
