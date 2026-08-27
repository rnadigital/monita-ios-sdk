//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of getBodyJSON, getDataByType, and fillDataFromBody. Extracts request
/// parameters from the URL query string (standard, legacy semicolon, and
/// matrix forms) and from the body when it is parseable as JSON,
/// form urlencoded pairs, or plain key=value text. Binary bodies contribute
/// nothing; URL parameters are still captured.
public enum BodyParser {

    public static let bodyReadCap = 64 * 1024

    /// Returns nil when the URL cannot be parsed (the reference drops the
    /// capture in that case).
    public static func parse(url: String, body: Data?, contentTypeHint: String? = nil) -> JSONObject? {
        guard let components = URLComponents(string: url), components.scheme != nil else {
            return nil
        }
        var data = JSONObject()
        parseURLParameters(components, into: &data)
        if let body = body, body.count <= bodyReadCap, !body.isEmpty {
            if let text = String(data: body, encoding: .utf8) {
                parseBodyString(text, hint: contentTypeHint, into: &data)
            }
            // Binary bodies are never decoded; URL parameters only.
        }
        return data
    }

    // MARK: - URL parameters

    private static func parseURLParameters(_ components: URLComponents, into data: inout JSONObject) {
        let rawQuery = components.percentEncodedQuery ?? ""
        let path = components.percentEncodedPath
        if !rawQuery.isEmpty, !rawQuery.contains("&"), rawQuery.components(separatedBy: ";").count > 1 {
            // Legacy semicolon separated query parameters.
            for part in rawQuery.components(separatedBy: ";") {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 {
                    data[percentDecode(kv[0])] = .string(percentDecode(kv[1]))
                }
            }
        } else if !rawQuery.isEmpty, (rawQuery.components(separatedBy: "&").first ?? "").count > 0 {
            // Standard query parameters. The reference decodes each value a
            // second time through decodeURIComponent, so a doubly encoded
            // value arrives fully decoded.
            for part in rawQuery.components(separatedBy: "&") {
                guard !part.isEmpty else { continue }
                let kv = split2(part, on: "=")
                let key = formDecode(kv.0)
                let value = percentDecode(formDecode(kv.1))
                if !key.isEmpty {
                    data[key] = .string(value)
                }
            }
        } else if path.components(separatedBy: ";").count > 1 {
            // Legacy matrix parameters on the path.
            for part in path.components(separatedBy: ";").dropFirst() {
                let kv = part.components(separatedBy: "=")
                if kv.count == 2 {
                    data[percentDecode(kv[0])] = .string(percentDecode(kv[1]))
                }
            }
        }
    }

    // MARK: - Body

    private static func parseBodyString(_ body: String, hint: String?, into data: inout JSONObject) {
        var content: ParsedBody
        if let json = JSONParser.parse(body) {
            content = fromJSONValue(json)
        } else if body.components(separatedBy: ";").count > 1 {
            let pairs = body.components(separatedBy: ";")
                .map { $0.components(separatedBy: "=") }
                .filter { $0.count == 2 }
            if pairs.count > 1 {
                var object = JSONObject()
                for kv in pairs {
                    object[kv[0]] = .string(percentDecode(kv[1]))
                }
                content = .object(object)
            } else {
                content = .string(body)
            }
        } else if body.components(separatedBy: "&").count > 1 {
            let pairs = formPairs(body)
            if (pairs.count == 1 && !pairs[0].1.isEmpty) || pairs.count > 1 {
                var object = JSONObject()
                for (key, value) in pairs {
                    object[key] = .string(percentDecode(value))
                }
                content = .object(object)
            } else {
                content = .string(body)
            }
        } else {
            content = .string(body)
        }
        fillData(&data, from: content, hint: hint)
    }

    /// Port of getDataByType's classification of a parsed value.
    enum ParsedBody {
        case null
        case primitive(JSONValue)
        case string(String)
        case array([ParsedBody])
        case object(JSONObject)
    }

    private static func fromJSONValue(_ value: JSONValue) -> ParsedBody {
        switch value {
        case .null: return .null
        case .bool, .int, .double: return .primitive(value)
        case .string(let s): return .string(s)
        case .array(let a): return .array(a.map(fromJSONValue))
        case .object(let o): return .object(o)
        }
    }

    /// Port of fillDataFromBody.
    static func fillData(_ data: inout JSONObject, from body: ParsedBody, hint: String?) {
        let parsed = classify(body, hint: hint)
        switch parsed {
        case .null:
            break
        case .primitive(let v):
            data["value"] = v
        case .string(let s):
            data["value"] = .string(s)
        case .array(let items):
            for (i, item) in items.enumerated() {
                switch classify(item, hint: nil) {
                case .null:
                    data[String(i)] = .null
                case .primitive(let v):
                    data[String(i)] = v
                case .string(let s):
                    data[String(i)] = .string(s)
                case .object(let o):
                    data[String(i)] = .object(o)
                case .array:
                    // The reference assigns an empty object for nested arrays.
                    data[String(i)] = .object(JSONObject())
                }
            }
        case .object(let o):
            data.merge(o)
        }
    }

    /// Port of getDataByType for string inputs: retry JSON when hinted or
    /// prefixed, then try URL parameter pairs, else keep the plain string.
    private static func classify(_ body: ParsedBody, hint: String?) -> ParsedBody {
        guard case .string(let text) = body else { return body }
        if hint == "application/json" || text.hasPrefix("{") || text.hasPrefix("[") {
            if let json = JSONParser.parse(text) {
                return fromJSONValue(json)
            }
        }
        let pairs = formPairs(text)
        if pairs.count == 1, pairs[0].0 == text, pairs[0].1.isEmpty {
            // Not really URL parameters; keep the string.
            return .string(text)
        }
        if !pairs.isEmpty {
            var object = JSONObject()
            for (key, value) in pairs {
                object[key] = .string(value)
            }
            return .object(object)
        }
        return .string(text)
    }

    // MARK: - Decoding helpers

    /// URLSearchParams style pairs: split on &, then on the first =, decode
    /// percent escapes with + treated as space.
    static func formPairs(_ text: String) -> [(String, String)] {
        var out: [(String, String)] = []
        for part in text.components(separatedBy: "&") {
            guard !part.isEmpty else { continue }
            let kv = split2(part, on: "=")
            out.append((formDecode(kv.0), formDecode(kv.1)))
        }
        return out
    }

    private static func split2(_ text: String, on separator: Character) -> (String, String) {
        if let idx = text.firstIndex(of: separator) {
            return (String(text[..<idx]), String(text[text.index(after: idx)...]))
        }
        return (text, "")
    }

    /// decodeURIComponent equivalent; on malformed escapes the input is kept
    /// as is (the reference would throw and drop the event; keeping the raw
    /// value is safer and never loses the capture).
    static func percentDecode(_ text: String) -> String {
        text.removingPercentEncoding ?? text
    }

    /// application/x-www-form-urlencoded decode: + is space, then percent
    /// escapes.
    static func formDecode(_ text: String) -> String {
        let plusReplaced = text.replacingOccurrences(of: "+", with: " ")
        return plusReplaced.removingPercentEncoding ?? plusReplaced
    }
}
