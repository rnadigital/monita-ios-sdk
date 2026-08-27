//  Copyright RNA Digital PTY LTD

import XCTest
@testable import MonitaSDK

final class UploaderTests: XCTestCase {

    private var directory: URL = FileManager.default.temporaryDirectory
    private let queue = DispatchQueue(label: "test.uploader")

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("monita-uploader-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        super.tearDown()
    }

    private func makeUploader(transport: MockTransport, disk: DiskQueue) -> Uploader {
        let uploader = Uploader(
            queue: queue,
            transport: transport,
            diskQueue: disk,
            endpoint: URL(string: "https://collect.monita.ai/api/v1")
        )
        uploader.backoffBase = 0.05
        uploader.backoffCap = 0.2
        return uploader
    }

    private func wait(until check: @escaping () -> Bool, timeout: TimeInterval = 5) {
        let deadline = Date().addingTimeInterval(timeout)
        while !check(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testRecordDeletedOnlyAfterTwoHundred() {
        let transport = MockTransport()
        transport.route("collect.monita.ai") { .init(status: 204) }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        disk.append(body: Data("{\"b\":2}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        queue.async { uploader.kick() }
        wait(until: { self.queue.sync { disk.isEmpty } })
        XCTAssertTrue(queue.sync { disk.isEmpty })
        XCTAssertEqual(transport.requests(matching: "collect").count, 2)
        XCTAssertEqual(transport.requests[0].method, "POST")
        XCTAssertEqual(transport.requests[0].headers["content-type"], "application/json")
        XCTAssertEqual(String(data: transport.requests[0].body ?? Data(), encoding: .utf8), "{\"a\":1}")
    }

    func testFailureKeepsRecordAndRetriesWithBackoff() {
        let transport = MockTransport()
        let lock = NSLock()
        var failuresLeft = 2
        transport.route("collect.monita.ai") {
            lock.lock()
            defer { lock.unlock() }
            if failuresLeft > 0 {
                failuresLeft -= 1
                return .init(status: 500)
            }
            return .init(status: 204)
        }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        queue.async { uploader.kick() }
        wait(until: { self.queue.sync { disk.isEmpty } })
        XCTAssertTrue(queue.sync { disk.isEmpty })
        XCTAssertEqual(transport.requests(matching: "collect").count, 3)
    }

    func testTransportErrorRetries() {
        let transport = MockTransport()
        let lock = NSLock()
        var failuresLeft = 1
        transport.route("collect.monita.ai") {
            lock.lock()
            defer { lock.unlock() }
            if failuresLeft > 0 {
                failuresLeft -= 1
                return .init(status: nil)
            }
            return .init(status: 204)
        }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        queue.async { uploader.kick() }
        wait(until: { self.queue.sync { disk.isEmpty } })
        XCTAssertTrue(queue.sync { disk.isEmpty })
    }

    func testKickDuringScheduledRetryNeverBypassesBackoff() {
        let transport = MockTransport()
        transport.route("collect.monita.ai") { .init(status: 500) }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        uploader.backoffBase = 30 // far beyond the test window
        uploader.backoffCap = 60
        queue.sync { uploader.kick() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertEqual(transport.requests.count, 1)
        // New batches keep arriving and kicking; none may bypass the backoff.
        for _ in 0..<20 {
            queue.sync {
                disk.append(body: Data("{\"more\":1}".utf8), eventCount: 1)
                uploader.kick()
            }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(transport.requests.count, 1)
    }

    func testNetworkRestoredCancelsBackoffForPromptRecovery() {
        let transport = MockTransport()
        let lock = NSLock()
        var failuresLeft = 1
        transport.route("collect.monita.ai") {
            lock.lock()
            defer { lock.unlock() }
            if failuresLeft > 0 {
                failuresLeft -= 1
                return .init(status: 500)
            }
            return .init(status: 204)
        }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        uploader.backoffBase = 30 // the scheduled retry alone would be far too late
        uploader.backoffCap = 60
        queue.sync { uploader.kick() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        XCTAssertFalse(queue.sync { disk.isEmpty })
        queue.async { uploader.networkRestored() }
        wait(until: { self.queue.sync { disk.isEmpty } }, timeout: 2)
        XCTAssertTrue(queue.sync { disk.isEmpty })
    }

    func testNoUploadWhileUnreachable() {
        let transport = MockTransport()
        transport.route("collect.monita.ai") { .init(status: 204) }
        let disk = DiskQueue(directory: directory)
        disk.append(body: Data("{\"a\":1}".utf8), eventCount: 1)
        let uploader = makeUploader(transport: transport, disk: disk)
        uploader.isReachable = { false }
        queue.sync { uploader.kick() }
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(transport.requests.isEmpty)
        XCTAssertFalse(queue.sync { disk.isEmpty })
        // Network returns: the next kick drains.
        uploader.isReachable = { true }
        queue.async { uploader.kick() }
        wait(until: { self.queue.sync { disk.isEmpty } })
        XCTAssertTrue(queue.sync { disk.isEmpty })
    }
}
