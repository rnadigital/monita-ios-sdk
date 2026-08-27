//  Copyright RNA Digital PTY LTD

import Foundation

/// An ordered JSON object. Key insertion order is preserved because the
/// pipeline mirrors JavaScript object semantics: the parameter cap keeps the
/// first N keys in insertion order, exactly like the reference script.
public struct JSONObject: Equatable, Sendable {
    public private(set) var keys: [String] = []
    private var storage: [String: JSONValue] = [:]

    public init() {}

    public init(_ pairs: [(String, JSONValue)]) {
        for (key, value) in pairs { self[key] = value }
    }

    public subscript(key: String) -> JSONValue? {
        get { storage[key] }
        set {
            if let newValue = newValue {
                if storage[key] == nil { keys.append(key) }
                storage[key] = newValue
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public var count: Int { keys.count }

    public func contains(_ key: String) -> Bool { storage[key] != nil }

    public mutating func removeValue(forKey key: String) { self[key] = nil }

    /// Merge semantics of Object.assign: existing keys are overwritten in
    /// place, new keys append in the other object's order.
    public mutating func merge(_ other: JSONObject) {
        for key in other.keys { self[key] = other[key] }
    }

    /// Wire equality is key set plus values; key order never matters on the wire.
    public static func == (lhs: JSONObject, rhs: JSONObject) -> Bool {
        lhs.storage == rhs.storage
    }
}

/// A dynamic JSON value with ordered objects. Used for request data, config
/// decoding, and payload construction so wire behavior is fully deterministic.
public indirect enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object(JSONObject)

    public static func == (lhs: JSONValue, rhs: JSONValue) -> Bool {
        switch (lhs, rhs) {
        case (.null, .null): return true
        case let (.bool(a), .bool(b)): return a == b
        case let (.int(a), .int(b)): return a == b
        case let (.double(a), .double(b)): return a == b
        case let (.int(a), .double(b)), let (.double(b), .int(a)): return Double(a) == b
        case let (.string(a), .string(b)): return a == b
        case let (.array(a), .array(b)): return a == b
        case let (.object(a), .object(b)): return a == b
        default: return false
        }
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var objectValue: JSONObject? {
        if case .object(let o) = self { return o }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    /// Loose string form matching JavaScript string coercion, used by the
    /// template engine ("" + value) and loose equality.
    public var jsStringified: String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .int(let i): return String(i)
        case .double(let d): return JSONValue.formatDouble(d)
        case .string(let s): return s
        case .array(let a):
            return a.map { element -> String in
                if case .null = element { return "" }
                return element.jsStringified
            }.joined(separator: ",")
        case .object: return "[object Object]"
        }
    }

    static func formatDouble(_ d: Double) -> String {
        guard d.isFinite else { return "null" }
        if d == d.rounded(), abs(d) < 1e15 {
            return String(Int64(d))
        }
        return "\(d)"
    }
}

// MARK: - Serialization

extension JSONValue {
    /// Deterministic JSON text. Object keys serialize in insertion order.
    public func serialized() -> String {
        var out = ""
        serialize(into: &out)
        return out
    }

    public func serializedData() -> Data {
        Data(serialized().utf8)
    }

    private func serialize(into out: inout String) {
        switch self {
        case .null:
            out += "null"
        case .bool(let b):
            out += b ? "true" : "false"
        case .int(let i):
            out += String(i)
        case .double(let d):
            if d.isFinite {
                if d == d.rounded(), abs(d) < 1e15 {
                    out += String(Int64(d))
                } else {
                    out += "\(d)"
                }
            } else {
                out += "null"
            }
        case .string(let s):
            JSONValue.escape(s, into: &out)
        case .array(let a):
            out += "["
            for (i, v) in a.enumerated() {
                if i > 0 { out += "," }
                v.serialize(into: &out)
            }
            out += "]"
        case .object(let o):
            out += "{"
            var first = true
            for key in o.keys {
                guard let value = o[key] else { continue }
                if !first { out += "," }
                first = false
                JSONValue.escape(key, into: &out)
                out += ":"
                value.serialize(into: &out)
            }
            out += "}"
        }
    }

    private static func escape(_ s: String, into out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}

// MARK: - Parsing

/// Minimal recursive descent JSON parser producing ordered objects. Foundation
/// parsers do not preserve object key order, and key order feeds the parameter
/// cap, so the SDK carries its own parser. Depth capped defensively.
public enum JSONParser {
    public static func parse(_ text: String) -> JSONValue? {
        var scanner = Scanner(scalars: Array(text.unicodeScalars))
        scanner.skipWhitespace()
        guard let value = scanner.parseValue(depth: 0) else { return nil }
        scanner.skipWhitespace()
        guard scanner.isAtEnd else { return nil }
        return value
    }

    public static func parse(_ data: Data) -> JSONValue? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        return parse(text)
    }

    private struct Scanner {
        let scalars: [Unicode.Scalar]
        var index = 0
        static let maxDepth = 128

        init(scalars: [Unicode.Scalar]) { self.scalars = scalars }

        var isAtEnd: Bool { index >= scalars.count }

        mutating func skipWhitespace() {
            while index < scalars.count {
                let c = scalars[index]
                if c == " " || c == "\t" || c == "\n" || c == "\r" { index += 1 } else { break }
            }
        }

        mutating func parseValue(depth: Int) -> JSONValue? {
            guard depth < Scanner.maxDepth, index < scalars.count else { return nil }
            switch scalars[index] {
            case "{": return parseObject(depth: depth)
            case "[": return parseArray(depth: depth)
            case "\"": return parseString().map { .string($0) }
            case "t":
                return consume("true") ? .bool(true) : nil
            case "f":
                return consume("false") ? .bool(false) : nil
            case "n":
                return consume("null") ? JSONValue.null : nil
            default:
                return parseNumber()
            }
        }

        mutating func consume(_ word: String) -> Bool {
            let w = Array(word.unicodeScalars)
            guard index + w.count <= scalars.count else { return false }
            for (i, c) in w.enumerated() where scalars[index + i] != c { return false }
            index += w.count
            return true
        }

        mutating func parseObject(depth: Int) -> JSONValue? {
            index += 1
            var object = JSONObject()
            skipWhitespace()
            if index < scalars.count, scalars[index] == "}" { index += 1; return .object(object) }
            while true {
                skipWhitespace()
                guard let key = parseString() else { return nil }
                skipWhitespace()
                guard index < scalars.count, scalars[index] == ":" else { return nil }
                index += 1
                skipWhitespace()
                guard let value = parseValue(depth: depth + 1) else { return nil }
                object[key] = value
                skipWhitespace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "}" { index += 1; return .object(object) }
                return nil
            }
        }

        mutating func parseArray(depth: Int) -> JSONValue? {
            index += 1
            var array: [JSONValue] = []
            skipWhitespace()
            if index < scalars.count, scalars[index] == "]" { index += 1; return .array(array) }
            while true {
                skipWhitespace()
                guard let value = parseValue(depth: depth + 1) else { return nil }
                array.append(value)
                skipWhitespace()
                guard index < scalars.count else { return nil }
                if scalars[index] == "," { index += 1; continue }
                if scalars[index] == "]" { index += 1; return .array(array) }
                return nil
            }
        }

        mutating func parseString() -> String? {
            guard index < scalars.count, scalars[index] == "\"" else { return nil }
            index += 1
            var out = String.UnicodeScalarView()
            while index < scalars.count {
                let c = scalars[index]
                if c == "\"" { index += 1; return String(out) }
                if c == "\\" {
                    index += 1
                    guard index < scalars.count else { return nil }
                    let e = scalars[index]
                    switch e {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        guard let first = parseHex4() else { return nil }
                        var code = first
                        if code >= 0xD800, code <= 0xDBFF {
                            // Surrogate pair.
                            if index + 2 < scalars.count, scalars[index + 1] == "\\", scalars[index + 2] == "u" {
                                index += 2
                                guard let low = parseHex4(), low >= 0xDC00, low <= 0xDFFF else { return nil }
                                code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                code = 0xFFFD
                            }
                        } else if code >= 0xDC00, code <= 0xDFFF {
                            code = 0xFFFD
                        }
                        if let scalar = Unicode.Scalar(code) {
                            out.append(scalar)
                        } else {
                            out.append("\u{FFFD}")
                        }
                    default:
                        return nil
                    }
                    index += 1
                } else {
                    out.append(c)
                    index += 1
                }
            }
            return nil
        }

        mutating func parseHex4() -> UInt32? {
            guard index + 4 < scalars.count else { return nil }
            var value: UInt32 = 0
            for i in 1...4 {
                let c = scalars[index + i]
                let d: UInt32
                switch c {
                case "0"..."9": d = c.value - 48
                case "a"..."f": d = c.value - 87
                case "A"..."F": d = c.value - 55
                default: return nil
                }
                value = value * 16 + d
            }
            index += 4
            return value
        }

        mutating func parseNumber() -> JSONValue? {
            let start = index
            var sawFraction = false
            if index < scalars.count, scalars[index] == "-" { index += 1 }
            while index < scalars.count {
                let c = scalars[index]
                if c >= "0" && c <= "9" {
                    index += 1
                } else if c == "." || c == "e" || c == "E" || c == "+" || c == "-" {
                    sawFraction = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            let text = String(String.UnicodeScalarView(scalars[start..<index]))
            if !sawFraction, let i = Int64(text) { return .int(i) }
            guard let d = Double(text) else { return nil }
            return .double(d)
        }
    }
}
