//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class ConfigDecodeTests: XCTestCase {

    func testDecodesLegacyMisspelledWireKeys() {
        let json = """
        {
          "monitoringVersion": "46",
          "vendors": [
            {
              "vendorName": "Facebook (Meta Pixel)",
              "urlPatternMatches": ["facebook.com/tr/?id=8117817644981394"],
              "eventParamter": "{{id}}-{{ev}}",
              "execludeParameters": ["sw", "user.email"],
              "filters": [{"key": "ev", "op": "eq", "val": ["Purchase"]}]
            }
          ]
        }
        """
        let config = RemoteConfig.decode(data: Data(json.utf8))
        XCTAssertEqual(config?.monitoringVersion, "46")
        let vendor = config?.vendors.first
        XCTAssertEqual(vendor?.vendorName, "Facebook (Meta Pixel)")
        XCTAssertEqual(vendor?.urlPatternMatches, ["facebook.com/tr/?id=8117817644981394"])
        XCTAssertEqual(vendor?.eventParameter, "{{id}}-{{ev}}")
        XCTAssertEqual(vendor?.excludeParameters, ["sw", "user.email"])
        XCTAssertEqual(vendor?.filters, [FilterRule(key: "ev", op: "eq", val: ["Purchase"])])
    }

    func testUnknownFieldsAreIgnoredNeverFatal() {
        let json = """
        {
          "monitoringVersion": "3",
          "someFutureFlag": {"nested": [1, 2, 3]},
          "vendors": [
            {"vendorName": "X", "urlPatternMatches": ["x.test"], "surprise": true}
          ]
        }
        """
        let config = RemoteConfig.decode(data: Data(json.utf8))
        XCTAssertEqual(config?.monitoringVersion, "3")
        XCTAssertEqual(config?.vendors.count, 1)
    }

    func testFilterGroupsDecode() {
        let json = """
        {
          "monitoringVersion": "1",
          "vendors": [
            {
              "vendorName": "X",
              "urlPatternMatches": ["x.test"],
              "filterGroups": [
                {"op": "any", "filters": [{"key": "ev", "op": "eq", "val": ["A"]}, {"key": "ev", "op": "eq", "val": ["B"]}]},
                {"op": "all", "filters": [{"key": "cur", "op": "eq", "val": ["AUD"]}]},
                {"op": "weird", "filters": []}
              ]
            }
          ]
        }
        """
        let vendor = RemoteConfig.decode(data: Data(json.utf8))?.vendors.first
        XCTAssertEqual(vendor?.filterGroups.count, 3)
        XCTAssertEqual(vendor?.filterGroups[0].op, "any")
        XCTAssertEqual(vendor?.filterGroups[0].filters.count, 2)
        XCTAssertEqual(vendor?.filterGroups[1].op, "all")
        // Unknown group operators degrade to "all".
        XCTAssertEqual(vendor?.filterGroups[2].op, "all")
    }

    func testNumericMonitoringVersionBecomesString() {
        let config = RemoteConfig.decode(data: Data("{\"monitoringVersion\": 46, \"vendors\": []}".utf8))
        XCTAssertEqual(config?.monitoringVersion, "46")
    }

    func testSingleStringValNormalizesToArray() {
        let json = """
        {"monitoringVersion": "1", "vendors": [{"vendorName": "X", "urlPatternMatches": ["x.test"],
          "filters": [{"key": "k", "op": "eq", "val": "single"}]}]}
        """
        let vendor = RemoteConfig.decode(data: Data(json.utf8))?.vendors.first
        XCTAssertEqual(vendor?.filters.first?.val, ["single"])
    }

    func testMonitoringStatusDecodes() {
        let paused = RemoteConfig.decode(data: Data("{\"monitoringVersion\": \"1\", \"monitoringStatus\": \"paused\", \"vendors\": []}".utf8))
        XCTAssertEqual(paused?.monitoringStatus, "paused")
        let active = RemoteConfig.decode(data: Data("{\"monitoringVersion\": \"1\", \"vendors\": []}".utf8))
        XCTAssertNil(active?.monitoringStatus)
    }

    func testAllowManualMonitoring() {
        let on = RemoteConfig.decode(data: Data("{\"monitoringVersion\": \"1\", \"allowManualMonitoring\": true, \"vendors\": []}".utf8))
        XCTAssertEqual(on?.allowManualMonitoring, true)
        let off = RemoteConfig.decode(data: Data("{\"monitoringVersion\": \"1\", \"vendors\": []}".utf8))
        XCTAssertEqual(off?.allowManualMonitoring, false)
    }

    func testGarbageInputIsNilNotFatal() {
        XCTAssertNil(RemoteConfig.decode(data: Data("not json".utf8)))
        XCTAssertNil(RemoteConfig.decode(data: Data("[1,2,3]".utf8)))
    }
}
