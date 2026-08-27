//  Copyright RNA Digital PTY LTD

import Foundation

/// The batch shared envelope fields. These appear once per batch; everything
/// else is per event. Key names mirror the reference script exactly.
public struct SharedContext: Equatable, Sendable {
    public var token: String
    public var mv: String
    public var sv: String
    public var u: String
    public var p: String
    public var vid: String
    public var sid: String
    public var doValue: String
    public var rl: String
    public var env: String
    public var et: String
    public var cn: String?
    public var cid: String?

    public init(
        token: String,
        mv: String,
        sv: String,
        u: String,
        p: String,
        vid: String,
        sid: String,
        doValue: String,
        rl: String,
        env: String = "production",
        et: String = "",
        cn: String? = nil,
        cid: String? = nil
    ) {
        self.token = token
        self.mv = mv
        self.sv = sv
        self.u = u
        self.p = p
        self.vid = vid
        self.sid = sid
        self.doValue = doValue
        self.rl = rl
        self.env = env
        self.et = et
        self.cn = cn
        self.cid = cid
    }
}

public enum EventBuilder {

    /// Maximum parameters kept per event, mirroring MAX_PARAMS_TAKEN.
    public static let maxParamsTaken = 100

    /// The envelope keys hoisted out of each event when batching, in the
    /// reference's order.
    public static let batchSharedKeys: [String] = [
        "t", "dm", "mv", "sv", "u", "p", "vid", "sid", "s", "do", "rl", "env", "et", "cn", "cid",
    ]

    public static func envelopeObject(_ ctx: SharedContext) -> JSONObject {
        var object = JSONObject()
        object["t"] = .string(ctx.token)
        object["dm"] = .string("app")
        object["mv"] = .string(ctx.mv)
        object["sv"] = .string(ctx.sv)
        object["u"] = .string(ctx.u)
        object["p"] = .string(ctx.p)
        object["vid"] = .string(ctx.vid)
        object["sid"] = .string(ctx.sid)
        object["s"] = .string("ios-sdk")
        object["do"] = .string(ctx.doValue)
        object["rl"] = .string(ctx.rl)
        object["env"] = .string(ctx.env)
        object["et"] = .string(ctx.et)
        object["cn"] = ctx.cn.map { JSONValue.string($0) } ?? .null
        if let cid = ctx.cid {
            object["cid"] = .string(cid)
        }
        return object
    }

    /// Port of filterData: keep the first 100 parameters in insertion order,
    /// then apply the vendor's exclusion paths.
    public static func filterData(_ data: JSONObject, excludedPaths: [String]) -> JSONObject {
        var capped = JSONObject()
        for key in data.keys.prefix(maxParamsTaken) {
            capped[key] = data[key]
        }
        Exclusion.apply(&capped, excludedPaths: excludedPaths)
        return capped
    }

    /// Event name extraction in the reference's priority order: host resolver
    /// hook, config template, data.event, data.ev. Values that compare loosely
    /// equal to false (empty strings, zero) are treated as absent. Returns nil
    /// when nothing resolves; the wire value is then JSON null.
    public static func extractEvent(
        vendor: VendorConfig,
        data: JSONObject,
        hostResolver: ((String, JSONObject) -> String?)?
    ) -> JSONValue? {
        let wrapped = JSONValue.object(data)
        if let resolver = hostResolver, let resolved = resolver(vendor.vendorName, data) {
            if !Extraction.isLooselyFalse(.string(resolved)) {
                return .string(resolved)
            }
        }
        if let template = vendor.eventParameter, !template.isEmpty {
            let value = Extraction.fillTemplate(template, data: wrapped)
            if !Extraction.isLooselyFalse(value) {
                return value
            }
        }
        if let event = data["event"], !Extraction.isLooselyFalse(event) {
            return event
        }
        if let ev = data["ev"], !Extraction.isLooselyFalse(ev) {
            return ev
        }
        return nil
    }

    /// Builds one full flat payload (shared fields plus per event fields),
    /// exactly like the reference's sendData. The batcher splits it back into
    /// envelope and event by key. `st` is included only when known. Returns
    /// one payload per event when the extracted event fans out into an array.
    public static func buildPayloads(
        context: SharedContext,
        vendor: VendorConfig,
        data: JSONObject,
        vu: String,
        method: String,
        tm: Double,
        status: String?,
        hostResolver: ((String, JSONObject) -> String?)? = nil
    ) -> [JSONObject] {
        let event = extractEvent(vendor: vendor, data: data, hostResolver: hostResolver)
        let filtered = filterData(data, excludedPaths: vendor.excludeParameters)

        var base = envelopeObject(context)
        base["tm"] = .double(tm)
        base["e"] = event ?? .null
        base["vn"] = .string(vendor.vendorName)
        if let status = status {
            base["st"] = .string(status)
        }
        base["m"] = .string(method)
        base["vu"] = .string(vu)
        base["dt"] = .array([.object(filtered)])
        base["np"] = .array([])

        if case .array(let events)? = event {
            // Array fan out: one cloned payload per element.
            return events.map { element in
                var clone = base
                clone["e"] = element
                return clone
            }
        }
        return [base]
    }

    /// Builds the monita_env payload. The environment event carries only
    /// tm, e, vn, and dt beyond the envelope, matching the reference's
    /// reportEnvironment payload shape.
    public static func buildEnvironmentPayload(
        context: SharedContext,
        snapshot: JSONObject,
        tm: Double
    ) -> JSONObject {
        var payload = envelopeObject(context)
        payload["tm"] = .double(tm)
        payload["e"] = .string("monita_env")
        payload["vn"] = .string("Monita")
        payload["dt"] = .array([.object(snapshot)])
        return payload
    }

    /// Splits a flat payload into (shared envelope, event fields) by the
    /// reference's BATCH_SHARED_KEYS list.
    public static func split(_ payload: JSONObject) -> (shared: JSONObject, event: JSONObject) {
        var shared = JSONObject()
        var event = JSONObject()
        for key in payload.keys {
            guard let value = payload[key] else { continue }
            if batchSharedKeys.contains(key) {
                shared[key] = value
            } else {
                event[key] = value
            }
        }
        return (shared, event)
    }
}
