//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class SessionConsentTests: XCTestCase {

    private var defaults: UserDefaults = .standard
    private var suiteName = ""

    override func setUp() {
        super.setUp()
        suiteName = "monita-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    // MARK: - Session rotation

    func testSessionIdStableWithinThirtyMinutes() {
        var now = 1_000_000.0
        let session = SessionManager(defaults: defaults, now: { now })
        let first = session.currentSessionId()
        now += 900 // 15 minutes
        XCTAssertEqual(session.currentSessionId(), first)
        now += 1700 // another ~28 minutes, but activity refreshed the clock
        XCTAssertEqual(session.currentSessionId(), first)
    }

    func testSessionRotatesAfterThirtyMinutesOfInactivity() {
        var now = 1_000_000.0
        let session = SessionManager(defaults: defaults, now: { now })
        let first = session.currentSessionId()
        now += 1801
        let second = session.currentSessionId()
        XCTAssertNotEqual(first, second)
    }

    func testSessionPersistsAcrossRelaunchWithinWindow() {
        var now = 1_000_000.0
        let first = SessionManager(defaults: defaults, now: { now }).currentSessionId()
        now += 60
        let relaunched = SessionManager(defaults: defaults, now: { now }).currentSessionId()
        XCTAssertEqual(first, relaunched)
    }

    func testHostSessionOverrideWins() {
        let session = SessionManager(defaults: defaults, now: { 1 })
        session.overrideId = "host-session"
        XCTAssertEqual(session.currentSessionId(), "host-session")
        session.overrideId = nil
        XCTAssertNotEqual(session.currentSessionId(), "host-session")
    }

    // MARK: - Visitor id

    func testVisitorIdIsStablePerInstall() {
        let first = VisitorIdentity.visitorId(defaults: defaults)
        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(VisitorIdentity.visitorId(defaults: defaults), first)
    }

    // MARK: - Consent auto read

    func testConsentReadsIABStringsInPriorityOrder() {
        let consent = ConsentManager(defaults: defaults)
        XCTAssertNil(consent.currentConsent())

        defaults.set("1YNN", forKey: "IABUSPrivacy_String")
        XCTAssertEqual(consent.currentConsent(), "1YNN")

        defaults.set("DBABMA~GPPSTRING", forKey: "IABGPP_HDR_GppString")
        XCTAssertEqual(consent.currentConsent(), "DBABMA~GPPSTRING")

        defaults.set("CPXxTCFSTRING", forKey: "IABTCF_TCString")
        XCTAssertEqual(consent.currentConsent(), "CPXxTCFSTRING")
    }

    func testConsentOverrideWinsOverAutoDetection() {
        defaults.set("CPXxTCFSTRING", forKey: "IABTCF_TCString")
        let consent = ConsentManager(defaults: defaults)
        consent.override = "custom-consent"
        XCTAssertEqual(consent.currentConsent(), "custom-consent")
        consent.override = nil
        XCTAssertEqual(consent.currentConsent(), "CPXxTCFSTRING")
    }

    func testConsentProviderUsedWhenNoOverride() {
        let consent = ConsentManager(defaults: defaults)
        consent.provider = { "provider-consent" }
        XCTAssertEqual(consent.currentConsent(), "provider-consent")
        consent.override = "explicit"
        XCTAssertEqual(consent.currentConsent(), "explicit")
    }

    func testHasTCFString() {
        let consent = ConsentManager(defaults: defaults)
        XCTAssertFalse(consent.hasTCFString)
        defaults.set("CPXx", forKey: "IABTCF_TCString")
        XCTAssertTrue(consent.hasTCFString)
    }
}

final class CircuitBreakerTests: XCTestCase {

    func testAllowsUpToLimitPerWindow() {
        var breaker = CircuitBreaker(now: 0)
        for i in 1...100 {
            XCTAssertTrue(breaker.allow(now: 0.01 * Double(i)))
        }
        XCTAssertFalse(breaker.allow(now: 1.5))
        XCTAssertTrue(breaker.tripped)
    }

    func testWindowResetsWhenSpreadOut() {
        var breaker = CircuitBreaker(now: 0)
        var now = 0.0
        for _ in 0..<500 {
            now += 7 // beyond the 6 second window each time
            XCTAssertTrue(breaker.allow(now: now))
        }
        XCTAssertFalse(breaker.tripped)
    }

    func testTripIsPermanentForProcessLifetime() {
        var breaker = CircuitBreaker(now: 0)
        for i in 0...100 {
            _ = breaker.allow(now: Double(i) * 0.001)
        }
        XCTAssertTrue(breaker.tripped)
        XCTAssertFalse(breaker.allow(now: 10_000))
    }
}
