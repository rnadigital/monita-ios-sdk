//  Copyright RNA Digital PTY LTD

import Foundation

/// Port of the reference's batching sender. Events queue and ship as one
/// envelope: shared fields once at the top level, per event fields inside an
/// "events" array. A single queued event ships in the legacy flat shape.
/// Flush triggers: 10 events, 2 seconds after the first queued event, app
/// backgrounding, or a shared context change (which flushes the old envelope
/// first). Debug mode bypasses batching entirely.
///
/// Not thread safe by itself: confined to the engine's serial queue.
final class Batcher {

    static let maxEvents = 10
    static let maxWaitSeconds = 2.0
    static let maxBytes = 60_000
    /// The ingest worker accepts at most 50 events per POST; overflow is
    /// dropped server side, so chunks never exceed it.
    static let serverMaxEventsPerPost = 50

    private let queue: DispatchQueue
    private var pendingEvents: [JSONObject] = []
    private var shared: JSONObject?
    private var sharedKey: String?
    private var timerGeneration = 0
    private var timerActive = false

    /// Called with a ready to send body and its event count.
    var onChunk: ((Data, Int) -> Void)?
    var isDebugUnbatched: () -> Bool = { false }

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    var queuedEventCount: Int { pendingEvents.count }

    /// Accepts one full flat payload (shared plus event fields merged).
    func enqueue(_ payload: JSONObject) {
        if isDebugUnbatched() {
            let body = JSONValue.object(payload).serializedData()
            onChunk?(body, 1)
            return
        }
        let (payloadShared, event) = EventBuilder.split(payload)
        let key = JSONValue.object(payloadShared).serialized()
        if !pendingEvents.isEmpty, key != sharedKey {
            // Shared context changed mid queue (screen change, consent
            // update): flush the old envelope first; never mix contexts.
            flush()
        }
        if pendingEvents.isEmpty {
            shared = payloadShared
            sharedKey = key
        }
        pendingEvents.append(event)
        if pendingEvents.count >= Batcher.maxEvents {
            flush()
        } else if !timerActive {
            timerActive = true
            timerGeneration += 1
            let generation = timerGeneration
            queue.asyncAfter(deadline: .now() + Batcher.maxWaitSeconds) { [weak self] in
                guard let self = self, self.timerActive, self.timerGeneration == generation else { return }
                self.flush()
            }
        }
    }

    func flush() {
        timerActive = false
        guard !pendingEvents.isEmpty, let shared = shared else { return }
        let events = pendingEvents
        pendingEvents = []
        self.shared = nil
        self.sharedKey = nil
        for (body, count) in Batcher.chunks(shared: shared, events: events) {
            onChunk?(body, count)
        }
    }

    func discardQueued() {
        timerActive = false
        pendingEvents = []
        shared = nil
        sharedKey = nil
    }

    /// Chunks events by serialized size (60KB, mirroring the reference's
    /// sendBeacon headroom) and by the ingest worker's 50 event cap. A single
    /// event chunk serializes in the legacy flat shape (shared and event
    /// fields merged, no "events" key).
    static func chunks(shared: JSONObject, events: [JSONObject]) -> [(Data, Int)] {
        let baseSize = JSONValue.object(shared).serialized().utf8.count + 16
        var out: [(Data, Int)] = []
        var chunk: [JSONObject] = []
        var size = baseSize
        func emit() {
            guard !chunk.isEmpty else { return }
            out.append((serializeChunk(shared: shared, events: chunk), chunk.count))
            chunk = []
            size = baseSize
        }
        for event in events {
            let eventSize = JSONValue.object(event).serialized().utf8.count + 1
            if !chunk.isEmpty, size + eventSize > maxBytes || chunk.count >= serverMaxEventsPerPost {
                emit()
            }
            chunk.append(event)
            size += eventSize
        }
        emit()
        return out
    }

    static func serializeChunk(shared: JSONObject, events: [JSONObject]) -> Data {
        if events.count == 1 {
            var flat = shared
            flat.merge(events[0])
            return JSONValue.object(flat).serializedData()
        }
        var envelope = shared
        envelope["events"] = .array(events.map { .object($0) })
        return JSONValue.object(envelope).serializedData()
    }
}
