//  Copyright RNA Digital PTY LTD

import Foundation

/// Drains the disk queue one record at a time. A record is acknowledged (and
/// only then deleted) after an HTTP 2xx from the collect endpoint. Failures
/// retry with exponential backoff plus jitter (base 5 seconds, capped at 10
/// minutes), and only while the network is reachable. While a retry is
/// scheduled, kick() is a no op so a stream of new batches can never bypass
/// the backoff; the deliberate escape hatch is networkRestored(), which
/// cancels the pending backoff for prompt recovery when connectivity returns.
/// Confined to the engine's serial queue: every mutation happens on `queue`,
/// including the transport completion, which hops back onto it. That queue
/// confinement is why the class is @unchecked Sendable.
final class Uploader: @unchecked Sendable {

    static let backoffBaseSeconds = 5.0
    static let backoffCapSeconds = 600.0

    /// Instance backoff parameters (overridable so tests run fast).
    var backoffBase = Uploader.backoffBaseSeconds
    var backoffCap = Uploader.backoffCapSeconds

    private let queue: DispatchQueue
    private let transport: HTTPTransport
    private let diskQueue: DiskQueue
    private let endpoint: URL?
    private var inFlight = false
    private var retryScheduled = false
    private var attempts = 0
    private var generation = 0
    private var retryGeneration = 0

    var isReachable: () -> Bool = { true }

    init(queue: DispatchQueue, transport: HTTPTransport, diskQueue: DiskQueue, endpoint: URL?) {
        self.queue = queue
        self.transport = transport
        self.diskQueue = diskQueue
        self.endpoint = endpoint
    }

    /// Cancels any scheduled retry and resets backoff (used when the queue is
    /// cleared by a kill switch or opt out). Also invalidates the in flight
    /// completion, which is correct there because the record it would have
    /// acknowledged has been cleared.
    func reset() {
        generation += 1
        retryGeneration += 1
        retryScheduled = false
        attempts = 0
    }

    /// Reachability returned: cancel the pending backoff (its records are
    /// still queued) and try again immediately with fresh backoff state.
    func networkRestored() {
        retryGeneration += 1
        retryScheduled = false
        attempts = 0
        kick()
    }

    /// Attempts the next record if idle. Safe to call often: while an upload
    /// is in flight or a backoff retry is scheduled this is a no op.
    func kick() {
        guard !inFlight, !retryScheduled, isReachable(), let endpoint = endpoint else { return }
        guard let record = diskQueue.peek() else { return }
        inFlight = true
        let currentGeneration = generation

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = record.body

        MonitaLog.debug("uploading record \(record.id) with \(record.eventCount) events")
        transport.perform(request) { [weak self] status, _, _ in
            guard let self = self else { return }
            self.queue.async {
                self.inFlight = false
                guard currentGeneration == self.generation else { return }
                if let status = status, (200..<300).contains(status) {
                    self.diskQueue.ack(record.id)
                    self.attempts = 0
                    self.kick()
                } else {
                    self.attempts += 1
                    self.scheduleRetry()
                }
            }
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        let exponent = min(Double(attempts - 1), 12)
        let base = min(backoffCap, backoffBase * pow(2, exponent))
        let jitter = base * Double.random(in: 0...0.25)
        let delay = min(backoffCap, base + jitter)
        let currentRetryGeneration = retryGeneration
        MonitaLog.debug("upload failed, retrying in \(Int(delay))s (attempt \(attempts))")
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, currentRetryGeneration == self.retryGeneration else { return }
            self.retryScheduled = false
            self.kick()
        }
    }
}
