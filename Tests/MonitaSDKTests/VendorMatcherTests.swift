//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

/// Matching parity guard: these semantics are ported EXACTLY from the
/// reference script (stripDomains and the match loop) so web and mobile match
/// identically on shared configs.
final class VendorMatcherTests: XCTestCase {

    private func vendor(_ name: String, _ patterns: [String]) -> VendorConfig {
        VendorConfig(vendorName: name, urlPatternMatches: patterns)
    }

    // MARK: - stripDomains port

    func testStripDomainsMirrorsTheReference() {
        // http:// is removed outright.
        XCTAssertEqual(VendorMatcher.stripDomain("http://example.com"), "example.com")
        // https:// becomes a leading slash, the reference's quirk.
        XCTAssertEqual(VendorMatcher.stripDomain("https://facebook.com/tr"), "/facebook.com/tr")
        // Anything not starting with http passes through untouched: no www
        // stripping, no lowercasing.
        XCTAssertEqual(VendorMatcher.stripDomain("www.Facebook.com/tr"), "www.Facebook.com/tr")
        XCTAssertEqual(VendorMatcher.stripDomain("Google-Analytics.com/collect"), "Google-Analytics.com/collect")
    }

    func testHttpsPatternAnchorsAfterSchemeLikeTheReference() {
        // https://facebook.com/tr strips to /facebook.com/tr, so the derived
        // match string //facebook.com/tr matches right after the scheme.
        let vendors = [vendor("FB", ["https://facebook.com/tr"])]
        XCTAssertEqual(VendorMatcher.match(url: "https://facebook.com/tr?id=1", vendors: vendors)?.vendorName, "FB")
        // The anchoring effect: an https:// pattern only matches right after
        // the scheme, so a www subdomain URL contains neither
        // //facebook.com/tr nor ./facebook.com/tr and does not match. This is
        // the reference's behavior for https:// prefixed patterns.
        XCTAssertNil(VendorMatcher.match(url: "https://www.facebook.com/tr?id=1", vendors: vendors))
    }

    // MARK: - Match loop

    func testMatchesSlashPrefixedPattern() {
        let vendors = [vendor("FB", ["facebook.com/tr"])]
        XCTAssertEqual(VendorMatcher.match(url: "https://www.facebook.com/tr?id=1", vendors: vendors)?.vendorName, "FB")
    }

    func testMatchesDotPrefixedPattern() {
        let vendors = [vendor("GA", ["google-analytics.com/g/collect"])]
        XCTAssertEqual(
            VendorMatcher.match(url: "https://region1.google-analytics.com/g/collect?v=2", vendors: vendors)?.vendorName,
            "GA"
        )
    }

    func testNoBareSubstringMatch() {
        // The pattern must be preceded by "/" or "." in the URL.
        let vendors = [vendor("X", ["ample.com"])]
        XCTAssertNil(VendorMatcher.match(url: "https://example.com/page", vendors: vendors))
    }

    func testMatchingIsCaseSensitiveLikeTheReference() {
        let vendors = [vendor("FB", ["Facebook.com/tr"])]
        // indexOf in the reference is case sensitive; a lowercase URL does not
        // contain the mixed case pattern.
        XCTAssertNil(VendorMatcher.match(url: "https://www.facebook.com/tr?x=1", vendors: vendors))
        XCTAssertEqual(VendorMatcher.match(url: "https://www.Facebook.com/tr?x=1", vendors: vendors)?.vendorName, "FB")
    }

    func testSlashStringsAreCheckedBeforeDotStrings() {
        // The reference iterates every "/" + pattern string before any
        // "." + pattern string, so a slash match of a later vendor beats a
        // dot match of an earlier one.
        let vendors = [
            vendor("DotVendor", ["tracker.test/collect"]),
            vendor("SlashVendor", ["sub.tracker.test/collect"]),
        ]
        // URL contains ".tracker.test/collect" (DotVendor's dot string) AND
        // "/sub.tracker.test/collect"? No: it contains "//sub.tracker.test".
        let url = "https://sub.tracker.test/collect?v=1"
        XCTAssertEqual(VendorMatcher.match(url: url, vendors: vendors)?.vendorName, "SlashVendor")
    }

    func testDuplicatePatternBelongsToLastVendor() {
        let vendors = [
            vendor("First", ["shared.test/p"]),
            vendor("Second", ["shared.test/p"]),
        ]
        XCTAssertEqual(VendorMatcher.match(url: "https://shared.test/p", vendors: vendors)?.vendorName, "Second")
    }

    func testFirstPatternInConfigOrderWins() {
        let vendors = [
            vendor("First", ["shared.test/path"]),
            vendor("Second", ["shared.test"]),
        ]
        XCTAssertEqual(VendorMatcher.match(url: "https://shared.test/path", vendors: vendors)?.vendorName, "First")
    }

    func testQueryStringPatternsMatch() {
        let vendors = [vendor("FB", ["facebook.com/tr/?id=8117817644981394"])]
        XCTAssertEqual(
            VendorMatcher.match(url: "https://www.facebook.com/tr/?id=8117817644981394&ev=Buy", vendors: vendors)?.vendorName,
            "FB"
        )
        XCTAssertNil(VendorMatcher.match(url: "https://www.facebook.com/tr/?id=999", vendors: vendors))
    }

    func testNoMatchReturnsNil() {
        XCTAssertNil(VendorMatcher.match(url: "https://unrelated.test/x", vendors: [vendor("FB", ["facebook.com/tr"])]))
    }

    func testCompiledMatchStringOrder() {
        let compiled = CompiledVendorMatcher(vendors: [
            vendor("A", ["a.test"]),
            vendor("B", ["https://b.test"]),
        ])
        XCTAssertEqual(compiled.matchStrings, ["/a.test", "//b.test", ".a.test", "./b.test"])
    }
}
