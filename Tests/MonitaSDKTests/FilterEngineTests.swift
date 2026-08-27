//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class FilterEngineTests: XCTestCase {

    private let data = JSONValue.object(JSONObject([
        ("ev", .string("Purchase")),
        ("currency", .string("AUD")),
        ("id", .string("881")),
        ("empty", .string("")),
        ("amount", .double(9.99)),
    ]))

    private func rule(_ key: String, _ op: String?, _ val: [String]? = nil) -> FilterRule {
        FilterRule(key: key, op: op, val: val)
    }

    // MARK: - Flat list (legacy AND)

    func testEqExactMatch() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "eq", ["Purchase"])]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "eq", ["Lead"])]))
    }

    func testEqValArrayIsOr() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "eq", ["Lead", "Purchase"])]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "eq", ["Lead", "View"])]))
    }

    func testEqComparesNumbersLoosely() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("amount", "eq", ["9.99"])]))
    }

    func testFlatListIsAndOfAllRules() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [
            rule("ev", "eq", ["Purchase"]),
            rule("currency", "eq", ["AUD"]),
        ]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [
            rule("ev", "eq", ["Purchase"]),
            rule("currency", "eq", ["USD"]),
        ]))
    }

    func testNe() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "ne", ["Lead"])]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "ne", ["Purchase"])]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "ne", ["Lead", "Purchase"])]))
    }

    func testContainsIsSubstringNotEquality() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "contains", ["urch"])]))
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "contains", ["Purchase"])]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "contains", ["lead"])]))
        // Non string values never match contains.
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("amount", "contains", ["9"])]))
    }

    func testBlank() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("empty", "blank")]))
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("missing", "blank")]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "blank")]))
    }

    func testNotBlank() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "not_blank")]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("empty", "not_blank")]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("missing", "not_blank")]))
    }

    func testExistAndNotExist() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("empty", "exist")]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("missing", "exist")]))
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("missing", "not_exist")]))
        XCTAssertFalse(FilterEngine.passes(data, filters: [rule("ev", "not_exist")]))
    }

    func testUnknownOperatorPasses() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", "regex_match", ["x"])]))
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("ev", nil)]))
    }

    func testFilterKeySupportsTemplates() {
        XCTAssertTrue(FilterEngine.passes(data, filters: [rule("{{ev}}-{{currency}}", "eq", ["Purchase-AUD"])]))
    }

    func testEmptyFilterListPasses() {
        XCTAssertTrue(FilterEngine.passes(data, filters: []))
    }

    // MARK: - Filter groups (v2)

    private func group(_ op: String, _ filters: [FilterRule]) -> FilterGroup {
        FilterGroup(op: op, filters: filters)
    }

    func testGroupsAreOred() {
        // (ev=Lead AND currency=AUD) OR (ev=Purchase) passes via the second group.
        XCTAssertTrue(FilterEngine.passes(data, groups: [
            group("all", [rule("ev", "eq", ["Lead"]), rule("currency", "eq", ["AUD"])]),
            group("all", [rule("ev", "eq", ["Purchase"])]),
        ]))
    }

    func testAnyGroupNeedsOneMatch() {
        XCTAssertTrue(FilterEngine.passes(data, groups: [
            group("any", [rule("ev", "eq", ["Lead"]), rule("currency", "eq", ["AUD"])]),
        ]))
    }

    func testNoGroupSatisfiedFails() {
        XCTAssertFalse(FilterEngine.passes(data, groups: [
            group("all", [rule("ev", "eq", ["Lead"])]),
            group("any", [rule("currency", "eq", ["USD"]), rule("id", "eq", ["nope"])]),
        ]))
    }

    func testEmptyGroupsListPassesEverything() {
        XCTAssertTrue(FilterEngine.passes(data, groups: []))
    }

    func testGroupWithZeroConditionsIsSkippedNotAutoPass() {
        XCTAssertFalse(FilterEngine.passes(data, groups: [
            group("all", []),
            group("all", [rule("ev", "eq", ["Lead"])]),
        ]))
    }
}
