//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of deleteProperty: removes keys by dot path, where any path segment
/// written as /pattern/ is a regular expression matched against the keys at
/// that level. A bad pattern aborts that exclusion path silently, matching the
/// reference's catch behavior.
public enum Exclusion {

    public static func deleteProperty(_ object: inout JSONObject, path: String) {
        let parts = path.components(separatedBy: ".")
        guard !parts.isEmpty else { return }
        var wrapped = JSONValue.object(object)
        if traverseAndDelete(&wrapped, parts: parts, index: 0), case .object(let updated) = wrapped {
            object = updated
        }
    }

    public static func apply(_ object: inout JSONObject, excludedPaths: [String]) {
        for path in excludedPaths {
            deleteProperty(&object, path: path)
        }
    }

    /// Returns false when a segment's regex fails to compile; the caller keeps
    /// the object unchanged in that case.
    private static func traverseAndDelete(_ value: inout JSONValue, parts: [String], index: Int) -> Bool {
        guard index < parts.count else { return true }
        guard case .object(var object) = value else { return true }
        let part = parts[index]

        let keysToProcess: [String]
        if part.count >= 2, part.hasPrefix("/"), part.hasSuffix("/") {
            let pattern = String(part.dropFirst().dropLast())
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
            keysToProcess = object.keys.filter { key in
                let range = NSRange(key.startIndex..<key.endIndex, in: key)
                return regex.firstMatch(in: key, range: range) != nil
            }
        } else {
            keysToProcess = [part]
        }

        if index == parts.count - 1 {
            for key in keysToProcess {
                object.removeValue(forKey: key)
            }
        } else {
            for key in keysToProcess {
                guard var child = object[key] else { continue }
                if case .null = child { continue }
                guard traverseAndDelete(&child, parts: parts, index: index + 1) else { return false }
                object[key] = child
            }
        }
        value = .object(object)
        return true
    }
}
