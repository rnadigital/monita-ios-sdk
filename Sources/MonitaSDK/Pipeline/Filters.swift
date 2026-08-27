//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of checkPassOnFilters and checkPassOnFilterGroups from the reference
/// script. A legacy flat filter list is an AND of all rules. Filter groups are
/// ORed; inside a group "all" means AND and "any" means OR. Unknown operators
/// pass (forward compatibility, matching the reference).
public enum FilterEngine {

    public static func passes(_ data: JSONValue, filters: [FilterRule]) -> Bool {
        for f in filters {
            let filterValues: [String?]
            if let vals = f.val {
                filterValues = vals.map { Optional($0) }
            } else {
                filterValues = [nil]
            }
            switch f.op {
            case "eq", "contains":
                let value = Extraction.fillTemplate(f.key, data: data)
                var result = false
                for filterValue in filterValues {
                    let hit: Bool
                    if f.op == "eq" {
                        hit = looseEquals(value, filterValue)
                    } else if case .string(let s)? = value, let fv = filterValue {
                        hit = s.contains(fv)
                    } else {
                        hit = false
                    }
                    if hit { result = true; break }
                }
                if !result { return false }
            case "ne":
                for filterValue in filterValues {
                    if looseEquals(Extraction.fillTemplate(f.key, data: data), filterValue) {
                        return false
                    }
                }
            case "blank":
                let value = Extraction.fillTemplate(f.key, data: data)
                if let value = value, !isJSONNull(value) {
                    if case .string(let s) = value, s.isEmpty {
                        // Empty string is blank; passes.
                    } else {
                        return false
                    }
                }
            case "not_blank":
                let value = Extraction.fillTemplate(f.key, data: data)
                if value == nil || isJSONNull(value) {
                    return false
                }
                if case .string(let s)? = value, s.isEmpty {
                    return false
                }
            case "exist":
                let value = Extraction.fillTemplate(f.key, data: data)
                if value == nil || isJSONNull(value) {
                    return false
                }
            case "not_exist":
                let value = Extraction.fillTemplate(f.key, data: data)
                if value != nil && !isJSONNull(value) {
                    return false
                }
            default:
                // Unknown operator: the filter passes, matching the reference.
                break
            }
        }
        return true
    }

    public static func passes(_ data: JSONValue, groups: [FilterGroup]) -> Bool {
        if groups.isEmpty { return true }
        for group in groups {
            if group.filters.isEmpty { continue }
            if group.op == "any" {
                for f in group.filters where passes(data, filters: [f]) {
                    return true
                }
            } else if passes(data, filters: group.filters) {
                return true
            }
        }
        return false
    }

    private static func isJSONNull(_ value: JSONValue?) -> Bool {
        if case .null? = value { return true }
        return false
    }

    /// JavaScript loose equality between an extracted value and a filter value
    /// string. Missing compares equal to a missing filter value; numbers
    /// compare numerically against numeric strings; arrays coerce to their
    /// comma joined string form.
    static func looseEquals(_ value: JSONValue?, _ filterValue: String?) -> Bool {
        let missing = value == nil || isJSONNull(value)
        guard let filterValue = filterValue else { return missing }
        guard let value = value, !missing else { return false }
        switch value {
        case .string(let s):
            return s == filterValue
        case .int(let i):
            return Double(filterValue).map { Double(i) == $0 } ?? false
        case .double(let d):
            return Double(filterValue).map { d == $0 } ?? false
        case .bool(let b):
            let n: Double = b ? 1 : 0
            return Double(filterValue).map { n == $0 } ?? false
        case .array:
            return value.jsStringified == filterValue
        default:
            return false
        }
    }
}
