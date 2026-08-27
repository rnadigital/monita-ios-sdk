//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class DiskQueueTests: XCTestCase {

    private var directory: URL = FileManager.default.temporaryDirectory

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("monita-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func body(_ text: String) -> Data { Data(text.utf8) }

    // MARK: - On disk state builders (the queue's own line formats)

    private func recordLine(id: String, body: String) -> String {
        var object = JSONObject()
        object["id"] = .string(id)
        object["n"] = .int(1)
        object["b"] = .string(body)
        return JSONValue.object(object).serialized()
    }

    private func ackLine(id: String) -> String {
        "{\"ack\":\(JSONValue.string(id).serialized())}"
    }

    private func writeFile(_ name: String, lines: [String]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(name)
        try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: url)
    }

    func testAppendPeekAck() {
        let queue = DiskQueue(directory: directory)
        queue.append(body: body("{\"a\":1}"), eventCount: 1)
        queue.append(body: body("{\"b\":2}"), eventCount: 3)
        XCTAssertEqual(queue.recordCount, 2)
        XCTAssertEqual(queue.totalEvents, 4)
        guard let first = queue.peek() else { return XCTFail("no record") }
        XCTAssertEqual(String(data: first.body, encoding: .utf8), "{\"a\":1}")
        queue.ack(first.id)
        XCTAssertEqual(queue.recordCount, 1)
        XCTAssertEqual(queue.totalEvents, 3)
        XCTAssertEqual(String(data: queue.peek()?.body ?? Data(), encoding: .utf8), "{\"b\":2}")
    }

    func testRecordsPersistAcrossReload() {
        let queue = DiskQueue(directory: directory)
        queue.append(body: body("{\"a\":1}"), eventCount: 2)
        queue.append(body: body("{\"b\":2}"), eventCount: 1)

        let reloaded = DiskQueue(directory: directory)
        XCTAssertEqual(reloaded.recordCount, 2)
        XCTAssertEqual(reloaded.totalEvents, 3)
        XCTAssertEqual(String(data: reloaded.peek()?.body ?? Data(), encoding: .utf8), "{\"a\":1}")
    }

    func testAckedRecordsStayGoneAfterReload() {
        let queue = DiskQueue(directory: directory)
        queue.append(body: body("{\"a\":1}"), eventCount: 1)
        queue.append(body: body("{\"b\":2}"), eventCount: 1)
        guard let first = queue.peek() else { return XCTFail("no record") }
        queue.ack(first.id)

        let reloaded = DiskQueue(directory: directory)
        XCTAssertEqual(reloaded.recordCount, 1)
        XCTAssertEqual(String(data: reloaded.peek()?.body ?? Data(), encoding: .utf8), "{\"b\":2}")
    }

    func testEventCapDropsOldestFirst() {
        let queue = DiskQueue(directory: directory)
        for i in 0..<12 {
            queue.append(body: body("{\"i\":\(i)}"), eventCount: 50)
        }
        // 12 * 50 = 600 events exceeds the 500 cap; the oldest drop first.
        XCTAssertLessThanOrEqual(queue.totalEvents, DiskQueue.maxEvents)
        XCTAssertEqual(String(data: queue.peek()?.body ?? Data(), encoding: .utf8), "{\"i\":2}")
    }

    func testByteCapDropsOldestFirst() {
        let queue = DiskQueue(directory: directory)
        let big = String(repeating: "x", count: 600 * 1024)
        queue.append(body: body("{\"first\":\"\(big)\"}"), eventCount: 1)
        queue.append(body: body("{\"second\":\"\(big)\"}"), eventCount: 1)
        queue.append(body: body("{\"third\":\"\(big)\"}"), eventCount: 1)
        queue.append(body: body("{\"fourth\":\"\(big)\"}"), eventCount: 1)
        XCTAssertLessThanOrEqual(queue.totalBytes, DiskQueue.maxBytes)
        XCTAssertFalse(String(data: queue.peek()?.body ?? Data(), encoding: .utf8)?.contains("first") ?? true)
    }

    func testCrashBeforeCompactionRenameRecoversFromSegmentAndAcks() {
        // Death mid compaction, before the rename: the old segment and acks
        // are intact and a (possibly partial) temp file is left behind. The
        // temp must be discarded and every pending record recovered.
        writeFile("segment.jsonl", lines: [
            recordLine(id: "a", body: "{\"x\":1}"),
            recordLine(id: "b", body: "{\"x\":2}"),
            recordLine(id: "c", body: "{\"x\":3}"),
        ])
        writeFile("acks.jsonl", lines: [ackLine(id: "a")])
        writeFile("segment.tmp.jsonl", lines: ["{\"id\":\"b\",\"n\":1,\"b"])

        let queue = DiskQueue(directory: directory)
        XCTAssertEqual(queue.recordCount, 2)
        XCTAssertEqual(String(data: queue.peek()?.body ?? Data(), encoding: .utf8), "{\"x\":2}")
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("segment.tmp.jsonl").path))
        // The startup compaction itself must leave a loadable state.
        let reloaded = DiskQueue(directory: directory)
        XCTAssertEqual(reloaded.recordCount, 2)
        XCTAssertEqual(String(data: reloaded.peek()?.body ?? Data(), encoding: .utf8), "{\"x\":2}")
    }

    func testCrashAfterRenameBeforeAcksDeleteRecovers() {
        // Death after the rename but before the acks delete: the segment
        // already holds only live records and the stale acks reference ids
        // that no longer exist. Nothing may be lost or double filtered.
        writeFile("segment.jsonl", lines: [
            recordLine(id: "b", body: "{\"x\":2}"),
            recordLine(id: "c", body: "{\"x\":3}"),
        ])
        writeFile("acks.jsonl", lines: [ackLine(id: "a")])

        let queue = DiskQueue(directory: directory)
        XCTAssertEqual(queue.recordCount, 2)
        XCTAssertEqual(String(data: queue.peek()?.body ?? Data(), encoding: .utf8), "{\"x\":2}")
        XCTAssertEqual(queue.totalEvents, 2)
    }

    func testSegmentFileCompactsInPlaceDuringChurn() {
        let queue = DiskQueue(directory: directory)
        let segmentURL = directory.appendingPathComponent("segment.jsonl")
        let bigBody = "{\"pad\":\"" + String(repeating: "x", count: 300_000) + "\"}"
        var totalAppended = 0
        // Sustained churn: appends keep arriving while earlier records are
        // acknowledged, as during a long collect outage with partial success.
        for _ in 0..<20 {
            queue.append(body: body(bigBody), eventCount: 1)
            queue.append(body: body(bigBody), eventCount: 1)
            totalAppended += 2 * bigBody.utf8.count
            if let first = queue.peek() {
                queue.ack(first.id)
            }
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: segmentURL.path)
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        // Without in place compaction the segment file would hold everything
        // ever appended (~12MB). Compaction bounds it near live + threshold.
        XCTAssertGreaterThan(totalAppended, 10 * 1024 * 1024)
        XCTAssertGreaterThan(fileSize, 0)
        XCTAssertLessThan(fileSize, DiskQueue.maxBytes + DiskQueue.compactThresholdBytes + 512 * 1024)
        // Compaction never leaves its temp file behind.
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("segment.tmp.jsonl").path))
        // Live records survive compaction and a reload.
        let reloaded = DiskQueue(directory: directory)
        XCTAssertEqual(reloaded.recordCount, queue.recordCount)
        XCTAssertEqual(reloaded.totalBytes, queue.totalBytes)
    }

    func testClearRemovesEverything() {
        let queue = DiskQueue(directory: directory)
        queue.append(body: body("{\"a\":1}"), eventCount: 1)
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        let reloaded = DiskQueue(directory: directory)
        XCTAssertTrue(reloaded.isEmpty)
    }
}
