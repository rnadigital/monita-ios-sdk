//  Copyright RNA Digital PTY LTD

import Foundation
import Network

/// Thin NWPathMonitor wrapper. Reports reachability optimistically until the
/// first path update arrives so early uploads are never blocked by a slow
/// monitor start.
final class Reachability: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var reachable = true
    private var started = false

    var onReachable: (@Sendable () -> Void)?

    var isReachable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return reachable
    }

    func start() {
        lock.lock()
        let alreadyStarted = started
        started = true
        lock.unlock()
        guard !alreadyStarted else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            let nowReachable = path.status == .satisfied
            self.lock.lock()
            let wasReachable = self.reachable
            self.reachable = nowReachable
            self.lock.unlock()
            if nowReachable, !wasReachable {
                self.onReachable?()
            }
        }
        monitor.start(queue: DispatchQueue(label: "ai.monita.sdk.reachability"))
    }
}
