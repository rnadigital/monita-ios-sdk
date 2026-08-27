//  Copyright RNA Digital PTY LTD

import Foundation

/// Remote config fetch and cache. Routine fetches are plain conditional GETs
/// (ETag with If-None-Match, no cache busting parameters) so the CDN can serve
/// them. An explicit refresh appends ?v={configVersion} to punch through the
/// CDN cache. The last good config and its ETag persist on disk so a cold
/// start begins from cache instantly.
/// Confined to the engine's serial queue (completion handlers are dispatched
/// back onto it by the caller's transport wrapper in MonitaEngine).
final class ConfigStore {

    enum FetchOutcome {
        case updated(RemoteConfig)
        case notModified
        case paused
        case removed
        case failed
    }

    private let directory: URL
    private let configURL: URL?
    private var etag: String?
    private var consecutiveNotFound = 0

    private var configFile: URL { directory.appendingPathComponent("config.json") }
    private var etagFile: URL { directory.appendingPathComponent("etag.txt") }
    private var killMarkerFile: URL { directory.appendingPathComponent("kill.txt") }

    /// The persisted kill switch state ("paused" or "removed"), honored on
    /// cold start so a paused property never resumes capturing from cache.
    private(set) var persistedKillStatus: String?

    init(directory: URL, configURL: URL?) {
        self.directory = directory
        self.configURL = configURL
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
        etag = try? String(contentsOf: etagFile, encoding: .utf8)
        if let marker = try? String(contentsOf: killMarkerFile, encoding: .utf8),
           marker == "paused" || marker == "removed" {
            persistedKillStatus = marker
        }
    }

    /// Loads the cached config, if any.
    func loadCached() -> RemoteConfig? {
        guard let data = try? Data(contentsOf: configFile) else { return nil }
        return RemoteConfig.decode(data: data)
    }

    /// Builds the fetch request. `refreshVersion` is non nil only for an
    /// explicit refresh call and appends the cache busting parameter.
    func fetchRequest(refreshVersion: String?) -> URLRequest? {
        guard var url = configURL else { return nil }
        if let version = refreshVersion,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            var items = components.queryItems ?? []
            items.append(URLQueryItem(name: "v", value: version))
            components.queryItems = items
            if let busted = components.url {
                url = busted
            }
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if refreshVersion == nil, let etag = etag, !etag.isEmpty {
            request.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        return request
    }

    /// Interprets a fetch response. Two consecutive 404 or 410 results are
    /// the kill switch (treated as removed: cache wiped); a lone 404 is
    /// treated as transient (a CDN purge race must not kill monitoring). A
    /// body carrying monitoringStatus paused or removed also kills
    /// monitoring; paused keeps the cache, removed wipes it. Both persist a
    /// kill marker honored on the next cold start; any successful active
    /// config clears it.
    func handleResponse(status: Int?, headers: [String: String], data: Data?) -> FetchOutcome {
        guard let status = status else { return .failed }
        if status == 404 || status == 410 {
            consecutiveNotFound += 1
            if consecutiveNotFound < 2 {
                MonitaLog.debug("config returned \(status) once, keeping current state until confirmed")
                return .failed
            }
            wipe()
            setKillMarker("removed")
            return .removed
        }
        consecutiveNotFound = 0
        if status == 304 { return .notModified }
        guard (200..<300).contains(status), let data = data else { return .failed }
        guard let config = RemoteConfig.decode(data: data) else {
            MonitaLog.error("config decode failed, keeping cached config")
            return .failed
        }
        switch config.monitoringStatus {
        case "paused":
            setKillMarker("paused")
            return .paused
        case "removed":
            wipe()
            setKillMarker("removed")
            return .removed
        default:
            break
        }
        persist(data: data, etag: headers["etag"])
        setKillMarker(nil)
        return .updated(config)
    }

    private func persist(data: Data, etag newETag: String?) {
        try? data.write(to: configFile, options: .atomic)
        if let newETag = newETag {
            etag = newETag
            try? newETag.write(to: etagFile, atomically: true, encoding: .utf8)
        } else {
            // A 200 without an ETag invalidates the stored one; keeping it
            // would let a future 304 pin an older config.
            etag = nil
            try? FileManager.default.removeItem(at: etagFile)
        }
    }

    /// Clears the persisted kill marker (used when a 304 validates the last
    /// active config while paused, proving the property is active again).
    func clearKillMarker() {
        setKillMarker(nil)
    }

    private func setKillMarker(_ status: String?) {
        persistedKillStatus = status
        if let status = status {
            try? status.write(to: killMarkerFile, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: killMarkerFile)
        }
    }

    func wipe() {
        etag = nil
        try? FileManager.default.removeItem(at: configFile)
        try? FileManager.default.removeItem(at: etagFile)
    }
}
