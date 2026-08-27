//  Copyright RNA Digital PTY LTD

import Foundation

/// One filter rule. `op` is kept as a raw string so unknown operators pass
/// through to the engine (which lets them pass, matching the reference).
public struct FilterRule: Equatable, Sendable {
    public var key: String
    public var op: String?
    public var val: [String]?

    public init(key: String, op: String?, val: [String]? = nil) {
        self.key = key
        self.op = op
        self.val = val
    }
}

public struct FilterGroup: Equatable, Sendable {
    public var op: String
    public var filters: [FilterRule]

    public init(op: String, filters: [FilterRule]) {
        self.op = op
        self.filters = filters
    }
}

/// One vendor entry decoded from the remote config. The wire keys
/// `eventParamter` and `execludeParameters` are legacy misspellings that are
/// decoded as is; internal names are spelled correctly.
public struct VendorConfig: Equatable, Sendable {
    public var vendorName: String
    public var urlPatternMatches: [String]
    public var eventParameter: String?
    public var excludeParameters: [String]
    public var filters: [FilterRule]
    public var filterGroups: [FilterGroup]

    public init(
        vendorName: String,
        urlPatternMatches: [String],
        eventParameter: String? = nil,
        excludeParameters: [String] = [],
        filters: [FilterRule] = [],
        filterGroups: [FilterGroup] = []
    ) {
        self.vendorName = vendorName
        self.urlPatternMatches = urlPatternMatches
        self.eventParameter = eventParameter
        self.excludeParameters = excludeParameters
        self.filters = filters
        self.filterGroups = filterGroups
    }
}

public struct RemoteConfig: Equatable, Sendable {
    public var monitoringVersion: String
    public var allowManualMonitoring: Bool
    public var monitoringStatus: String?
    public var vendors: [VendorConfig]

    public init(
        monitoringVersion: String,
        allowManualMonitoring: Bool = false,
        monitoringStatus: String? = nil,
        vendors: [VendorConfig] = []
    ) {
        self.monitoringVersion = monitoringVersion
        self.allowManualMonitoring = allowManualMonitoring
        self.monitoringStatus = monitoringStatus
        self.vendors = vendors
    }

    /// Tolerant decode: unknown fields are ignored, wrong types degrade to
    /// defaults, and nothing is ever fatal. Returns nil only when the input is
    /// not a JSON object at all.
    public static func decode(_ json: JSONValue) -> RemoteConfig? {
        guard case .object(let root) = json else { return nil }
        var config = RemoteConfig(monitoringVersion: "")

        if let version = root["monitoringVersion"] {
            switch version {
            case .string(let s): config.monitoringVersion = s
            case .int(let i): config.monitoringVersion = String(i)
            case .double(let d): config.monitoringVersion = JSONValue.formatDouble(d)
            default: break
            }
        }
        if case .bool(let allow)? = root["allowManualMonitoring"] {
            config.allowManualMonitoring = allow
        }
        if case .string(let status)? = root["monitoringStatus"] {
            config.monitoringStatus = status
        }
        if case .array(let vendors)? = root["vendors"] {
            for entry in vendors {
                if let vendor = decodeVendor(entry) {
                    config.vendors.append(vendor)
                }
            }
        }
        return config
    }

    public static func decode(data: Data) -> RemoteConfig? {
        guard let json = JSONParser.parse(data) else { return nil }
        return decode(json)
    }

    private static func decodeVendor(_ json: JSONValue) -> VendorConfig? {
        guard case .object(let object) = json,
              case .string(let name)? = object["vendorName"] else {
            return nil
        }
        var vendor = VendorConfig(vendorName: name, urlPatternMatches: [])
        if case .array(let patterns)? = object["urlPatternMatches"] {
            vendor.urlPatternMatches = patterns.compactMap { $0.stringValue }
        }
        // Legacy misspelled wire key, decoded as is.
        if case .string(let template)? = object["eventParamter"] {
            vendor.eventParameter = template
        }
        // Legacy misspelled wire key, decoded as is.
        if case .array(let excluded)? = object["execludeParameters"] {
            vendor.excludeParameters = excluded.compactMap { $0.stringValue }
        }
        if case .array(let filters)? = object["filters"] {
            vendor.filters = filters.compactMap(decodeFilter)
        }
        if case .array(let groups)? = object["filterGroups"] {
            for entry in groups {
                guard case .object(let g) = entry else { continue }
                let op = g["op"]?.stringValue ?? "all"
                var rules: [FilterRule] = []
                if case .array(let fs)? = g["filters"] {
                    rules = fs.compactMap(decodeFilter)
                }
                vendor.filterGroups.append(FilterGroup(op: op == "any" ? "any" : "all", filters: rules))
            }
        }
        return vendor
    }

    private static func decodeFilter(_ json: JSONValue) -> FilterRule? {
        guard case .object(let object) = json,
              case .string(let key)? = object["key"] else {
            return nil
        }
        var rule = FilterRule(key: key, op: object["op"]?.stringValue)
        if let val = object["val"] {
            switch val {
            case .string(let s):
                rule.val = [s]
            case .array(let items):
                rule.val = items.map { $0.stringValue ?? $0.jsStringified }
            default:
                break
            }
        }
        return rule
    }
}
