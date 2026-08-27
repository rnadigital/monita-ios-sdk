//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class BatcherTests: XCTestCase {

    private var queue: DispatchQueue = DispatchQueue(label: "test.batcher")

    private func context(cn: String? = nil) -> SharedContext {
        SharedContext(
            token: "dom_batchtoken1234567890123",
            mv: "2.0.1",
            sv: "46",
            u: "app://com.example.shop/Checkout",
            p: "Checkout",
            vid: "11111111-2222-4333-8444-555555555555",
            sid: "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            doValue: "com.example.shop",
            av: "1.4.2+387",
            rl: "ios 17.5",
            cn: cn
        )
    }

    private func payload(event: String, cn: String? = nil, blob: String? = nil) -> JSONObject {
        let vendor = VendorConfig(vendorName: "Facebook (Meta Pixel)", urlPatternMatches: ["facebook.com/tr"])
        var data = JSONObject([("ev", .string(event))])
        if let blob = blob {
            data["blob"] = .string(blob)
        }
        data["vendorName"] = .string(vendor.vendorName)
        var payloads = EventBuilder.buildPayloads(
            context: context(cn: cn),
            vendor: VendorConfig(
                vendorName: vendor.vendorName,
                urlPatternMatches: vendor.urlPatternMatches,
                eventParameter: "{{ev}}"
            ),
            data: data,
            vu: "https://www.facebook.com/tr?ev=\(event)",
            method: "POST",
            tm: 1724732400.5,
            status: "success"
        )
        XCTAssertEqual(payloads.count, 1)
        return payloads.removeFirst()
    }

    private func makeBatcher(debug: Bool = false) -> (Batcher, () -> [(JSONValue, Int)]) {
        let batcher = Batcher(queue: queue)
        let lock = NSLock()
        var sent: [(JSONValue, Int)] = []
        batcher.isDebugUnbatched = { debug }
        batcher.onChunk = { body, count in
            guard let parsed = JSONParser.parse(body) else {
                XCTFail("chunk is not valid JSON")
                return
            }
            lock.lock()
            sent.append((parsed, count))
            lock.unlock()
        }
        return (batcher, {
            lock.lock()
            defer { lock.unlock() }
            return sent
        })
    }

    private func run(_ work: @escaping () -> Void) {
        queue.sync(execute: work)
    }

    // MARK: - Envelope format

    func testTenEventsFlushImmediatelyAsOneEnvelope() {
        let (batcher, sent) = makeBatcher()
        run {
            for i in 0..<10 {
                batcher.enqueue(self.payload(event: "ev_\(i)"))
            }
        }
        let beacons = sent()
        XCTAssertEqual(beacons.count, 1)
        guard case .object(let envelope) = beacons[0].0 else { return XCTFail("not an object") }
        XCTAssertEqual(envelope["t"], .string("dom_batchtoken1234567890123"))
        XCTAssertEqual(envelope["dm"], .string("app"))
        XCTAssertEqual(envelope["mv"], .string("2.0.1"))
        XCTAssertEqual(envelope["sv"], .string("46"))
        XCTAssertEqual(envelope["s"], .string("ios-sdk"))
        XCTAssertEqual(envelope["u"], .string("app://com.example.shop/Checkout"))
        XCTAssertEqual(envelope["p"], .string("Checkout"))
        XCTAssertEqual(envelope["do"], .string("com.example.shop"))
        XCTAssertEqual(envelope["av"], .string("1.4.2+387"))
        XCTAssertEqual(envelope["rl"], .string("ios 17.5"))
        XCTAssertEqual(envelope["env"], .string("production"))
        XCTAssertEqual(envelope["et"], .string(""))
        // Per event fields never leak into the envelope.
        XCTAssertFalse(envelope.contains("e"))
        XCTAssertFalse(envelope.contains("vn"))
        XCTAssertFalse(envelope.contains("tm"))
        guard case .array(let events)? = envelope["events"] else { return XCTFail("no events array") }
        XCTAssertEqual(events.count, 10)
        for (i, entry) in events.enumerated() {
            guard case .object(let event) = entry else { return XCTFail("event is not an object") }
            XCTAssertEqual(event["e"], .string("ev_\(i)"))
            XCTAssertEqual(event["vn"], .string("Facebook (Meta Pixel)"))
            XCTAssertEqual(event["m"], .string("POST"))
            XCTAssertEqual(event["st"], .string("success"))
            XCTAssertNotNil(event["vu"])
            XCTAssertNotNil(event["tm"])
            if case .array? = event["dt"] {} else { XCTFail("dt missing") }
            XCTAssertEqual(event["np"], .array([]))
            // Shared fields are not duplicated per entry.
            XCTAssertFalse(event.contains("t"))
            XCTAssertFalse(event.contains("u"))
            XCTAssertFalse(event.contains("vid"))
            XCTAssertFalse(event.contains("sid"))
            XCTAssertFalse(event.contains("mv"))
        }
    }

    func testSingleEventShipsLegacyFlatShape() {
        let (batcher, sent) = makeBatcher()
        run {
            batcher.enqueue(self.payload(event: "Solo"))
            XCTAssertEqual(sent().count, 0)
            batcher.flush()
        }
        let beacons = sent()
        XCTAssertEqual(beacons.count, 1)
        guard case .object(let flat) = beacons[0].0 else { return XCTFail("not an object") }
        XCTAssertFalse(flat.contains("events"))
        XCTAssertEqual(flat["e"], .string("Solo"))
        XCTAssertEqual(flat["vn"], .string("Facebook (Meta Pixel)"))
        XCTAssertEqual(flat["t"], .string("dom_batchtoken1234567890123"))
        XCTAssertEqual(flat["u"], .string("app://com.example.shop/Checkout"))
    }

    func testFlushSendsRemainderAndSecondFlushSendsNothing() {
        let (batcher, sent) = makeBatcher()
        run {
            batcher.enqueue(self.payload(event: "a"))
            batcher.enqueue(self.payload(event: "b"))
            batcher.enqueue(self.payload(event: "c"))
            XCTAssertEqual(sent().count, 0)
            batcher.flush()
            batcher.flush()
        }
        let beacons = sent()
        XCTAssertEqual(beacons.count, 1)
        XCTAssertEqual(beacons[0].1, 3)
    }

    func testTimerFlushesPartialQueue() {
        let (batcher, sent) = makeBatcher()
        run {
            batcher.enqueue(self.payload(event: "a"))
            batcher.enqueue(self.payload(event: "b"))
        }
        XCTAssertEqual(sent().count, 0)
        let deadline = Date().addingTimeInterval(4)
        while sent().isEmpty, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let beacons = sent()
        XCTAssertEqual(beacons.count, 1)
        XCTAssertEqual(beacons[0].1, 2)
    }

    func testSharedContextChangeFlushesOldEnvelopeFirst() {
        let (batcher, sent) = makeBatcher()
        run {
            batcher.enqueue(self.payload(event: "before"))
            batcher.enqueue(self.payload(event: "after", cn: "granted"))
        }
        var beacons = sent()
        XCTAssertEqual(beacons.count, 1)
        guard case .object(let first) = beacons[0].0 else { return XCTFail("not an object") }
        XCTAssertEqual(first["e"], .string("before"))
        run { batcher.flush() }
        beacons = sent()
        XCTAssertEqual(beacons.count, 2)
        guard case .object(let second) = beacons[1].0 else { return XCTFail("not an object") }
        XCTAssertEqual(second["e"], .string("after"))
        XCTAssertEqual(second["cn"], .string("granted"))
    }

    func testSizeCapSplitsIntoMultipleChunks() {
        let (batcher, sent) = makeBatcher()
        run {
            for i in 0..<3 {
                batcher.enqueue(self.payload(event: "big_\(i)", blob: String(repeating: "a", count: 25000)))
            }
            batcher.flush()
        }
        let beacons = sent()
        XCTAssertGreaterThanOrEqual(beacons.count, 2)
        var names: [String] = []
        for (value, _) in beacons {
            guard case .object(let body) = value else { continue }
            XCTAssertLessThan(value.serialized().utf8.count, 64000)
            if case .array(let events)? = body["events"] {
                for entry in events {
                    if case .object(let e) = entry, case .string(let name)? = e["e"] {
                        names.append(name)
                    }
                }
            } else if case .string(let name)? = body["e"] {
                names.append(name)
            }
        }
        XCTAssertEqual(names.sorted(), ["big_0", "big_1", "big_2"])
    }

    func testServerEventCapNeverExceedsFiftyPerChunk() {
        var events: [JSONObject] = []
        for i in 0..<120 {
            events.append(JSONObject([("e", .string("ev_\(i)")), ("tm", .double(1))]))
        }
        let shared = JSONObject([("t", .string("dom_x"))])
        let chunks = Batcher.chunks(shared: shared, events: events)
        XCTAssertEqual(chunks.map { $0.1 }, [50, 50, 20])
    }

    func testDebugModeBypassesBatching() {
        let (batcher, sent) = makeBatcher(debug: true)
        run {
            batcher.enqueue(self.payload(event: "one"))
            batcher.enqueue(self.payload(event: "two"))
            batcher.enqueue(self.payload(event: "three"))
        }
        let beacons = sent()
        XCTAssertEqual(beacons.count, 3)
        var names: [String] = []
        for (value, count) in beacons {
            XCTAssertEqual(count, 1)
            guard case .object(let flat) = value else { continue }
            XCTAssertFalse(flat.contains("events"))
            XCTAssertEqual(flat["t"], .string("dom_batchtoken1234567890123"))
            if case .string(let name)? = flat["e"] {
                names.append(name)
            }
        }
        XCTAssertEqual(names, ["one", "two", "three"])
    }
}
