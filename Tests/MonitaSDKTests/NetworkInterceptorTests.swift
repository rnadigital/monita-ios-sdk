//  Copyright RNA Digital PTY LTD

import XCTest
import Network
@testable import MonitaSDK

/// Real interception tests: the resume swizzle observes an actual URLSession
/// request round trip against a local loopback HTTP server, and completion
/// status arrives through the KVO path.
final class NetworkInterceptorTests: XCTestCase {

    /// Minimal loopback HTTP server: reads one request, answers a fixed 207.
    private final class LoopbackServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "test.loopback")
        private var connections: [NWConnection] = []
        private(set) var port: UInt16 = 0

        init?() {
            guard let listener = try? NWListener(using: .tcp, on: .any) else { return nil }
            self.listener = listener
            let ready = DispatchSemaphore(value: 0)
            listener.stateUpdateHandler = { state in
                if case .ready = state { ready.signal() }
                if case .failed = state { ready.signal() }
            }
            listener.newConnectionHandler = { [weak self] connection in
                self?.queue.async {
                    self?.connections.append(connection)
                    self?.serve(connection)
                }
            }
            listener.start(queue: queue)
            guard ready.wait(timeout: .now() + 5) == .success, let port = listener.port else {
                listener.cancel()
                return nil
            }
            self.port = port.rawValue
        }

        private func serve(_ connection: NWConnection) {
            connection.start(queue: queue)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 128 * 1024) { _, _, _, _ in
                let response = "HTTP/1.1 207 Multi-Status\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
        }

        func stop() {
            listener.cancel()
            queue.sync {
                connections.forEach { $0.cancel() }
                connections = []
            }
        }
    }

    /// Thread safe recorder for interceptor events.
    private final class Recorder: @unchecked Sendable {
        enum Event {
            case resume(key: ObjectIdentifier, request: CapturedRequest)
            case completion(key: ObjectIdentifier, status: Int?, errored: Bool)
        }

        private let lock = NSLock()
        private var storage: [Event] = []
        var blockedSubstring: String?

        var events: [Event] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func record(_ event: Event) {
            lock.lock()
            storage.append(event)
            lock.unlock()
        }

        func install() {
            NetworkInterceptor.setHandlers(
                shouldCapture: { [weak self] url in
                    guard let self = self else { return false }
                    if let blocked = self.blockedSubstring, url.contains(blocked) { return false }
                    return url.contains("127.0.0.1")
                },
                onResume: { [weak self] event in
                    self?.record(.resume(key: event.taskKey, request: event.request))
                },
                onCompletion: { [weak self] key, status, errored in
                    self?.record(.completion(key: key, status: status, errored: errored))
                }
            )
        }
    }

    private var server: LoopbackServer?
    private var recorder = Recorder()

    override func setUp() {
        super.setUp()
        recorder = Recorder()
        server = LoopbackServer()
    }

    override func tearDown() {
        // Leave inert handlers behind so later resumed tasks record nothing.
        NetworkInterceptor.setHandlers(
            shouldCapture: { _ in false },
            onResume: { _ in },
            onCompletion: { _, _, _ in }
        )
        server?.stop()
        server = nil
        super.tearDown()
    }

    private func waitUntil(timeout: TimeInterval = 8, _ check: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !check(), Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testResumeImplementingClassIsFoundInTheClassCluster() {
        let selector = NSSelectorFromString("resume")
        guard let cls = NetworkInterceptor.resumeImplementingClass(selector: selector) else {
            return XCTFail("resume implementing class not found")
        }
        XCTAssertNotNil(class_getInstanceMethod(cls, selector))
        // The walk starts from a concrete task, so the found class is part of
        // the URLSessionTask hierarchy.
        var candidate: AnyClass? = cls
        var reachesNSObject = false
        while let current = candidate {
            if current == NSObject.self { reachesNSObject = true; break }
            candidate = class_getSuperclass(current)
        }
        XCTAssertTrue(reachesNSObject)
    }

    func testInstallIsIdempotent() {
        XCTAssertTrue(NetworkInterceptor.install())
        XCTAssertTrue(NetworkInterceptor.install())
        XCTAssertTrue(NetworkInterceptor.isInstalled)
    }

    func testRoundTripCapturesRequestThenCompletionStatus() throws {
        guard let server = server else { throw XCTSkip("loopback listener unavailable") }
        recorder.install()
        XCTAssertTrue(NetworkInterceptor.install())

        guard let url = URL(string: "http://127.0.0.1:\(server.port)/tr?ev=Purchase") else {
            return XCTFail("bad url")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data("{\"a\":\"1\"}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        task.resume()

        waitUntil { self.recorder.events.count >= 2 }
        let events = recorder.events
        XCTAssertEqual(events.count, 2)

        // Ordering: resume strictly before completion, correlated by key.
        guard case .resume(let resumeKey, let captured) = events[0] else {
            return XCTFail("first event is not the resume capture")
        }
        XCTAssertTrue(captured.url.hasSuffix("/tr?ev=Purchase"))
        XCTAssertEqual(captured.method, "POST")
        XCTAssertEqual(captured.body, Data("{\"a\":\"1\"}".utf8))
        XCTAssertEqual(captured.contentType, "application/json")

        guard case .completion(let completionKey, let status, let errored) = events[1] else {
            return XCTFail("second event is not the completion")
        }
        XCTAssertEqual(completionKey, resumeKey)
        XCTAssertEqual(status, 207)
        XCTAssertFalse(errored)
    }

    func testPrefilterSkipsRegistrationEntirely() throws {
        guard let server = server else { throw XCTSkip("loopback listener unavailable") }
        recorder.blockedSubstring = "/blocked"
        recorder.install()
        XCTAssertTrue(NetworkInterceptor.install())

        guard let url = URL(string: "http://127.0.0.1:\(server.port)/blocked?x=1") else {
            return XCTFail("bad url")
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let done = expectation(description: "request finished")
        let task = session.dataTask(with: url) { _, _, _ in done.fulfill() }
        task.resume()
        wait(for: [done], timeout: 8)
        // Prefiltered tasks register neither a resume event nor completion KVO.
        XCTAssertTrue(recorder.events.isEmpty)
    }

    func testDoubleResumeReportsOnce() throws {
        guard let server = server else { throw XCTSkip("loopback listener unavailable") }
        recorder.install()
        XCTAssertTrue(NetworkInterceptor.install())

        guard let url = URL(string: "http://127.0.0.1:\(server.port)/tr?ev=Twice") else {
            return XCTFail("bad url")
        }
        let session = URLSession(configuration: .ephemeral)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: url)
        task.resume()
        task.resume()
        waitUntil { self.recorder.events.count >= 2 }
        let resumes = recorder.events.filter { if case .resume = $0 { return true }; return false }
        XCTAssertEqual(resumes.count, 1)
    }
}
