//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

/// End to end pipeline tests: configure with a mock transport, capture, and
/// inspect what reaches the collect endpoint.
final class EngineIntegrationTests: XCTestCase {

    private var directory: URL = FileManager.default.temporaryDirectory
    private var defaults: UserDefaults = .standard
    private var suiteName = ""
    private var transport = MockTransport()
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = 1_724_732_400.0
        var now: Double {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        func advance(_ by: Double) {
            lock.lock()
            value += by
            lock.unlock()
        }
    }
    private var clock = Clock()

    override func setUp() {
        super.setUp()
        suiteName = "monita-engine-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("monita-engine-\(UUID().uuidString)", isDirectory: true)
        transport = MockTransport()
        clock = Clock()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private var standardConfigJSON: String {
        """
        {
          "monitoringVersion": "46",
          "allowManualMonitoring": true,
          "vendors": [
            {
              "vendorName": "Facebook (Meta Pixel)",
              "urlPatternMatches": ["facebook.com/tr"],
              "eventParamter": "{{ev}}",
              "execludeParameters": ["secret"],
              "filters": [{"key": "ev", "op": "not_blank"}]
            }
          ]
        }
        """
    }

    private func makeEngine(environmentDelay: Double = 3600) -> MonitaEngine {
        let deps = MonitaEngine.Dependencies(
            defaults: defaults,
            storageDirectory: directory,
            transport: transport,
            now: { [clock] in clock.now },
            bundleId: "com.example.shop",
            osVersion: "ios 17.5",
            installInterceptor: false,
            observeAppLifecycle: false,
            startReachability: false,
            environmentDelaySeconds: environmentDelay
        )
        return MonitaEngine(dependencies: deps)
    }

    private func configureAndWait(_ engine: MonitaEngine, token: String = "dom_testtoken1234567890123") {
        engine.configure(MonitaConfiguration(token: token))
        waitUntil { engine.remoteConfigForTesting != nil || self.transport.requests(matching: "custom-config").count > 0 }
        engine.syncForTesting()
        engine.syncForTesting()
    }

    private func waitUntil(timeout: TimeInterval = 5, _ check: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !check(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    private func collectBodies() -> [JSONValue] {
        transport.requests(matching: "collect.monita.ai").compactMap { seen in
            seen.body.flatMap { JSONParser.parse($0) }
        }
    }

    func testCaptureFlowsThroughPipelineToCollect() {
        transport.route("custom-config") { .init(status: 200, headers: ["etag": "\"v46\""], body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        XCTAssertEqual(engine.remoteConfigForTesting?.monitoringVersion, "46")

        engine.captureForTesting(
            url: "https://www.facebook.com/tr?ev=Purchase&secret=hide-me&id=7",
            method: "POST",
            body: nil,
            status: 200
        )
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        let bodies = collectBodies()
        XCTAssertEqual(bodies.count, 1)
        guard case .object(let payload) = bodies[0] else { return XCTFail("bad payload") }
        XCTAssertEqual(payload["t"], .string("dom_testtoken1234567890123"))
        XCTAssertEqual(payload["dm"], .string("app"))
        XCTAssertEqual(payload["s"], .string("ios-sdk"))
        XCTAssertEqual(payload["sv"], .string("46"))
        XCTAssertEqual(payload["e"], .string("Purchase"))
        XCTAssertEqual(payload["vn"], .string("Facebook (Meta Pixel)"))
        XCTAssertEqual(payload["st"], .string("success"))
        XCTAssertEqual(payload["u"], .string("app://com.example.shop"))
        XCTAssertEqual(payload["p"], .string(""))
        XCTAssertEqual(payload["do"], .string("com.example.shop"))
        XCTAssertEqual(payload["rl"], .string("ios 17.5"))
        // Excluded parameter never rides.
        guard case .array(let dt)? = payload["dt"], case .object(let data) = dt[0] else {
            return XCTFail("dt missing")
        }
        XCTAssertFalse(data.contains("secret"))
        XCTAssertEqual(data["ev"], .string("Purchase"))
        XCTAssertEqual(data["vendorName"], .string("Facebook (Meta Pixel)"))
        // Delivered record is deleted after the 2xx.
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
    }

    func testNonMatchingAndFilteredRequestsAreDropped() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        // Unrelated host: no vendor match.
        engine.captureForTesting(url: "https://api.example.com/v1/things", method: "GET", body: nil, status: 200)
        // Matching vendor but blank event: not_blank filter drops it.
        engine.captureForTesting(url: "https://www.facebook.com/tr?other=1", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertEqual(collectBodies().count, 0)
    }

    func testScreenAndCustomerIdAndConsentRideTheEnvelope() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        defaults.set("CPXxTCF", forKey: "IABTCF_TCString")
        let engine = makeEngine()
        configureAndWait(engine)
        engine.setScreen("Checkout")
        engine.setCustomerId("customer-42")
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Lead", method: "GET", body: nil, status: 200)
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        guard case .object(let payload)? = collectBodies().first else { return XCTFail("no payload") }
        XCTAssertEqual(payload["u"], .string("app://com.example.shop/Checkout"))
        XCTAssertEqual(payload["p"], .string("Checkout"))
        XCTAssertEqual(payload["cid"], .string("customer-42"))
        XCTAssertEqual(payload["cn"], .string("CPXxTCF"))
    }

    func testPreConfigRingBufferReplaysOnceConfigArrives() {
        // Config is served only after a delay flag flips.
        let lock = NSLock()
        var serveConfig = false
        transport.route("custom-config") {
            lock.lock()
            defer { lock.unlock() }
            if serveConfig {
                return .init(status: 200, body: Data(self.standardConfigJSON.utf8))
            }
            return .init(status: nil)
        }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        engine.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        engine.syncForTesting()
        XCTAssertNil(engine.remoteConfigForTesting)

        // Launch time vendor traffic before any config exists.
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=AppLaunch", method: "GET", body: nil, status: 200)
        engine.syncForTesting()

        lock.lock(); serveConfig = true; lock.unlock()
        engine.refreshConfig()
        waitUntil { engine.remoteConfigForTesting != nil }
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        guard case .object(let payload)? = collectBodies().first else { return XCTFail("buffered capture lost") }
        XCTAssertEqual(payload["e"], .string("AppLaunch"))
    }

    func testKillSwitchPausedClearsQueueAndStopsCapture() {
        let lock = NSLock()
        var paused = false
        transport.route("custom-config") {
            lock.lock()
            defer { lock.unlock() }
            let json = paused
                ? "{\"monitoringVersion\": \"47\", \"monitoringStatus\": \"paused\", \"vendors\": []}"
                : self.standardConfigJSON
            return .init(status: 200, body: Data(json.utf8))
        }
        // Collect never succeeds so records stay queued.
        transport.route("collect.monita.ai") { .init(status: 500) }
        let engine = makeEngine()
        configureAndWait(engine)
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Buy", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, false)

        lock.lock(); paused = true; lock.unlock()
        engine.refreshConfig()
        waitUntil { engine.diskQueueForTesting?.isEmpty == true }
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
        XCTAssertNil(engine.remoteConfigForTesting)
        // Capture is off now.
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=After", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
    }

    func testKillSwitch404RequiresTwoConsecutiveResults() {
        let lock = NSLock()
        var gone = false
        transport.route("custom-config") {
            lock.lock()
            defer { lock.unlock() }
            if gone {
                return .init(status: 404)
            }
            return .init(status: 200, body: Data(self.standardConfigJSON.utf8))
        }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        XCTAssertNotNil(engine.remoteConfigForTesting)
        lock.lock(); gone = true; lock.unlock()

        // A lone 404 (CDN purge race) keeps the current config.
        engine.refreshConfig()
        engine.syncForTesting()
        engine.syncForTesting()
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        XCTAssertNotNil(engine.remoteConfigForTesting)

        // The second consecutive 404 confirms removal and wipes the cache.
        engine.refreshConfig()
        waitUntil { engine.remoteConfigForTesting == nil }
        XCTAssertNil(engine.remoteConfigForTesting)
        // Cached config file was wiped and the kill marker persisted: a fresh
        // engine starts with nothing.
        let second = makeEngine()
        second.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        second.syncForTesting()
        XCTAssertNil(second.remoteConfigForTesting)
    }

    func testPausedKillStateSurvivesColdStart() {
        let lock = NSLock()
        var paused = false
        transport.route("custom-config") {
            lock.lock()
            defer { lock.unlock() }
            let json = paused
                ? "{\"monitoringVersion\": \"47\", \"monitoringStatus\": \"paused\", \"vendors\": []}"
                : self.standardConfigJSON
            return .init(status: 200, body: Data(json.utf8))
        }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        lock.lock(); paused = true; lock.unlock()
        engine.refreshConfig()
        waitUntil { engine.remoteConfigForTesting == nil }

        // Cold start with the config endpoint unreachable: the persisted kill
        // marker must keep capture off even though the cached config file
        // still exists (paused keeps the cache).
        let offline = MockTransport()
        offline.route("custom-config") { .init(status: nil) }
        offline.route("collect.monita.ai") { .init(status: 204) }
        transport = offline
        let second = makeEngine()
        second.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        second.syncForTesting()
        XCTAssertNil(second.remoteConfigForTesting)
        second.captureForTesting(url: "https://www.facebook.com/tr?ev=WhilePaused", method: "GET", body: nil, status: 200)
        second.flush()
        second.syncForTesting()
        XCTAssertEqual(second.diskQueueForTesting?.isEmpty, true)
        XCTAssertTrue(offline.requests(matching: "collect.monita.ai").isEmpty)
    }

    func testColdStartUsesCachedConfigInstantly() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let first = makeEngine()
        configureAndWait(first)
        XCTAssertNotNil(first.remoteConfigForTesting)

        // Second launch: config endpoint now unreachable, cache still works.
        let offlineTransport = MockTransport()
        offlineTransport.route("custom-config") { .init(status: nil) }
        offlineTransport.route("collect.monita.ai") { .init(status: 204) }
        transport = offlineTransport
        let second = makeEngine()
        second.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        second.syncForTesting()
        XCTAssertEqual(second.remoteConfigForTesting?.monitoringVersion, "46")
    }

    func testManualSendRequiresAllowManualMonitoringAndKnownVendor() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        engine.send(vendor: "Facebook (Meta Pixel)", event: "ManualBuy", data: ["value": 12, "ev": "ManualBuy"])
        engine.send(vendor: "Unknown Vendor", event: "Nope", data: ["ev": "Nope"])
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        let bodies = collectBodies()
        XCTAssertEqual(bodies.count, 1)
        guard case .object(let payload) = bodies[0] else { return XCTFail("bad payload") }
        XCTAssertEqual(payload["e"], .string("ManualBuy"))
        XCTAssertEqual(payload["m"], .string("POST"))
        guard case .array(let dt)? = payload["dt"], case .object(let data) = dt[0] else {
            return XCTFail("dt missing")
        }
        XCTAssertEqual(data["event"], .string("ManualBuy"))
        XCTAssertEqual(data["value"], .int(12))
    }

    func testEventFilterGateDropsEvents() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        engine.setEventFilter { payload in
            (payload["e"] as? String) != "Blocked"
        }
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Blocked", method: "GET", body: nil, status: 200)
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Allowed", method: "GET", body: nil, status: 200)
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        guard case .object(let payload)? = collectBodies().first else { return XCTFail("no payload") }
        XCTAssertEqual(payload["e"], .string("Allowed"))
    }

    func testOptOutStopsCaptureAndClearsQueueUntilOptIn() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 500) }
        let engine = makeEngine()
        configureAndWait(engine)
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=One", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, false)
        engine.optOut()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Two", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
        engine.optIn()
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Three", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, false)
    }

    func testInternalEndpointsAreNeverCaptured() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        engine.captureForTesting(url: "https://collect.monita.ai/api/v1", method: "POST", body: nil, status: 204)
        engine.captureForTesting(url: "https://cdn.monita.ai/custom-config/dom_x.json", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
    }

    func testEnvironmentEventSendsOncePerSessionThroughEnvelope() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine(environmentDelay: 0.05)
        configureAndWait(engine)
        engine.flush()
        waitUntil { self.collectBodies().count >= 1 }
        engine.flush()
        engine.syncForTesting()
        let bodies = collectBodies()
        XCTAssertEqual(bodies.count, 1)
        guard case .object(let payload)? = bodies.first else { return XCTFail("no env event") }
        XCTAssertEqual(payload["e"], .string("monita_env"))
        XCTAssertEqual(payload["vn"], .string("Monita"))
        guard case .array(let dt)? = payload["dt"], case .object(let snapshot) = dt[0] else {
            return XCTFail("snapshot missing")
        }
        XCTAssertTrue(snapshot.contains("sdks"))
        XCTAssertTrue(snapshot.contains("cmp"))
        XCTAssertTrue(snapshot.contains("tcf"))
        XCTAssertTrue(snapshot.contains("os"))
        XCTAssertTrue(snapshot.contains("model"))
        XCTAssertEqual(snapshot["sdk"], .string("2.0.0"))
        XCTAssertTrue(snapshot.contains("att"))
    }

    func testRoutineFetchSendsIfNoneMatchAndNoCacheBuster() {
        transport.route("custom-config") { .init(status: 200, headers: ["etag": "\"abc\""], body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        let firstFetch = transport.requests(matching: "custom-config").first
        XCTAssertNil(firstFetch?.headers["if-none-match"])
        XCTAssertEqual(firstFetch?.url.contains("?v="), false)

        // Second launch reuses the stored ETag on its routine fetch.
        let second = makeEngine()
        second.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        second.syncForTesting()
        waitUntil { self.transport.requests(matching: "custom-config").count >= 2 }
        let routine = transport.requests(matching: "custom-config").last
        XCTAssertEqual(routine?.headers["if-none-match"], "\"abc\"")
        XCTAssertEqual(routine?.url.contains("?v="), false)

        // Explicit refresh adds the cache buster and skips If-None-Match.
        second.refreshConfig()
        waitUntil { self.transport.requests(matching: "custom-config").count >= 3 }
        let refresh = transport.requests(matching: "custom-config").last
        XCTAssertEqual(refresh?.url.contains("v=46"), true)
        XCTAssertNil(refresh?.headers["if-none-match"])
    }

    func testReactivationAfterPauseViaThreeOhFour() {
        enum Phase { case active, paused, notModified }
        let lock = NSLock()
        var phase = Phase.active
        func setPhase(_ p: Phase) { lock.lock(); phase = p; lock.unlock() }
        transport.route("custom-config") {
            lock.lock()
            defer { lock.unlock() }
            switch phase {
            case .active:
                return .init(status: 200, headers: ["etag": "\"v46etag\""], body: Data(self.standardConfigJSON.utf8))
            case .paused:
                return .init(status: 200, body: Data("{\"monitoringVersion\": \"46\", \"monitoringStatus\": \"paused\", \"vendors\": []}".utf8))
            case .notModified:
                return .init(status: 304)
            }
        }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        XCTAssertNotNil(engine.remoteConfigForTesting)

        // The property gets paused.
        setPhase(.paused)
        engine.queue.async { engine.fetchConfig(force: false) }
        waitUntil { engine.remoteConfigForTesting == nil }
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=WhilePaused", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)

        // Reactivated with UNCHANGED content: the routine conditional GET
        // returns 304 against the last active config's ETag. That must clear
        // the pause and resume from cache; before the fix the SDK stayed
        // killed forever on this path.
        setPhase(.notModified)
        engine.queue.async { engine.fetchConfig(force: false) }
        waitUntil { engine.remoteConfigForTesting != nil }
        XCTAssertEqual(engine.remoteConfigForTesting?.monitoringVersion, "46")
        let lastConfigRequest = transport.requests(matching: "custom-config").last
        XCTAssertEqual(lastConfigRequest?.headers["if-none-match"], "\"v46etag\"")

        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=BackAgain", method: "GET", body: nil, status: 200)
        engine.flush()
        waitUntil { self.collectBodies().count == 1 }
        guard case .object(let payload)? = collectBodies().first else { return XCTFail("no payload after reactivation") }
        XCTAssertEqual(payload["e"], .string("BackAgain"))

        // The kill marker is gone: a cold start begins from cache instantly.
        let second = makeEngine()
        second.configure(MonitaConfiguration(token: "dom_testtoken1234567890123"))
        second.syncForTesting()
        XCTAssertEqual(second.remoteConfigForTesting?.monitoringVersion, "46")
    }

    func testCircuitBreakerTripsAfterHundredMatchedEventsInWindow() {
        transport.route("custom-config") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("collect.monita.ai") { .init(status: 204) }
        let engine = makeEngine()
        configureAndWait(engine)
        // The fake clock is frozen, so every capture lands in one 6s window.
        for i in 0..<130 {
            engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Burst\(i)", method: "GET", body: nil, status: 200)
        }
        engine.flush()
        engine.syncForTesting()
        func delivered() -> Int {
            var count = 0
            for body in collectBodies() {
                guard case .object(let payload) = body else { continue }
                if case .array(let events)? = payload["events"] {
                    count += events.count
                } else if payload.contains("e") {
                    count += 1
                }
            }
            return count
        }
        waitUntil { delivered() == 100 }
        XCTAssertEqual(delivered(), 100)
        // Capture stays off for the rest of the process lifetime.
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Later", method: "GET", body: nil, status: 200)
        engine.flush()
        engine.syncForTesting()
        XCTAssertEqual(engine.diskQueueForTesting?.isEmpty, true)
    }

    func testCustomEndpointsAreFullURLs() {
        transport.route("proxy.customer.test/monita-config.json") { .init(status: 200, body: Data(self.standardConfigJSON.utf8)) }
        transport.route("proxy.customer.test/ingest") { .init(status: 204) }
        let engine = makeEngine()
        engine.configure(MonitaConfiguration(
            token: "dom_testtoken1234567890123",
            collectEndpoint: "https://proxy.customer.test/ingest",
            configEndpoint: "https://proxy.customer.test/monita-config.json"
        ))
        engine.syncForTesting()
        waitUntil { engine.remoteConfigForTesting != nil }
        XCTAssertEqual(engine.remoteConfigForTesting?.monitoringVersion, "46")
        engine.captureForTesting(url: "https://www.facebook.com/tr?ev=Proxy", method: "GET", body: nil, status: 200)
        engine.flush()
        waitUntil { self.transport.requests(matching: "proxy.customer.test/ingest").count == 1 }
        XCTAssertEqual(transport.requests(matching: "proxy.customer.test/ingest").count, 1)
        XCTAssertEqual(transport.requests(matching: "collect.monita.ai").count, 0)
    }
}
