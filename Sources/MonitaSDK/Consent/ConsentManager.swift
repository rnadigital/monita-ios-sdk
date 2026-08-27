//  Copyright RNA Digital PTY LTD

import Foundation

/// Consent string resolution for the `cn` envelope field.
///
/// Priority: a host supplied override (setConsent), then a host provider
/// closure (setConsentProvider), then the IAB strings CMP SDKs write to the
/// platform default store: IABTCF_TCString, IABGPP_HDR_GppString,
/// IABUSPrivacy_String, in that order. Re-read on every event build (cheap)
/// so CMP updates propagate; a change mid queue flushes the envelope first
/// through the batcher's shared context rule.
/// Confined to the engine's serial queue.
final class ConsentManager {
    static let tcfKey = "IABTCF_TCString"
    static let gppKey = "IABGPP_HDR_GppString"
    static let uspKey = "IABUSPrivacy_String"

    private let defaults: UserDefaults

    var override: String?
    var provider: (() -> String?)?

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func currentConsent() -> String? {
        if let override = override {
            return override
        }
        if let provider = provider, let provided = provider() {
            return provided
        }
        for key in [ConsentManager.tcfKey, ConsentManager.gppKey, ConsentManager.uspKey] {
            if let value = defaults.string(forKey: key), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    var hasTCFString: Bool {
        if let value = defaults.string(forKey: ConsentManager.tcfKey), !value.isEmpty {
            return true
        }
        return false
    }
}
