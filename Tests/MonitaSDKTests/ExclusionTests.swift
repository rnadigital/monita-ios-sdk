//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class ExclusionTests: XCTestCase {

    private func sample() -> JSONObject {
        JSONObject([
            ("email", .string("a@b.test")),
            ("user", .object(JSONObject([
                ("name", .string("A")),
                ("token", .string("secret")),
            ]))),
            ("cd_1", .string("x")),
            ("cd_2", .string("y")),
            ("keep", .string("z")),
        ])
    }

    func testDeleteTopLevelKey() {
        var data = sample()
        Exclusion.deleteProperty(&data, path: "email")
        XCTAssertFalse(data.contains("email"))
        XCTAssertTrue(data.contains("keep"))
    }

    func testDeleteNestedDotPath() {
        var data = sample()
        Exclusion.deleteProperty(&data, path: "user.token")
        XCTAssertEqual(data["user"], .object(JSONObject([("name", .string("A"))])))
    }

    func testRegexSegmentDeletesMatchingKeys() {
        var data = sample()
        Exclusion.deleteProperty(&data, path: "/^cd_/")
        XCTAssertFalse(data.contains("cd_1"))
        XCTAssertFalse(data.contains("cd_2"))
        XCTAssertTrue(data.contains("keep"))
    }

    func testRegexSegmentInNestedPath() {
        var data = JSONObject([
            ("u1", .object(JSONObject([("pii", .string("a")), ("ok", .string("b"))]))),
            ("u2", .object(JSONObject([("pii", .string("c"))]))),
        ])
        Exclusion.deleteProperty(&data, path: "/^u/.pii")
        XCTAssertEqual(data["u1"], .object(JSONObject([("ok", .string("b"))])))
        XCTAssertEqual(data["u2"], .object(JSONObject()))
    }

    func testMissingPathIsNoOp() {
        var data = sample()
        Exclusion.deleteProperty(&data, path: "nope.deeper")
        XCTAssertEqual(data, sample())
    }

    func testBadRegexLeavesObjectUntouched() {
        var data = sample()
        Exclusion.deleteProperty(&data, path: "/([/")
        XCTAssertEqual(data, sample())
    }

    func testParamCapKeepsFirstHundredKeys() {
        var data = JSONObject()
        for i in 0..<150 {
            data["k\(i)"] = .string("\(i)")
        }
        let filtered = EventBuilder.filterData(data, excludedPaths: [])
        XCTAssertEqual(filtered.count, 100)
        XCTAssertTrue(filtered.contains("k0"))
        XCTAssertTrue(filtered.contains("k99"))
        XCTAssertFalse(filtered.contains("k100"))
    }

    func testFilterDataAppliesExclusions() {
        let filtered = EventBuilder.filterData(sample(), excludedPaths: ["email", "user.token"])
        XCTAssertFalse(filtered.contains("email"))
        XCTAssertEqual(filtered["user"], .object(JSONObject([("name", .string("A"))])))
    }
}
