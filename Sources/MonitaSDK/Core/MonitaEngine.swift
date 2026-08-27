//  Copyright RNA Digital PTY LTD

import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// The SDK's orchestrator. All mutable state is confined to one serial
/// dispatch queue; the capture hot path only snapshots the request and hops
/// onto that queue. The class is @unchecked Sendable because every mutation
/// happens on `queue`.
final class MonitaEngine: @unchecked Sendable {

    struct Dependencies {
        var defaults: UserDefaults
        var storageDirectory: URL
        var transport: HTTPTransport
        var now: @Sendable () -> Double
        var bundleId: String
        var osVersion: String
        var installInterceptor: Bool
        var observeAppLifecycle: Bool
        var startReachability: Bool
        var environmentDelaySeconds: Double

        static func production() -> Dependencies {
            let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return Dependencies(
                defaults: .standard,
                storageDirectory: caches.appendingPathComponent("monita", isDirectory: true),
                transport: URLSessionTransport(),
                now: { Date().timeIntervalSince1970 },
                bundleId: Platform.bundleIdentifier(),
                osVersion: Platform.osVersionString(),
                installInterceptor: true,
                observeAppLifecycle: true,
                startReachability: true,
                environmentDelaySeconds: 2.5
            )
        }
    }

    enum KillState {
        case paused
        case removed
    }

    /// Pending capture: the request snapshot plus a weak reference to the
    /// task so the sweep can re-check its state before finalizing.
    private struct PendingCapture {
        let request: CapturedRequest
        let taskRef: NetworkInterceptor.WeakTaskBox?
    }

    /// Lock protected snapshot consulted on the capture hot path from any
    /// thread. When a config is loaded, tasks whose URL matches no vendor
    /// pattern pay nothing (no snapshot, no KVO); during the pre config
    /// window everything is captured for the ring buffer; when opted out or
    /// killed, nothing is registered at all.
    private final class CapturePrefilter: @unchecked Sendable {
        private let lock = NSLock()
        private var enabled = false
        private var matchStrings: [String]?
        private var internalMarkers: [String] = []

        func update(enabled: Bool, matchStrings: [String]?, internalMarkers: [String]) {
            lock.lock()
            self.enabled = enabled
            self.matchStrings = matchStrings
            self.internalMarkers = internalMarkers
            lock.unlock()
        }

        func shouldCapture(_ url: String) -> Bool {
            lock.lock()
            let enabled = self.enabled
            let matchStrings = self.matchStrings
            let internalMarkers = self.internalMarkers
            lock.unlock()
            guard enabled else { return false }
            for marker in internalMarkers where url.contains(marker) { return false }
            guard let matchStrings = matchStrings else { return true }
            if matchStrings.contains(where: { url.contains($0) }) {
                return true
            }
            MonitaLog.debug("no vendor match, skipping \(url)")
            return false
        }
    }

    static let shared = MonitaEngine(dependencies: .production())

    let queue = DispatchQueue(label: "ai.monita.sdk.engine")
    private let deps: Dependencies

    // Configured state; all access on `queue`.
    private var configuration: MonitaConfiguration?
    private var collectEndpoint = MonitaDefaults.collectEndpoint
    private var configEndpoint = ""
    private var remoteConfig: RemoteConfig?
    private var compiledMatcher: CompiledVendorMatcher?
    private let prefilter = CapturePrefilter()
    private var killState: KillState?
    private var configStore: ConfigStore?
    private var diskQueue: DiskQueue?
    private var uploader: Uploader?
    private var batcher: Batcher?
    private var consent: ConsentManager?
    private var session: SessionManager?
    private var visitorId = ""
    private var circuitBreaker: CircuitBreaker?
    private let ringBuffer = PreConfigBuffer()
    private var pending: [ObjectIdentifier: PendingCapture] = [:]
    private var reachability: Reachability?
    private var refreshTimer: DispatchSourceTimer?
    private var sweepTimer: DispatchSourceTimer?
    private var lastConfigFetch: Double = 0
    private var isForeground = true
    private var optedOut = false
    private var debugUnbatched = false
    private var environmentDelayElapsed = false
    private var screen: String?
    private var customerId: String?
    private var eventFilter: (([String: Any]) -> Bool)?
    private var eventResolver: ((String, [String: Any]) -> String?)?
    private var lifecycleObservers: [NSObjectProtocol] = []

    private static let optOutKey = "monita_opt_out"
    private static let envSnapshotKey = "monita_env_snap"
    private static let envSessionKey = "monita_env_sid"
    static let configRefreshInterval = 6.0 * 3600.0
    /// A pending task older than this is finalized with st omitted, but only
    /// once it is no longer running (long uploads and polls keep their real
    /// completion).
    static let pendingTaskTimeout = 600.0

    init(dependencies: Dependencies) {
        deps = dependencies
    }

    var isConfigured: Bool {
        queue.sync { configuration != nil }
    }

    // MARK: - Configure

    func configure(_ config: MonitaConfiguration) {
        queue.async { [weak self] in
            self?.configureOnQueue(config)
        }
    }

    private func configureOnQueue(_ config: MonitaConfiguration) {
        guard configuration == nil else {
            MonitaLog.debug("configure called more than once, ignoring")
            return
        }
        let token = config.token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            MonitaLog.error("configure called without a token, monitoring stays off")
            return
        }
        var resolved = config
        resolved.token = token
        configuration = resolved
        collectEndpoint = resolved.collectEndpoint ?? MonitaDefaults.collectEndpoint
        configEndpoint = resolved.configEndpoint ?? MonitaDefaults.configEndpoint(token: token)

        if resolved.debugLogging
            || ProcessInfo.processInfo.arguments.contains("-MonitaDebugLogging")
            || deps.defaults.bool(forKey: "MonitaDebugLogging") {
            MonitaLog.setDebugEnabled(true)
            debugUnbatched = true
        }

        optedOut = deps.defaults.bool(forKey: MonitaEngine.optOutKey)
        visitorId = VisitorIdentity.visitorId(defaults: deps.defaults)
        session = SessionManager(defaults: deps.defaults, now: deps.now)
        consent = ConsentManager(defaults: deps.defaults)
        circuitBreaker = CircuitBreaker(now: deps.now())

        let store = ConfigStore(
            directory: deps.storageDirectory.appendingPathComponent("config", isDirectory: true),
            configURL: URL(string: configEndpoint)
        )
        configStore = store
        let disk = DiskQueue(directory: deps.storageDirectory.appendingPathComponent("queue", isDirectory: true))
        diskQueue = disk
        let up = Uploader(
            queue: queue,
            transport: deps.transport,
            diskQueue: disk,
            endpoint: URL(string: collectEndpoint)
        )
        uploader = up
        let batch = Batcher(queue: queue)
        batch.isDebugUnbatched = { [weak self] in self?.debugUnbatched ?? false }
        batch.onChunk = { [weak self] body, count in
            guard let self = self, !self.optedOut, self.killState == nil else { return }
            self.diskQueue?.append(body: body, eventCount: count)
            self.uploader?.kick()
        }
        batcher = batch

        if deps.startReachability {
            let reach = Reachability()
            reach.onReachable = { [weak self] in
                self?.queue.async { self?.uploader?.networkRestored() }
            }
            reach.start()
            reachability = reach
            up.isReachable = { reach.isReachable }
        }

        switch store.persistedKillStatus {
        case "paused":
            killState = .paused
            MonitaLog.debug("kill marker present, monitoring stays paused")
        case "removed":
            killState = .removed
            MonitaLog.debug("kill marker present, monitoring stays removed")
        default:
            if let cached = store.loadCached() {
                switch cached.monitoringStatus {
                case "paused":
                    killState = .paused
                case "removed":
                    killState = .removed
                    store.wipe()
                default:
                    setRemoteConfig(cached)
                    MonitaLog.debug("starting from cached config version \(cached.monitoringVersion)")
                }
            }
        }
        updatePrefilter()

        if deps.installInterceptor {
            let prefilter = self.prefilter
            NetworkInterceptor.setHandlers(
                shouldCapture: { url in prefilter.shouldCapture(url) },
                onResume: { [weak self] event in
                    self?.queue.async { self?.handleTaskResumeOnQueue(event) }
                },
                onCompletion: { [weak self] key, status, errored in
                    self?.queue.async { self?.handleTaskCompletionOnQueue(key: key, status: status, errored: errored) }
                }
            )
            NetworkInterceptor.install()
        }

        startTimers()
        if deps.observeAppLifecycle {
            observeLifecycle()
        }
        queue.asyncAfter(deadline: .now() + deps.environmentDelaySeconds) { [weak self] in
            guard let self = self else { return }
            self.environmentDelayElapsed = true
            self.sendEnvironmentIfNeeded()
        }
        fetchConfig(force: false)
        up.kick()
        MonitaLog.debug("configured with token \(token.prefix(8))... collect \(collectEndpoint)")
    }

    private func startTimers() {
        let refresh = DispatchSource.makeTimerSource(queue: queue)
        refresh.schedule(deadline: .now() + MonitaEngine.configRefreshInterval, repeating: MonitaEngine.configRefreshInterval)
        refresh.setEventHandler { [weak self] in
            guard let self = self, self.isForeground else { return }
            self.fetchConfig(force: false)
        }
        refresh.resume()
        refreshTimer = refresh

        let sweep = DispatchSource.makeTimerSource(queue: queue)
        sweep.schedule(deadline: .now() + 30, repeating: 30)
        sweep.setEventHandler { [weak self] in
            self?.sweepPendingTasks()
        }
        sweep.resume()
        sweepTimer = sweep
    }

    private func observeLifecycle() {
        #if canImport(UIKit) && !os(watchOS)
        let center = NotificationCenter.default
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleDidEnterBackground() }
        })
        lifecycleObservers.append(center.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.handleWillEnterForeground() }
        })
        #endif
    }

    private func handleDidEnterBackground() {
        isForeground = false
        batcher?.flush()
        uploader?.kick()
    }

    private func handleWillEnterForeground() {
        isForeground = true
        if deps.now() - lastConfigFetch > MonitaEngine.configRefreshInterval {
            fetchConfig(force: false)
        }
        // Cheap re-check so environment changes made while backgrounded (for
        // example an ATT status change in Settings) re-send the snapshot.
        sendEnvironmentIfNeeded()
        uploader?.kick()
    }

    // MARK: - Config fetch

    func fetchConfig(force: Bool) {
        guard let store = configStore else { return }
        let refreshVersion = force ? (remoteConfig?.monitoringVersion ?? "0") : nil
        guard let request = store.fetchRequest(refreshVersion: refreshVersion) else {
            MonitaLog.error("config endpoint URL is invalid")
            return
        }
        lastConfigFetch = deps.now()
        deps.transport.perform(request) { [weak self] status, headers, data in
            self?.queue.async {
                self?.handleConfigResponse(status: status, headers: headers, data: data)
            }
        }
    }

    private func handleConfigResponse(status: Int?, headers: [String: String], data: Data?) {
        guard let store = configStore else { return }
        switch store.handleResponse(status: status, headers: headers, data: data) {
        case .updated(let config):
            killState = nil
            setRemoteConfig(config)
            MonitaLog.debug("config updated to version \(config.monitoringVersion)")
            drainRingBuffer()
            sendEnvironmentIfNeeded()
        case .notModified:
            if killState == .paused {
                // The stored ETag belongs to the last ACTIVE config (paused
                // bodies are never persisted), so a 304 while paused proves
                // the property serves active content again. Without this, a
                // reactivation with unchanged content would 304 forever and
                // monitoring would stay paused.
                killState = nil
                store.clearKillMarker()
                MonitaLog.debug("monitoring reactivated after pause (config validated by 304)")
            }
            if remoteConfig == nil, killState == nil, let cached = store.loadCached() {
                setRemoteConfig(cached)
                drainRingBuffer()
                sendEnvironmentIfNeeded()
            }
        case .paused:
            MonitaLog.debug("monitoring paused by kill switch")
            applyKillSwitch(.paused)
        case .removed:
            MonitaLog.debug("monitoring removed by kill switch")
            applyKillSwitch(.removed)
        case .failed:
            MonitaLog.debug("config fetch failed, keeping current config")
        }
        updatePrefilter()
    }

    /// Sets the active config and compiles the vendor matcher once.
    private func setRemoteConfig(_ config: RemoteConfig?) {
        remoteConfig = config
        compiledMatcher = config.map { CompiledVendorMatcher(vendors: $0.vendors) }
    }

    /// Publishes the current capture eligibility to the hot path prefilter.
    private func updatePrefilter() {
        var markers = [collectEndpoint, "cdn.monita.ai"]
        if !configEndpoint.isEmpty {
            markers.append(configEndpoint)
        }
        prefilter.update(
            enabled: capturingEnabled,
            matchStrings: compiledMatcher?.matchStrings,
            internalMarkers: markers
        )
    }

    private func applyKillSwitch(_ state: KillState) {
        killState = state
        setRemoteConfig(nil)
        pending.removeAll()
        ringBuffer.clear()
        batcher?.discardQueued()
        diskQueue?.clear()
        uploader?.reset()
        updatePrefilter()
    }

    // MARK: - Capture

    private var capturingEnabled: Bool {
        configuration != nil && !optedOut && killState == nil
    }

    func handleTaskResumeOnQueue(_ event: NetworkInterceptor.TaskEvent) {
        guard capturingEnabled else { return }
        guard !isInternalEndpoint(event.request.url) else { return }
        guard circuitBreaker?.tripped == false else { return }
        pending[event.taskKey] = PendingCapture(request: event.request, taskRef: event.taskRef)
    }

    func handleTaskCompletionOnQueue(key: ObjectIdentifier, status: Int?, errored: Bool) {
        guard let entry = pending.removeValue(forKey: key) else { return }
        finalize(FinalizedCapture(request: entry.request, statusCode: status, errored: errored))
    }

    private func sweepPendingTasks() {
        let now = deps.now()
        let stale = pending.filter { now - $0.value.request.timestamp > MonitaEngine.pendingTaskTimeout }
        for (key, entry) in stale {
            // A task still running keeps its real completion; only tasks that
            // are gone or no longer running finalize with st omitted.
            if let task = entry.taskRef?.task, task.state == .running {
                continue
            }
            pending.removeValue(forKey: key)
            finalize(FinalizedCapture(request: entry.request, statusCode: nil, errored: false))
        }
    }

    private func finalize(_ capture: FinalizedCapture) {
        guard capturingEnabled else { return }
        if let config = remoteConfig {
            process(capture, config: config)
        } else {
            ringBuffer.append(capture)
        }
    }

    private func drainRingBuffer() {
        guard let config = remoteConfig else { return }
        for capture in ringBuffer.drain(now: deps.now()) {
            process(capture, config: config)
        }
    }

    private func process(_ capture: FinalizedCapture, config: RemoteConfig) {
        guard let vendor = compiledMatcher?.match(url: capture.request.url) else {
            MonitaLog.debug("no vendor match for \(capture.request.url)")
            return
        }
        MonitaLog.debug("matched \(vendor.vendorName) for \(capture.request.url)")
        guard var data = BodyParser.parse(
            url: capture.request.url,
            body: capture.request.body,
            contentTypeHint: capture.request.contentType
        ) else {
            return
        }
        data["__mon_url"] = .string(capture.request.url)
        data["__mon_host"] = .string(hostOf(capture.request.url))
        data["__mon_method"] = .string(capture.request.method)
        data["vendorName"] = .string(vendor.vendorName)

        guard passesFilters(data: data, vendor: vendor) else {
            MonitaLog.debug("filters dropped \(vendor.vendorName) request")
            return
        }
        emit(
            vendor: vendor,
            data: data,
            vu: capture.request.url,
            method: capture.request.method,
            tm: capture.request.timestamp,
            status: capture.tagStatus,
            config: config
        )
    }

    private func passesFilters(data: JSONObject, vendor: VendorConfig) -> Bool {
        let wrapped = JSONValue.object(data)
        if !vendor.filterGroups.isEmpty {
            return FilterEngine.passes(wrapped, groups: vendor.filterGroups)
        }
        return FilterEngine.passes(wrapped, filters: vendor.filters)
    }

    private func emit(
        vendor: VendorConfig,
        data: JSONObject,
        vu: String,
        method: String,
        tm: Double,
        status: String?,
        config: RemoteConfig
    ) {
        // The breaker counts events that matched a vendor and passed filters,
        // mirroring the reference's sendData placement. More than 100 in a 6
        // second window turns capture off for the rest of the launch.
        guard circuitBreaker?.allow(now: deps.now()) == true else { return }
        let resolver: ((String, JSONObject) -> String?)?
        if let hostResolver = eventResolver {
            resolver = { name, object in hostResolver(name, ValueBridge.toDictionary(object)) }
        } else {
            resolver = nil
        }
        let payloads = EventBuilder.buildPayloads(
            context: sharedContext(config: config),
            vendor: vendor,
            data: data,
            vu: vu,
            method: method,
            tm: tm,
            status: status,
            hostResolver: resolver
        )
        for payload in payloads {
            if let filter = eventFilter, filter(ValueBridge.toDictionary(payload)) == false {
                MonitaLog.debug("event dropped by host event filter")
                continue
            }
            batcher?.enqueue(payload)
        }
    }

    private func sharedContext(config: RemoteConfig) -> SharedContext {
        var u = "app://\(deps.bundleId)"
        if let screen = screen, !screen.isEmpty {
            u += "/\(screen)"
        }
        return SharedContext(
            token: configuration?.token ?? "",
            mv: MonitaDefaults.sdkVersion,
            sv: config.monitoringVersion,
            u: u,
            p: screen ?? "",
            vid: visitorId,
            sid: session?.currentSessionId() ?? "",
            doValue: deps.bundleId,
            rl: deps.osVersion,
            cn: consent?.currentConsent(),
            cid: customerId
        )
    }

    private func hostOf(_ url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else { return "" }
        if let port = components.port {
            return "\(host):\(port)"
        }
        return host
    }

    private func isInternalEndpoint(_ url: String) -> Bool {
        if url.contains(collectEndpoint) { return true }
        if !configEndpoint.isEmpty, url.contains(configEndpoint) { return true }
        if url.contains("cdn.monita.ai") { return true }
        return false
    }

    // MARK: - Environment event

    private func sendEnvironmentIfNeeded() {
        guard environmentDelayElapsed, capturingEnabled, let config = remoteConfig else { return }
        let snapshot = EnvironmentDetector.snapshot(
            hasTCFString: consent?.hasTCFString ?? false,
            sdkVersion: MonitaDefaults.sdkVersion
        )
        let serialized = JSONValue.object(snapshot).serialized()
        let context = sharedContext(config: config)
        let previousSnapshot = deps.defaults.string(forKey: MonitaEngine.envSnapshotKey)
        let previousSession = deps.defaults.string(forKey: MonitaEngine.envSessionKey)
        guard serialized != previousSnapshot || context.sid != previousSession else { return }
        deps.defaults.set(serialized, forKey: MonitaEngine.envSnapshotKey)
        deps.defaults.set(context.sid, forKey: MonitaEngine.envSessionKey)
        let payload = EventBuilder.buildEnvironmentPayload(
            context: context,
            snapshot: snapshot,
            tm: deps.now()
        )
        batcher?.enqueue(payload)
        MonitaLog.debug("environment event queued")
    }

    // MARK: - Public API surface

    func setCustomerId(_ id: String?) {
        queue.async { self.customerId = id }
    }

    func setSessionId(_ id: String?) {
        queue.async { self.session?.overrideId = id }
    }

    func setConsent(_ value: String?) {
        queue.async { self.consent?.override = value }
    }

    func setConsentProvider(_ provider: (@Sendable () -> String?)?) {
        queue.async { self.consent?.provider = provider }
    }

    func setScreen(_ name: String?) {
        queue.async { self.screen = name }
    }

    func setEventFilter(_ filter: (@Sendable ([String: Any]) -> Bool)?) {
        queue.async { self.eventFilter = filter }
    }

    func setEventResolver(_ resolver: (@Sendable (String, [String: Any]) -> String?)?) {
        queue.async { self.eventResolver = resolver }
    }

    func send(vendor: String, event: String, data: [String: Any]) {
        queue.async { self.sendManualOnQueue(vendor: vendor, event: event, data: data) }
    }

    private func sendManualOnQueue(vendor vendorName: String, event: String, data userData: [String: Any]) {
        guard capturingEnabled, let config = remoteConfig else {
            MonitaLog.debug("manual send ignored, monitoring is not active")
            return
        }
        guard config.allowManualMonitoring else {
            MonitaLog.debug("manual monitoring is not enabled for this property")
            return
        }
        guard let vendor = VendorMatcher.vendorNamed(vendorName, in: config.vendors) else {
            MonitaLog.debug("manual send ignored, unknown vendor \(vendorName)")
            return
        }
        var data = JSONObject()
        data["vendorName"] = .string(vendorName)
        data["event"] = .string(event)
        if case .object(let converted) = ValueBridge.toJSONValue(userData) {
            data.merge(converted)
        }
        data["__mon_url"] = .string(collectEndpoint)
        data["__mon_host"] = .string(hostOf(collectEndpoint))
        data["__mon_method"] = .string("POST")
        guard passesFilters(data: data, vendor: vendor) else { return }
        emit(
            vendor: vendor,
            data: data,
            vu: collectEndpoint,
            method: "POST",
            tm: deps.now(),
            status: nil,
            config: config
        )
    }

    func optOut() {
        queue.async {
            self.optedOut = true
            self.deps.defaults.set(true, forKey: MonitaEngine.optOutKey)
            self.pending.removeAll()
            self.ringBuffer.clear()
            self.batcher?.discardQueued()
            self.diskQueue?.clear()
            self.uploader?.reset()
            self.updatePrefilter()
            MonitaLog.debug("opted out, queued data cleared")
        }
    }

    func optIn() {
        queue.async {
            self.optedOut = false
            self.deps.defaults.set(false, forKey: MonitaEngine.optOutKey)
            self.updatePrefilter()
            MonitaLog.debug("opted in")
        }
    }

    func flush() {
        queue.async {
            self.batcher?.flush()
            self.uploader?.kick()
        }
    }

    func refreshConfig() {
        queue.async {
            self.fetchConfig(force: true)
        }
    }

    func setDebugLogging(_ enabled: Bool) {
        MonitaLog.setDebugEnabled(enabled)
        queue.async {
            self.debugUnbatched = enabled
        }
    }

    // MARK: - Test support

    func syncForTesting() {
        queue.sync {}
    }

    func captureForTesting(url: String, method: String, body: Data?, contentType: String? = nil, status: Int?, errored: Bool = false) {
        queue.async {
            guard self.capturingEnabled, !self.isInternalEndpoint(url) else { return }
            guard self.circuitBreaker?.tripped == false else { return }
            let request = CapturedRequest(
                url: url,
                method: method,
                body: body,
                contentType: contentType,
                timestamp: self.deps.now()
            )
            self.finalize(FinalizedCapture(request: request, statusCode: status, errored: errored))
        }
    }

    var diskQueueForTesting: DiskQueue? {
        queue.sync { diskQueue }
    }

    var remoteConfigForTesting: RemoteConfig? {
        queue.sync { remoteConfig }
    }
}
