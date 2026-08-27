//  Copyright RNA Digital PTY LTD

import Foundation

/// Session id management, parity with the reference's getmse: an SDK
/// generated UUID that rotates after 30 minutes of inactivity or app
/// background. The id and last activity timestamp persist so a quick relaunch
/// keeps the session. A host supplied id (setSessionId) always wins until
/// cleared. Confined to the engine's serial queue.
final class SessionManager {
    static let rotationSeconds = 1800.0

    private let defaults: UserDefaults
    private let now: () -> Double
    private static let sidKey = "monita_sid"
    private static let touchKey = "monita_mst"

    var overrideId: String?

    init(defaults: UserDefaults, now: @escaping () -> Double) {
        self.defaults = defaults
        self.now = now
    }

    /// Returns the current session id, rotating it when the inactivity gap
    /// exceeds 30 minutes, and touches the activity timestamp.
    func currentSessionId() -> String {
        if let overrideId = overrideId {
            return overrideId
        }
        let time = now()
        var sid = defaults.string(forKey: SessionManager.sidKey)
        let lastTouch = defaults.double(forKey: SessionManager.touchKey)
        if sid == nil || lastTouch <= 0 || time - lastTouch > SessionManager.rotationSeconds {
            sid = UUID().uuidString.lowercased()
            defaults.set(sid, forKey: SessionManager.sidKey)
        }
        defaults.set(time, forKey: SessionManager.touchKey)
        return sid ?? UUID().uuidString.lowercased()
    }
}

/// Install scoped visitor id: an SDK generated UUID persisted in UserDefaults.
/// Never a hardware or advertising identifier.
enum VisitorIdentity {
    private static let key = "monita_vid"

    static func visitorId(defaults: UserDefaults) -> String {
        if let existing = defaults.string(forKey: key), !existing.isEmpty {
            return existing
        }
        let fresh = UUID().uuidString.lowercased()
        defaults.set(fresh, forKey: key)
        return fresh
    }
}
