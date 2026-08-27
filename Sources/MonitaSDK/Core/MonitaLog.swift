//  Copyright RNA Digital PTY LTD

import Foundation
import os

/// Internal logging through os.Logger (subsystem ai.monita.sdk). Release
/// default is errors only. Debug logging is opt in via
/// Monita.setDebugLogging(true), the -MonitaDebugLogging launch argument, or
/// a MonitaDebugLogging user default. Payload bodies are never logged outside
/// explicit debug level.
enum MonitaLog {
    private static let logger = Logger(subsystem: "ai.monita.sdk", category: "monita")
    private static let lock = NSLock()
    private static var debugOn = false

    static var isDebugEnabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return debugOn
    }

    static func setDebugEnabled(_ enabled: Bool) {
        lock.lock()
        debugOn = enabled
        lock.unlock()
    }

    static func debug(_ message: @autoclosure () -> String) {
        guard isDebugEnabled else { return }
        let text = message()
        logger.debug("\(text, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
