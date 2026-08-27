//  Copyright RNA Digital PTY LTD

import Foundation

/// The public entry point for the Monita SDK.
///
/// Quick start:
///
///     import MonitaSDK
///
///     Monita.configure(token: "dom_xxxxxxxxxxxxxxxxxxxxxxxx")
///
/// Every method is safe to call from any thread or queue. Monitoring is
/// passive: the SDK observes the app's own URLSession traffic and never
/// mutates, blocks, or re-issues a request.
public enum Monita {

    /// The SDK version string.
    public static var version: String { MonitaDefaults.sdkVersion }

    /// Configures the SDK reading the token from the app's Info.plist key
    /// `MonitaSDKToken`.
    public static func configure() {
        let token = Bundle.main.object(forInfoDictionaryKey: MonitaDefaults.infoPlistTokenKey) as? String ?? ""
        if token.isEmpty {
            MonitaLog.error("no MonitaSDKToken entry found in Info.plist, monitoring stays off")
            return
        }
        configure(token: token)
    }

    /// Configures the SDK with a property token.
    public static func configure(token: String) {
        configure(MonitaConfiguration(token: token))
    }

    /// Configures the SDK with full options. `collectEndpoint` and
    /// `configEndpoint` are full URLs and default to the Monita production
    /// endpoints when nil.
    public static func configure(_ configuration: MonitaConfiguration) {
        MonitaEngine.shared.configure(configuration)
    }

    /// Attaches a customer supplied user id to every payload (`cid`). Pass
    /// nil to remove it.
    public static func setCustomerId(_ id: String?) {
        MonitaEngine.shared.setCustomerId(id)
    }

    /// Overrides the SDK managed session id. Pass nil to return to the SDK
    /// managed id, which rotates after 30 minutes of inactivity.
    public static func setSessionId(_ id: String?) {
        MonitaEngine.shared.setSessionId(id)
    }

    /// Overrides consent auto detection with an explicit consent string.
    /// Pass nil to return to auto detection (IABTCF_TCString,
    /// IABGPP_HDR_GppString, IABUSPrivacy_String from UserDefaults).
    public static func setConsent(_ consent: String?) {
        MonitaEngine.shared.setConsent(consent)
    }

    /// Registers a closure that supplies the consent string dynamically. An
    /// explicit setConsent value wins over the provider.
    public static func setConsentProvider(_ provider: (@Sendable () -> String?)?) {
        MonitaEngine.shared.setConsentProvider(provider)
    }

    /// Sets the current screen name, mapped into the `u` and `p` payload
    /// fields. Pass nil to clear.
    public static func setScreen(_ name: String?) {
        MonitaEngine.shared.setScreen(name)
    }

    /// Registers a gate that runs for every outgoing event with the full
    /// payload. Return false to drop the event. Use this to wire a CMP
    /// callback when events should only flow with consent.
    public static func setEventFilter(_ filter: (@Sendable ([String: Any]) -> Bool)?) {
        MonitaEngine.shared.setEventFilter(filter)
    }

    /// Registers a resolver that names the event for a captured request
    /// before config templates run. Return nil to fall through to the
    /// configured extraction.
    public static func setEventResolver(_ resolver: (@Sendable (String, [String: Any]) -> String?)?) {
        MonitaEngine.shared.setEventResolver(resolver)
    }

    /// Sends a manual vendor event. Active only when the remote config
    /// enables manual monitoring and the vendor exists in the config.
    public static func send(vendor: String, event: String, data: [String: Any]) {
        MonitaEngine.shared.send(vendor: vendor, event: event, data: data)
    }

    /// Stops monitoring and clears all queued data. Persists across
    /// launches.
    public static func optOut() {
        MonitaEngine.shared.optOut()
    }

    /// Re-enables monitoring after optOut. Persists across launches.
    public static func optIn() {
        MonitaEngine.shared.optIn()
    }

    /// Flushes batched events to the delivery queue and attempts an upload
    /// now.
    public static func flush() {
        MonitaEngine.shared.flush()
    }

    /// Forces a config refresh, bypassing the CDN cache.
    public static func refreshConfig() {
        MonitaEngine.shared.refreshConfig()
    }

    /// Toggles verbose debug logging. Debug mode also bypasses batching, one
    /// POST per event, for troubleshooting. Default off; release builds log
    /// errors only and never log payload bodies.
    public static func setDebugLogging(_ enabled: Bool) {
        MonitaEngine.shared.setDebugLogging(enabled)
    }
}
