//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class ExtractionTests: XCTestCase {

    private func obj(_ pairs: [(String, JSONValue)]) -> JSONValue {
        .object(JSONObject(pairs))
    }

    // MARK: - splitKeys (getKeys port)

    func testSplitPlainDotPath() {
        XCTAssertEqual(Extraction.splitKeys("a.b.c"), ["a", "b", "c"])
        XCTAssertEqual(Extraction.splitKeys("single"), ["single"])
    }

    func testSplitQuotedSegmentSpanningDots() {
        XCTAssertEqual(Extraction.splitKeys("a.b.'c.d'"), ["a", "b", "c.d"])
        XCTAssertEqual(Extraction.splitKeys("a.\"b.c\".d"), ["a", "b.c", "d"])
    }

    func testSplitQuotedSegmentWithinOnePart() {
        XCTAssertEqual(Extraction.splitKeys("a.'b'.c"), ["a", "b", "c"])
    }

    func testSplitUnterminatedQuoteKeepsRawSegment() {
        XCTAssertEqual(Extraction.splitKeys("a.'b.c"), ["a", "'b", "c"])
    }

    // MARK: - dotAccess

    func testDotAccessNested() {
        let data = obj([("a", obj([("b", .string("x"))]))])
        XCTAssertEqual(Extraction.dotAccess(data, path: "a.b"), .string("x"))
    }

    func testDotAccessMissingIsNil() {
        let data = obj([("a", .string("x"))])
        XCTAssertNil(Extraction.dotAccess(data, path: "a.b"))
        XCTAssertNil(Extraction.dotAccess(data, path: "zz"))
    }

    func testDotAccessJSONNullIsMissing() {
        let data = obj([("a", .null)])
        XCTAssertNil(Extraction.dotAccess(data, path: "a"))
    }

    func testDotAccessArrayFansOut() {
        let data = obj([
            ("items", .array([
                obj([("name", .string("a"))]),
                obj([("name", .string("b"))]),
                obj([("other", .string("c"))]),
            ])),
        ])
        XCTAssertEqual(
            Extraction.dotAccess(data, path: "items.name"),
            .array([.string("a"), .string("b")])
        )
    }

    func testDotAccessArrayWithNoMatchesIsNil() {
        let data = obj([("items", .array([obj([("x", .string("1"))])]))])
        XCTAssertNil(Extraction.dotAccess(data, path: "items.name"))
    }

    // MARK: - multiply

    func testMultiplyConcatenatesScalars() {
        XCTAssertEqual(Extraction.multiply([.string("a"), .string("b"), .string("c")]), ["abc"])
    }

    func testMultiplyFansOutArrays() {
        let out = Extraction.multiply([
            .string("a"),
            .array([.string("1"), .string("2")]),
            .string("b"),
            .array([.string("@"), .string("#")]),
        ])
        XCTAssertEqual(Set(out), Set(["a1b@", "a2b@", "a1b#", "a2b#"]))
        XCTAssertEqual(out.count, 4)
    }

    // MARK: - fillTemplate (fillParamsFromData port)

    func testPlainPathWithoutBracesIsDotAccess() {
        let data = obj([("ev", .string("Purchase"))])
        XCTAssertEqual(Extraction.fillTemplate("ev", data: data), .string("Purchase"))
    }

    func testSimpleInterpolation() {
        let data = obj([("id", .string("881")), ("ev", .string("Lead"))])
        XCTAssertEqual(Extraction.fillTemplate("{{id}}-{{ev}}", data: data), .string("881-Lead"))
    }

    func testMissingValueYieldsEmptyString() {
        let data = obj([("id", .string("881"))])
        XCTAssertEqual(Extraction.fillTemplate("{{nope}}", data: data), .string(""))
        XCTAssertEqual(Extraction.fillTemplate("{{id}}-{{nope}}", data: data), .string("881-"))
    }

    func testArrayValueFansOutIntoMultipleEvents() {
        let data = obj([
            ("products", .array([
                obj([("sku", .string("A"))]),
                obj([("sku", .string("B"))]),
            ])),
        ])
        XCTAssertEqual(
            Extraction.fillTemplate("buy-{{products.sku}}", data: data),
            .array([.string("buy-A"), .string("buy-B")])
        )
    }

    func testArrayFanOutDropsNullsLikeJavaScript() {
        // Probe case from the adversarial review: nulls inside fanned arrays
        // must never interpolate as the literal string "null".
        let data = obj([
            ("a", .array([
                obj([("b", .array([.string("x"), .null]))]),
            ])),
        ])
        XCTAssertEqual(Extraction.fillTemplate("ev-{{a.b}}", data: data), .string("ev-x"))
        // All null values leave the path missing entirely.
        let allNull = obj([("a", .array([obj([("b", .array([.null, .null]))])]))])
        XCTAssertNil(Extraction.dotAccess(allNull, path: "a.b"))
        XCTAssertEqual(Extraction.fillTemplate("ev-{{a.b}}", data: allNull), .string("ev-"))
    }

    func testNumberValueConcatenatesLikeJavaScript() {
        let data = obj([("n", .int(5)), ("d", .double(2.5))])
        XCTAssertEqual(Extraction.fillTemplate("{{n}}-{{d}}", data: data), .string("5-2.5"))
    }

    // MARK: - regex templating (mirrors the reference tests)

    private let tw = JSONObject([
        ("events", .string("[[\"pageview\",{\"currency\":\"GBP\"}]]")),
        ("txn_id", .string("o2g3p")),
    ])

    func testRegexExtractsFirstMatch() {
        XCTAssertEqual(
            Extraction.fillTemplate("{{regex::\\w+::events}}", data: .object(tw)),
            .string("pageview")
        )
    }

    func testRegexPrefersCaptureGroupOne() {
        XCTAssertEqual(
            Extraction.fillTemplate("{{regex::\"([a-z]+)\"::events}}", data: .object(tw)),
            .string("pageview")
        )
    }

    func testRegexMixesWithStaticTextAndPlainParams() {
        XCTAssertEqual(
            Extraction.fillTemplate("{{txn_id}}-{{regex::\\w+::events}}", data: .object(tw)),
            .string("o2g3p-pageview")
        )
    }

    func testRegexDropsSilentlyOnNoMatch() {
        XCTAssertEqual(Extraction.fillTemplate("{{regex::zzz9::events}}", data: .object(tw)), .string(""))
        XCTAssertEqual(
            Extraction.fillTemplate("{{txn_id}}-{{regex::zzz9::events}}", data: .object(tw)),
            .string("o2g3p-")
        )
    }

    func testRegexSurvivesInvalidPattern() {
        XCTAssertEqual(Extraction.fillTemplate("{{regex::([::events}}", data: .object(tw)), .string(""))
    }

    func testRegexCapsInputAtFourKilobytes() {
        let long = JSONObject([("blob", .string(String(repeating: "x", count: 10000) + "needle"))])
        XCTAssertEqual(Extraction.fillTemplate("{{regex::needle::blob}}", data: .object(long)), .string(""))
    }

    func testUnknownTemplateFunctionKeepsRawValue() {
        let data = obj([("v", .string("keep"))])
        XCTAssertEqual(Extraction.fillTemplate("{{upper::x::v}}", data: data), .string("keep"))
    }

    // MARK: - loose falsiness

    func testLooseFalsiness() {
        XCTAssertTrue(Extraction.isLooselyFalse(nil))
        XCTAssertTrue(Extraction.isLooselyFalse(.null))
        XCTAssertTrue(Extraction.isLooselyFalse(.string("")))
        XCTAssertTrue(Extraction.isLooselyFalse(.string("0")))
        XCTAssertTrue(Extraction.isLooselyFalse(.bool(false)))
        XCTAssertTrue(Extraction.isLooselyFalse(.int(0)))
        XCTAssertFalse(Extraction.isLooselyFalse(.string("Purchase")))
        XCTAssertFalse(Extraction.isLooselyFalse(.string("false")))
        XCTAssertFalse(Extraction.isLooselyFalse(.int(1)))
    }
}
