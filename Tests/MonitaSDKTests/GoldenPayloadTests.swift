//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

/// Wire compatibility guard: constructs a known capture and asserts the exact
/// JSON keys and envelope shape against fixtures derived from the reference
/// JavaScript SDK output. Renaming any key silently breaks live customers.
final class GoldenPayloadTests: XCTestCase {

    private func fixture(_ name: String) throws -> JSONValue {
        let bundle = Bundle.module
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
              let data = try? Data(contentsOf: url),
              let parsed = JSONParser.parse(data) else {
            throw XCTSkip("fixture \(name) missing")
        }
        return parsed
    }

    private var vendor: VendorConfig {
        VendorConfig(
            vendorName: "Facebook (Meta Pixel)",
            urlPatternMatches: ["facebook.com/tr"],
            eventParameter: "{{ev}}",
            excludeParameters: ["value"]
        )
    }

    private var context: SharedContext {
        SharedContext(
            token: "dom_goldentoken123456789012",
            mv: "2.0.0",
            sv: "46",
            u: "app://com.example.shop/Checkout",
            p: "Checkout",
            vid: "11111111-2222-4333-8444-555555555555",
            sid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            doValue: "com.example.shop",
            rl: "ios 17.5",
            cn: "CPXxRfAPXxRfAAfKABENBUCsAP_AAH_AAAAAJNNf",
            cid: "customer-42"
        )
    }

    private func buildPayload(url: String, body: String?, method: String, tm: Double) throws -> JSONObject {
        guard var data = BodyParser.parse(
            url: url,
            body: body.map { Data($0.utf8) },
            contentTypeHint: body == nil ? nil : "application/json"
        ) else {
            throw XCTSkip("URL failed to parse")
        }
        data["__mon_url"] = .string(url)
        data["__mon_host"] = .string("www.facebook.com")
        data["__mon_method"] = .string(method)
        data["vendorName"] = .string(vendor.vendorName)
        let payloads = EventBuilder.buildPayloads(
            context: context,
            vendor: vendor,
            data: data,
            vu: url,
            method: method,
            tm: tm,
            status: "success"
        )
        XCTAssertEqual(payloads.count, 1)
        return payloads[0]
    }

    private func buildBothPayloads() throws -> [JSONObject] {
        let first = try buildPayload(
            url: "https://www.facebook.com/tr/?id=812&ev=Purchase",
            body: "{\"currency\":\"USD\",\"value\":9.99}",
            method: "POST",
            tm: 1724732400.5
        )
        let second = try buildPayload(
            url: "https://www.facebook.com/tr/?id=812&ev=AddToCart",
            body: nil,
            method: "GET",
            tm: 1724732401.25
        )
        return [first, second]
    }

    func testEnvelopeMatchesGoldenFixtureExactly() throws {
        let payloads = try buildBothPayloads()
        let splits = payloads.map { EventBuilder.split($0) }
        XCTAssertEqual(splits[0].shared, splits[1].shared, "shared context must be identical")
        let chunks = Batcher.chunks(shared: splits[0].shared, events: splits.map { $0.event })
        XCTAssertEqual(chunks.count, 1)
        guard let built = JSONParser.parse(chunks[0].0) else { return XCTFail("built envelope is not JSON") }
        let expected = try fixture("golden-envelope")
        XCTAssertEqual(built, expected)
    }

    func testSingleEventMatchesLegacyFlatGoldenFixture() throws {
        let payloads = try buildBothPayloads()
        let split = EventBuilder.split(payloads[0])
        let chunks = Batcher.chunks(shared: split.shared, events: [split.event])
        XCTAssertEqual(chunks.count, 1)
        guard let built = JSONParser.parse(chunks[0].0) else { return XCTFail("built payload is not JSON") }
        let expected = try fixture("golden-single")
        XCTAssertEqual(built, expected)
    }

    func testEnvelopeKeySetIsExact() throws {
        let payloads = try buildBothPayloads()
        let split = EventBuilder.split(payloads[0])
        XCTAssertEqual(
            split.shared.keys,
            ["t", "dm", "mv", "sv", "u", "p", "vid", "sid", "s", "do", "rl", "env", "et", "cn", "cid"]
        )
        XCTAssertEqual(
            split.event.keys,
            ["tm", "e", "vn", "st", "m", "vu", "dt", "np"]
        )
    }

    func testUnknownStatusOmitsSt() throws {
        guard var data = BodyParser.parse(url: "https://www.facebook.com/tr/?ev=X", body: nil, contentTypeHint: nil) else {
            return XCTFail("parse failed")
        }
        data["vendorName"] = .string(vendor.vendorName)
        let payloads = EventBuilder.buildPayloads(
            context: context, vendor: vendor, data: data,
            vu: "https://www.facebook.com/tr/?ev=X", method: "GET", tm: 1, status: nil
        )
        XCTAssertFalse(payloads[0].contains("st"))
    }

    func testMissingEventIsJSONNullNeverStringNull() throws {
        guard var data = BodyParser.parse(url: "https://www.facebook.com/tr/?id=1", body: nil, contentTypeHint: nil) else {
            return XCTFail("parse failed")
        }
        data["vendorName"] = .string(vendor.vendorName)
        let payloads = EventBuilder.buildPayloads(
            context: context, vendor: vendor, data: data,
            vu: "https://www.facebook.com/tr/?id=1", method: "GET", tm: 1, status: nil
        )
        XCTAssertEqual(payloads[0]["e"], JSONValue.null)
        XCTAssertTrue(JSONValue.object(payloads[0]).serialized().contains("\"e\":null"))
    }

    func testEnvironmentEventShape() {
        var snapshot = JSONObject()
        snapshot["sdks"] = .array([])
        snapshot["tcf"] = .bool(false)
        let payload = EventBuilder.buildEnvironmentPayload(context: context, snapshot: snapshot, tm: 1724732402)
        XCTAssertEqual(payload["e"], .string("monita_env"))
        XCTAssertEqual(payload["vn"], .string("Monita"))
        XCTAssertEqual(payload["dt"], .array([.object(snapshot)]))
        // The environment event carries no request fields.
        XCTAssertFalse(payload.contains("vu"))
        XCTAssertFalse(payload.contains("m"))
        XCTAssertFalse(payload.contains("st"))
        XCTAssertFalse(payload.contains("np"))
    }
}
