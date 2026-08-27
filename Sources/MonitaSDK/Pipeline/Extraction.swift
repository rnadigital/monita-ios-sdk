//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of the reference script's key path and template engine: getKeys,
/// dotAccess, multiply, and fillParamsFromData. Semantics are mirrored exactly,
/// including quoted path segments, array fan out, and the bounded regex helper.
public enum Extraction {

    /// Port of getKeys: splits "a.b.'c.d'" into ["a", "b", "c.d"]. Quoted
    /// segments (single or double quotes) may span dots.
    public static func splitKeys(_ path: String) -> [String] {
        let parts = path.components(separatedBy: ".")
        var acc: [String] = []
        var nextI: Int?
        var i = 0
        while i < parts.count {
            let x = parts[i]
            if x.hasPrefix("\"") || x.hasPrefix("'") {
                let endChar = String(x.prefix(1))
                if x.count >= 1, x.hasSuffix(endChar), x.count > 1 || x == endChar {
                    // Complete quoted segment inside one part.
                    if x.count <= 2 {
                        acc.append("")
                    } else {
                        acc.append(String(x.dropFirst().dropLast()))
                    }
                } else {
                    var dt: [String] = [String(x.dropFirst())]
                    var found = false
                    var j = i + 1
                    while j < parts.count {
                        if parts[j].hasSuffix(endChar) {
                            dt.append(String(parts[j].dropLast()))
                            nextI = j + 1
                            found = true
                            break
                        } else {
                            dt.append(parts[j])
                        }
                        j += 1
                    }
                    if found {
                        acc.append(dt.joined(separator: "."))
                    } else {
                        acc.append(x)
                    }
                }
            } else if let n = nextI {
                if n == i {
                    acc.append(x)
                    nextI = nil
                }
                // Parts consumed by a quoted segment are skipped.
            } else {
                acc.append(x)
            }
            i += 1
        }
        return acc
    }

    /// Port of dotAccess. Arrays fan out: an array value maps the remaining
    /// key over every element, flattens, and drops nulls; an empty result is
    /// missing. Returns nil for missing or JSON null values.
    public static func dotAccess(_ obj: JSONValue?, path: String) -> JSONValue? {
        dotAccess(obj, keys: splitKeys(path))
    }

    public static func dotAccess(_ obj: JSONValue?, keys: [String]) -> JSONValue? {
        var current = obj
        for key in keys {
            current = access(current, key: key)
        }
        return current
    }

    private static func access(_ value: JSONValue?, key: String) -> JSONValue? {
        guard let value = value else { return nil }
        switch value {
        case .object(let object):
            guard let found = object[key] else { return nil }
            if case .null = found { return nil }
            return found
        case .array(let array):
            var matches: [JSONValue] = []
            for element in array {
                guard let v = access(element, key: key) else { continue }
                if case .array(let inner) = v {
                    matches.append(contentsOf: flattenDeep(inner))
                } else if !isNull(v) {
                    matches.append(v)
                }
            }
            return matches.isEmpty ? nil : .array(matches)
        default:
            return nil
        }
    }

    private static func isNull(_ value: JSONValue) -> Bool {
        if case .null = value { return true }
        return false
    }

    /// Flattens nested arrays and drops JSON nulls, matching the reference's
    /// flatten plus null filter in dotAccess so fan out never interpolates a
    /// literal "null" into an event name.
    static func flattenDeep(_ array: [JSONValue]) -> [JSONValue] {
        var out: [JSONValue] = []
        for element in array {
            if case .array(let inner) = element {
                out.append(contentsOf: flattenDeep(inner))
            } else if !isNull(element) {
                out.append(element)
            }
        }
        return out
    }

    /// Port of multiply: concatenates parts left to right; an array part fans
    /// the accumulated strings out over every element (cartesian product).
    public static func multiply(_ items: [JSONValue]) -> [String] {
        var acc: [String] = [""]
        for item in items {
            if case .array(let elements) = item {
                var next: [String] = []
                for prefix in acc {
                    for element in elements {
                        next.append(contentsOf: multiply([.string(prefix), element]))
                    }
                }
                acc = next
            } else {
                let text = item.jsStringified
                acc = acc.map { $0 + text }
            }
        }
        return acc
    }

    /// Port of fillParamsFromData. A template without braces is a plain dot
    /// path lookup. With braces, "{{param}}" interpolates dot path values and
    /// "{{regex::pattern::field}}" applies a bounded regex (input capped at
    /// 4KB, capture group 1 preferred, null on no match or bad pattern).
    /// Array values fan out into one output string per combination.
    /// Returns nil when the input template is nil.
    public static func fillTemplate(_ template: String?, data: JSONValue) -> JSONValue? {
        guard let template = template, !template.isEmpty else {
            return template.map { .string($0) }
        }
        guard template.contains("{{") || template.contains("}}") else {
            return dotAccess(data, path: template)
        }

        var parts: [JSONValue] = []
        var literal = ""
        var rest = Substring(template)
        while let open = rest.range(of: "{{") {
            literal += rest[rest.startIndex..<open.lowerBound]
            if !literal.isEmpty {
                parts.append(.string(literal))
                literal = ""
            }
            let afterOpen = rest[open.upperBound...]
            if let close = afterOpen.range(of: "}}") {
                let parameter = String(afterOpen[afterOpen.startIndex..<close.lowerBound])
                if !parameter.isEmpty, let value = resolveParameter(parameter, data: data) {
                    parts.append(value)
                }
                rest = afterOpen[close.upperBound...]
            } else {
                // Unterminated parameter: the reference keeps the raw text.
                let parameter = String(afterOpen)
                if !parameter.isEmpty {
                    parts.append(.string(parameter))
                }
                rest = afterOpen[afterOpen.endIndex...]
            }
        }
        literal += rest
        if !literal.isEmpty {
            parts.append(.string(literal))
        }
        let output = multiply(parts)
        if output.count == 1 {
            return .string(output[0])
        }
        return .array(output.map { .string($0) })
    }

    private static let regexInputCap = 4096

    private static func resolveParameter(_ parameter: String, data: JSONValue) -> JSONValue? {
        let functionSplit = parameter.components(separatedBy: "::")
        if functionSplit.count == 3 {
            let fn = functionSplit[0]
            let pattern = functionSplit[1]
            let field = functionSplit[2]
            var value = dotAccess(data, path: field)
            if case .string(let text)? = value, fn == "regex" {
                value = applyRegex(pattern: pattern, to: text)
            }
            return value
        }
        return dotAccess(data, path: parameter)
    }

    private static func applyRegex(pattern: String, to text: String) -> JSONValue? {
        let bounded = String(text.prefix(regexInputCap))
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(bounded.startIndex..<bounded.endIndex, in: bounded)
        guard let match = regex.firstMatch(in: bounded, range: range) else { return nil }
        if match.numberOfRanges > 1 {
            let groupRange = match.range(at: 1)
            if groupRange.location != NSNotFound, let swiftRange = Range(groupRange, in: bounded) {
                return .string(String(bounded[swiftRange]))
            }
        }
        guard let swiftRange = Range(match.range, in: bounded) else { return nil }
        return .string(String(bounded[swiftRange]))
    }

    /// Loose falsiness matching the reference's getInOrder default test
    /// (value != undefined && value != null && value != false, with
    /// JavaScript loose equality). Empty strings and numeric zero strings
    /// compare loosely equal to false and count as absent.
    public static func isLooselyFalse(_ value: JSONValue?) -> Bool {
        guard let value = value else { return true }
        switch value {
        case .null:
            return true
        case .bool(let b):
            return !b
        case .int(let i):
            return i == 0
        case .double(let d):
            return d == 0
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { return true }
            if let n = Double(trimmed) { return n == 0 }
            return false
        case .array(let a):
            return isLooselyFalse(.string(JSONValue.array(a).jsStringified))
        case .object:
            return false
        }
    }
}
