//  Copyright RNA Digital PTY LTD

import Foundation

/// Persistent delivery queue backed by append only JSON lines segment files.
/// Each record is one ready to send POST body plus its event count. A record
/// is removed only after an acknowledged delivery (HTTP 2xx); acknowledgements
/// are themselves appended (to an acks file) so a crash between delivery and
/// compaction never resends more than one in flight record.
///
/// Compaction (on startup and once the bytes of acked or dropped records pass
/// a threshold) is crash atomic: live records are written to a temp file,
/// fsynced, renamed over the segment (rename(2) is atomic), and only then is
/// the acks file deleted. Process death before the rename leaves the old
/// segment plus acks authoritative (a leftover temp file is discarded on
/// load); death after the rename leaves a fresh segment plus stale acks whose
/// ids match nothing. No window loses a pending record.
///
/// Caps: 500 events or 2MB of bodies; oldest records are dropped first. The
/// compaction threshold bounds file growth during long outages.
/// Not thread safe by itself: confined to the engine's serial queue.
final class DiskQueue {

    struct Record {
        let id: String
        let eventCount: Int
        let body: Data
    }

    static let maxEvents = 500
    static let maxBytes = 2 * 1024 * 1024
    /// Dead bytes (acked or dropped record bodies still sitting in the
    /// segment file) tolerated before an in place compaction.
    static let compactThresholdBytes = 2 * DiskQueue.maxBytes

    private let directory: URL
    private let segmentURL: URL
    private let acksURL: URL
    private let tempSegmentURL: URL
    private var records: [Record] = []
    private var sequence = 0
    /// Bytes of acked or dropped records still present in the segment file.
    private var deadBytes = 0

    private(set) var totalEvents = 0
    private(set) var totalBytes = 0

    init(directory: URL) {
        self.directory = directory
        self.segmentURL = directory.appendingPathComponent("segment.jsonl")
        self.acksURL = directory.appendingPathComponent("acks.jsonl")
        self.tempSegmentURL = directory.appendingPathComponent("segment.tmp.jsonl")
        prepareDirectory()
        loadAndCompact()
    }

    var isEmpty: Bool { records.isEmpty }
    var recordCount: Int { records.count }

    func peek() -> Record? { records.first }

    func append(body: Data, eventCount: Int) {
        sequence += 1
        let id = "\(Int(Date().timeIntervalSince1970 * 1000))-\(sequence)"
        let record = Record(id: id, eventCount: eventCount, body: body)
        records.append(record)
        totalEvents += eventCount
        totalBytes += body.count
        appendLine(recordLine(record), to: segmentURL)
        enforceCaps()
    }

    func ack(_ id: String) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        let record = records.remove(at: index)
        totalEvents -= record.eventCount
        totalBytes -= record.body.count
        if records.isEmpty {
            deadBytes = 0
            resetFiles()
        } else {
            deadBytes += record.body.count
            appendLine("{\"ack\":\(JSONValue.string(id).serialized())}", to: acksURL)
            compactIfNeeded()
        }
    }

    func clear() {
        records = []
        totalEvents = 0
        totalBytes = 0
        deadBytes = 0
        resetFiles()
    }

    // MARK: - Internal

    private func enforceCaps() {
        while (totalEvents > DiskQueue.maxEvents || totalBytes > DiskQueue.maxBytes), records.count > 1 {
            let dropped = records.removeFirst()
            totalEvents -= dropped.eventCount
            totalBytes -= dropped.body.count
            deadBytes += dropped.body.count
            MonitaLog.debug("queue cap reached, dropping oldest record \(dropped.id) with \(dropped.eventCount) events")
            appendLine("{\"ack\":\(JSONValue.string(dropped.id).serialized())}", to: acksURL)
        }
        compactIfNeeded()
    }

    /// Rewrites the segment file with only live records once the dead bytes
    /// inside it pass the threshold, bounding file growth during outages.
    private func compactIfNeeded() {
        guard deadBytes > DiskQueue.compactThresholdBytes else { return }
        compact()
    }

    private func compact() {
        guard rewriteSegmentAtomically() else { return }
        deadBytes = 0
        MonitaLog.debug("queue compacted, \(records.count) live records rewritten")
    }

    /// Crash atomic segment rewrite: temp write, fsync, rename over the
    /// segment, then delete the acks file. Returns false (leaving the old
    /// segment and acks untouched and still consistent) when any step fails.
    private func rewriteSegmentAtomically() -> Bool {
        let fm = FileManager.default
        try? fm.removeItem(at: tempSegmentURL)
        var content = ""
        for record in records {
            content += recordLine(record)
            content += "\n"
        }
        guard fm.createFile(atPath: tempSegmentURL.path, contents: Data(content.utf8)) else {
            MonitaLog.debug("queue compaction skipped, temp segment not writable")
            return false
        }
        if let handle = try? FileHandle(forWritingTo: tempSegmentURL) {
            try? handle.synchronize()
            try? handle.close()
        }
        // rename(2) atomically replaces the segment; a crash strictly before
        // this point leaves the old segment plus acks as the source of truth.
        guard rename(tempSegmentURL.path, segmentURL.path) == 0 else {
            MonitaLog.debug("queue compaction skipped, segment rename failed")
            try? fm.removeItem(at: tempSegmentURL)
            return false
        }
        // Only after the new segment is durable do the acks become obsolete.
        // A crash before this delete leaves stale acks whose ids match no
        // record in the new segment, which is harmless on the next load.
        try? fm.removeItem(at: acksURL)
        return true
    }

    private func prepareDirectory() {
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            var url = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? url.setResourceValues(values)
        } catch {
            MonitaLog.error("queue directory unavailable: \(error.localizedDescription)")
        }
    }

    private func loadAndCompact() {
        // A leftover temp file means a compaction never reached its rename:
        // the segment and acks files are authoritative, the temp is discarded.
        try? FileManager.default.removeItem(at: tempSegmentURL)
        var acked = Set<String>()
        if let acksText = try? String(contentsOf: acksURL, encoding: .utf8) {
            for line in acksText.split(separator: "\n") {
                if case .object(let o)? = JSONParser.parse(String(line)),
                   case .string(let id)? = o["ack"] {
                    acked.insert(id)
                }
            }
        }
        var loaded: [Record] = []
        if let text = try? String(contentsOf: segmentURL, encoding: .utf8) {
            for line in text.split(separator: "\n") {
                guard case .object(let o)? = JSONParser.parse(String(line)),
                      case .string(let id)? = o["id"],
                      case .string(let body)? = o["b"] else {
                    continue
                }
                guard !acked.contains(id) else { continue }
                var count = 1
                if case .int(let n)? = o["n"] {
                    count = Int(n)
                }
                loaded.append(Record(id: id, eventCount: count, body: Data(body.utf8)))
            }
        }
        records = loaded
        totalEvents = records.reduce(0) { $0 + $1.eventCount }
        totalBytes = records.reduce(0) { $0 + $1.body.count }
        deadBytes = 0
        if records.isEmpty {
            resetFiles()
        } else {
            // Startup compaction uses the same crash atomic rewrite.
            _ = rewriteSegmentAtomically()
        }
        enforceCaps()
    }

    private func recordLine(_ record: Record) -> String {
        let bodyText = String(data: record.body, encoding: .utf8) ?? ""
        var object = JSONObject()
        object["id"] = .string(record.id)
        object["n"] = .int(Int64(record.eventCount))
        object["b"] = .string(bodyText)
        return JSONValue.object(object).serialized()
    }

    private func appendLine(_ line: String, to url: URL) {
        let data = Data((line + "\n").utf8)
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
            return
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            MonitaLog.debug("queue append failed: \(error.localizedDescription)")
        }
    }

    private func resetFiles() {
        let fm = FileManager.default
        try? fm.removeItem(at: segmentURL)
        try? fm.removeItem(at: acksURL)
        try? fm.removeItem(at: tempSegmentURL)
    }
}
