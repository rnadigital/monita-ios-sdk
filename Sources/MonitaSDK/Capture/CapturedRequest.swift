//  Copyright RNA Digital PTY LTD

import Foundation

/// Immutable snapshot of an outgoing request, taken at resume time. The body
/// comes from httpBody only (never httpBodyStream) and is capped at 64KB;
/// larger bodies contribute URL parameters only.
struct CapturedRequest: Sendable {
    let url: String
    let method: String
    let body: Data?
    let contentType: String?
    let timestamp: Double
}

/// A capture with its final delivery status. `statusCode` is nil when the
/// task never completed or reported no HTTP response.
struct FinalizedCapture: Sendable {
    let request: CapturedRequest
    let statusCode: Int?
    let errored: Bool

    /// Tag status per the payload schema: success below 400, failure at 400
    /// and above or on error, nil (omitted) when unknown.
    var tagStatus: String? {
        if errored { return "failure" }
        guard let statusCode = statusCode else { return nil }
        return statusCode < 400 ? "success" : "failure"
    }
}

/// Pre config ring buffer: from configure() on, finalized captures buffer
/// here until the cached or fetched config arrives, then replay through the
/// pipeline. Capacity 50, entries older than 30 seconds are dropped at drain
/// time. Confined to the engine's serial queue.
final class PreConfigBuffer {
    static let capacity = 50
    static let ttlSeconds = 30.0

    private var entries: [FinalizedCapture] = []

    func append(_ capture: FinalizedCapture) {
        entries.append(capture)
        if entries.count > PreConfigBuffer.capacity {
            entries.removeFirst(entries.count - PreConfigBuffer.capacity)
        }
    }

    /// Removes and returns entries still within the TTL.
    func drain(now: Double) -> [FinalizedCapture] {
        let live = entries.filter { now - $0.request.timestamp <= PreConfigBuffer.ttlSeconds }
        entries = []
        return live
    }

    func clear() {
        entries = []
    }
}
