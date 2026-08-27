//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class BodyParserTests: XCTestCase {

    private func parse(_ url: String, body: String? = nil, hint: String? = nil) -> JSONObject? {
        BodyParser.parse(url: url, body: body.map { Data($0.utf8) }, contentTypeHint: hint)
    }

    // MARK: - URL parameters

    func testQueryParameters() {
        let data = parse("https://x.test/tr?id=812&ev=Purchase")
        XCTAssertEqual(data?["id"], .string("812"))
        XCTAssertEqual(data?["ev"], .string("Purchase"))
    }

    func testQueryParametersDecodePercentEscapesAndPlus() {
        let data = parse("https://x.test/tr?msg=hello%20world&name=a+b")
        XCTAssertEqual(data?["msg"], .string("hello world"))
        XCTAssertEqual(data?["name"], .string("a b"))
    }

    func testDoublyEncodedQueryValueDecodesFully() {
        // The reference decodes each query value a second time.
        let data = parse("https://x.test/tr?u=https%253A%252F%252Fa.test")
        XCTAssertEqual(data?["u"], .string("https://a.test"))
    }

    func testLegacySemicolonQueryParameters() {
        let data = parse("https://x.test/tr?a=1;b=2")
        XCTAssertEqual(data?["a"], .string("1"))
        XCTAssertEqual(data?["b"], .string("2"))
    }

    func testMatrixPathParameters() {
        let data = parse("https://x.test/b/ss/rsid/1/JS-2.22.0;a=5;b=6")
        XCTAssertEqual(data?["a"], .string("5"))
        XCTAssertEqual(data?["b"], .string("6"))
    }

    func testInvalidURLReturnsNil() {
        XCTAssertNil(parse("not a url at all"))
    }

    // MARK: - Bodies

    func testJSONObjectBodyMergesKeys() {
        let data = parse("https://x.test/collect", body: "{\"event\":\"buy\",\"value\":9.99,\"flag\":true}")
        XCTAssertEqual(data?["event"], .string("buy"))
        XCTAssertEqual(data?["value"], .double(9.99))
        XCTAssertEqual(data?["flag"], .bool(true))
    }

    func testJSONArrayBodyUsesIndexKeys() {
        let data = parse("https://x.test/collect", body: "[{\"a\":\"1\"},\"plain\",7]")
        XCTAssertEqual(data?["0"], .object(JSONObject([("a", .string("1"))])))
        XCTAssertEqual(data?["1"], .string("plain"))
        XCTAssertEqual(data?["2"], .int(7))
    }

    func testFormURLEncodedBody() {
        let data = parse("https://x.test/collect", body: "ev=Lead&cur=USD&msg=a%20b")
        XCTAssertEqual(data?["ev"], .string("Lead"))
        XCTAssertEqual(data?["cur"], .string("USD"))
        XCTAssertEqual(data?["msg"], .string("a b"))
    }

    func testSemicolonPairBody() {
        let data = parse("https://x.test/collect", body: "a=1;b=2;c=3")
        XCTAssertEqual(data?["a"], .string("1"))
        XCTAssertEqual(data?["c"], .string("3"))
    }

    func testSingleKeyValueBody() {
        let data = parse("https://x.test/collect", body: "ev=Purchase")
        XCTAssertEqual(data?["ev"], .string("Purchase"))
    }

    func testPlainTextBodyBecomesValue() {
        let data = parse("https://x.test/collect", body: "just some text")
        XCTAssertEqual(data?["value"], .string("just some text"))
    }

    func testURLAndBodyParametersMergeInOrder() {
        let data = parse("https://x.test/tr?id=1", body: "{\"ev\":\"buy\"}")
        XCTAssertEqual(data?.keys, ["id", "ev"])
    }

    func testBinaryBodyContributesNothing() {
        var binary = Data([0xFF, 0xFE, 0x00, 0x81, 0xC0])
        binary.append(Data(repeating: 0x92, count: 64))
        let data = BodyParser.parse(url: "https://x.test/tr?id=1", body: binary, contentTypeHint: "application/x-protobuf")
        XCTAssertEqual(data?.keys, ["id"])
    }

    func testOversizedBodyContributesURLParamsOnly() {
        let big = Data(repeating: UInt8(ascii: "a"), count: BodyParser.bodyReadCap + 1)
        let data = BodyParser.parse(url: "https://x.test/tr?id=1", body: big, contentTypeHint: nil)
        XCTAssertEqual(data?.keys, ["id"])
    }

    func testJSONHintForcesJSONParse() {
        let data = parse("https://x.test/collect", body: "{\"a\":\"1\"}", hint: "application/json")
        XCTAssertEqual(data?["a"], .string("1"))
    }
}
