//  Copyright RNA Digital PTY LTD

import Foundation

/// Exact port of the reference script's vendor matching so web and mobile
/// match identically on shared configs.
///
/// stripDomains: a pattern starting with "http" has "http://" removed and
/// "https://" replaced with "/" (so https://x.com becomes /x.com, and its
/// derived match string //x.com anchors after the scheme exactly as it does
/// on the web). No www stripping, no lowercasing: matching is case sensitive
/// substring containment, exactly like the reference's indexOf.
///
/// The match loop checks every "/" + pattern string first (in config order),
/// then every "." + pattern string, and the first containing match wins; the
/// vendor is then resolved from the pattern map, where a duplicate pattern
/// belongs to the last vendor that declared it (JS object assignment).
public enum VendorMatcher {

    /// Port of stripDomains for one pattern.
    public static func stripDomain(_ pattern: String) -> String {
        guard pattern.hasPrefix("http") else { return pattern }
        var p = pattern
        if let range = p.range(of: "http://") {
            p.removeSubrange(range)
        }
        if let range = p.range(of: "https://") {
            p.replaceSubrange(range, with: "/")
        }
        return p
    }

    public static func vendorNamed(_ name: String, in vendors: [VendorConfig]) -> VendorConfig? {
        vendors.first { $0.vendorName == name }
    }

    /// Convenience for one off matching (tests); production code compiles
    /// once per config.
    public static func match(url: String, vendors: [VendorConfig]) -> VendorConfig? {
        CompiledVendorMatcher(vendors: vendors).match(url: url)
    }
}

/// Match strings and pattern map precomputed once per config.
public struct CompiledVendorMatcher: Sendable {
    public let vendors: [VendorConfig]
    /// Ordered as the reference iterates: all "/" prefixed strings in config
    /// order, then all "." prefixed strings, deduplicated keeping the first.
    public let matchStrings: [String]
    private let patternToVendorIndex: [String: Int]

    public init(vendors: [VendorConfig]) {
        self.vendors = vendors
        var map: [String: Int] = [:]
        var orderedPatterns: [String] = []
        for (index, vendor) in vendors.enumerated() {
            for raw in vendor.urlPatternMatches {
                let pattern = VendorMatcher.stripDomain(raw)
                if map[pattern] == nil {
                    orderedPatterns.append(pattern)
                }
                // A duplicate pattern belongs to the last vendor declaring it.
                map[pattern] = index
            }
        }
        patternToVendorIndex = map
        var strings: [String] = []
        var seen = Set<String>()
        for pattern in orderedPatterns {
            let candidate = "/" + pattern
            if seen.insert(candidate).inserted {
                strings.append(candidate)
            }
        }
        for pattern in orderedPatterns {
            let candidate = "." + pattern
            if seen.insert(candidate).inserted {
                strings.append(candidate)
            }
        }
        matchStrings = strings
    }

    /// Case sensitive substring match, first match string wins.
    public func match(url: String) -> VendorConfig? {
        for candidate in matchStrings where url.contains(candidate) {
            let pattern = String(candidate.dropFirst())
            if let index = patternToVendorIndex[pattern] {
                return vendors[index]
            }
            return nil
        }
        return nil
    }
}
