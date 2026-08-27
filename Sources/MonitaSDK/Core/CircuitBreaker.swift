//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of the reference's circuit breaker: more than 100 captured events in
/// a 6 second window trips capture off for the rest of the process lifetime.
struct CircuitBreaker {
    static let maxRequestsPerWindow = 100
    static let windowSeconds = 6.0

    private var requestCount = 0
    private var windowStart: Double
    private(set) var tripped = false

    init(now: Double) {
        windowStart = now
    }

    /// Returns true when the capture may proceed.
    mutating func allow(now: Double) -> Bool {
        if tripped { return false }
        if now - windowStart > CircuitBreaker.windowSeconds {
            requestCount = 0
            windowStart = now
        }
        requestCount += 1
        if requestCount > CircuitBreaker.maxRequestsPerWindow {
            tripped = true
            MonitaLog.error("circuit breaker tripped, too many captures, monitoring stopped for this launch")
            return false
        }
        return true
    }
}
