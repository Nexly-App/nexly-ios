import Foundation

/// Scalar value allowed in the flat `cdata` payload (mirrors `CData` in
/// `@nexly/core`). All values are normalised to strings server-side, so the
/// contract stays a flat `String` / `Int` / `Double` / `Bool` map — nested
/// objects and arrays are not representable here on purpose.
public enum CDataValue: Sendable, Equatable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    var jsonValue: Any {
        switch self {
        case .string(let value): return value
        case .int(let value): return value
        case .double(let value): return value
        case .bool(let value): return value
        }
    }
}

extension CDataValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension CDataValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .int(value) }
}

extension CDataValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .double(value) }
}

extension CDataValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

/// User-defined custom analytics payload. Top-level scalar map, validated
/// server-side against the per-app "Custom data" registry. Mirrors `CData`
/// in `packages/core/src/collect.ts`.
public typealias CData = [String: CDataValue]

/// Typed override for the per-event standard attribution slot accepted by
/// `Nexly.customEvent`'s `context` parameter. Mirrors
/// `internal/apps/ingest_context.go::StandardAttributionKeys` and
/// `StandardContextOverride` in `packages/core/src/collect.ts` — keep all
/// three in sync when adding a new marketing parameter.
public struct StandardContextOverride: Sendable {
    public var utmSource: String?
    public var utmMedium: String?
    public var utmCampaign: String?
    public var utmContent: String?
    public var utmTerm: String?
    public var gclid: String?
    public var gadSource: String?
    public var gadCampaignId: String?
    public var fbclid: String?
    public var msclkid: String?
    public var ttclid: String?
    public var liFatId: String?
    public var yclid: String?
    public var mcCid: String?
    public var ref: String?

    public init(
        utmSource: String? = nil,
        utmMedium: String? = nil,
        utmCampaign: String? = nil,
        utmContent: String? = nil,
        utmTerm: String? = nil,
        gclid: String? = nil,
        gadSource: String? = nil,
        gadCampaignId: String? = nil,
        fbclid: String? = nil,
        msclkid: String? = nil,
        ttclid: String? = nil,
        liFatId: String? = nil,
        yclid: String? = nil,
        mcCid: String? = nil,
        ref: String? = nil
    ) {
        self.utmSource = utmSource
        self.utmMedium = utmMedium
        self.utmCampaign = utmCampaign
        self.utmContent = utmContent
        self.utmTerm = utmTerm
        self.gclid = gclid
        self.gadSource = gadSource
        self.gadCampaignId = gadCampaignId
        self.fbclid = fbclid
        self.msclkid = msclkid
        self.ttclid = ttclid
        self.liFatId = liFatId
        self.yclid = yclid
        self.mcCid = mcCid
        self.ref = ref
    }

    /// Wire-format key/value pairs (snake_case), skipping unset fields.
    func asContext() -> [String: Any] {
        var out: [String: Any] = [:]
        if let utmSource { out["utm_source"] = utmSource }
        if let utmMedium { out["utm_medium"] = utmMedium }
        if let utmCampaign { out["utm_campaign"] = utmCampaign }
        if let utmContent { out["utm_content"] = utmContent }
        if let utmTerm { out["utm_term"] = utmTerm }
        if let gclid { out["gclid"] = gclid }
        if let gadSource { out["gad_source"] = gadSource }
        if let gadCampaignId { out["gad_campaignid"] = gadCampaignId }
        if let fbclid { out["fbclid"] = fbclid }
        if let msclkid { out["msclkid"] = msclkid }
        if let ttclid { out["ttclid"] = ttclid }
        if let liFatId { out["li_fat_id"] = liFatId }
        if let yclid { out["yclid"] = yclid }
        if let mcCid { out["mc_cid"] = mcCid }
        if let ref { out["ref"] = ref }
        return out
    }
}

/// Auth fields for ingest (no transport URL). Mirrors `IngestCredentials`.
struct IngestCredentials: Sendable {
    let appId: String
    let apiToken: String
}

/// Event envelope passed to `buildCollectPayload`. Mirrors `TrackEventInput`
/// in `packages/core/src/collect.ts`.
struct TrackEventInput {
    let credentials: IngestCredentials
    let eventName: String
    let eventType: String
    let client: String?
    let privacyMode: Bool
    let context: [String: Any]
    let data: [String: Any]
    let cdata: CData?
    let sessionContext: [String: Any]?
}

/// Builds the JSON body for `POST /v1/collect` (snake_case wire format).
///
/// Duplicates `context["path"]` to the top-level `path` when present.
/// Includes `cdata` when the caller passed a non-empty map. Includes
/// `session_context` when provided (first event of a session). Pure
/// function, no UIKit/Foundation runtime dependency beyond `Foundation`
/// value types — safe to unit test without a simulator.
func buildCollectPayload(_ input: TrackEventInput) -> [String: Any] {
    var body: [String: Any] = [
        "app_id": input.credentials.appId,
        "api_token": input.credentials.apiToken,
        "event_name": input.eventName,
        "event_type": input.eventType,
        "context": input.context,
        "data": input.data,
    ]

    let client = (input.client ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !client.isEmpty {
        body["client"] = client
    }
    if input.privacyMode {
        body["privacy_mode"] = true
    }
    if let path = input.context["path"] as? String, !path.isEmpty {
        body["path"] = path
    }
    if let cdata = input.cdata, !cdata.isEmpty {
        body["cdata"] = cdata.mapValues { $0.jsonValue }
    }
    if let sessionContext = input.sessionContext, !sessionContext.isEmpty {
        body["session_context"] = sessionContext
    }

    return body
}
