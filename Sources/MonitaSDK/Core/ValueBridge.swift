//  Copyright RNA Digital PTY LTD

import Foundation

/// Bridging between JSONValue and loosely typed host values ([String: Any])
/// for the public manual send, event filter, and event resolver APIs.
enum ValueBridge {

    static func toJSONValue(_ value: Any?) -> JSONValue {
        guard let value = value else { return .null }
        switch value {
        case is NSNull:
            return .null
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            let type = String(cString: number.objCType)
            if type == "f" || type == "d" {
                return .double(number.doubleValue)
            }
            return .int(number.int64Value)
        case let array as [Any]:
            return .array(array.map { toJSONValue($0) })
        case let dictionary as [String: Any]:
            var object = JSONObject()
            for key in dictionary.keys.sorted() {
                object[key] = toJSONValue(dictionary[key])
            }
            return .object(object)
        default:
            return .string(String(describing: value))
        }
    }

    static func toAny(_ value: JSONValue) -> Any {
        switch value {
        case .null:
            return NSNull()
        case .bool(let b):
            return b
        case .int(let i):
            return i
        case .double(let d):
            return d
        case .string(let s):
            return s
        case .array(let a):
            return a.map { toAny($0) }
        case .object(let o):
            return toDictionary(o)
        }
    }

    static func toDictionary(_ object: JSONObject) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in object.keys {
            if let value = object[key] {
                out[key] = toAny(value)
            }
        }
        return out
    }
}
