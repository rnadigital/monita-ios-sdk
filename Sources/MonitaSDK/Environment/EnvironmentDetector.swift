//  Copyright RNA Digital PTY LTD

import Foundation

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppTrackingTransparency)
import AppTrackingTransparency
#endif

/// Builds the monita_env snapshot for mobile: vendor and CMP SDK presence via
/// class checks (never behavior, never per user detail), app and OS versions,
/// coarse device model, SDK version, and the ATT authorization status. The
/// snapshot ships as a monita_env event with vendor name "Monita", matching
/// the reference's environment event naming, and re-sends only when the
/// snapshot changes or a new session begins.
enum EnvironmentDetector {

    /// Vendor and analytics SDK detection: display name to Objective C
    /// visible class names (any hit counts as present).
    static let vendorSDKClasses: [(String, [String])] = [
        ("firebase_analytics", ["FIRAnalytics", "FIRApp"]),
        ("facebook", ["FBSDKAppEvents", "FBSDKApplicationDelegate"]),
        ("adjust", ["ADJAdjust", "Adjust"]),
        ("appsflyer", ["AppsFlyerLib"]),
        ("branch", ["Branch", "BranchSDK.Branch"]),
        ("amplitude", ["Amplitude", "AMPClient"]),
        ("mixpanel", ["Mixpanel", "MPMixpanel"]),
        ("segment", ["SEGAnalytics", "Segment.Analytics"]),
        ("braze", ["Appboy", "BrazeKit.Braze"]),
        ("onesignal", ["OneSignal"]),
        ("tealium", ["Tealium", "TEALTealium"]),
        ("adobe", ["AEPMobileCore", "ACPCore", "ADBMobile"]),
        ("kochava", ["KVATracker", "KochavaTracker"]),
        ("singular", ["Singular"]),
    ]

    /// CMP SDK detection, presence and nothing else.
    static let cmpSDKClasses: [(String, [String])] = [
        ("onetrust", ["OTPublishersHeadlessSDK", "OTSDK"]),
        ("didomi", ["Didomi", "Didomi.Didomi"]),
        ("usercentrics", ["UsercentricsSDK", "UsercentricsCore.UsercentricsSDK", "UCUsercentrics"]),
        ("sourcepoint", ["SPConsentManager", "SPTCFConsent"]),
        ("trustarc", ["TRUSTeCMP", "TrustArcSDK"]),
        ("cookiebot", ["CookiebotSDK", "Cookiebot"]),
    ]

    static func snapshot(hasTCFString: Bool, sdkVersion: String) -> JSONObject {
        var env = JSONObject()
        var sdks: [JSONValue] = []
        for (name, classNames) in vendorSDKClasses where anyClassPresent(classNames) {
            var entry = JSONObject()
            entry["name"] = .string(name)
            entry["version"] = .null
            sdks.append(.object(entry))
        }
        var cmp: [JSONValue] = []
        for (name, classNames) in cmpSDKClasses where anyClassPresent(classNames) {
            var entry = JSONObject()
            entry["name"] = .string(name)
            entry["version"] = .null
            cmp.append(.object(entry))
        }
        env["sdks"] = .array(sdks)
        env["cmp"] = .array(cmp)
        env["tcf"] = .bool(hasTCFString)
        env["app"] = appVersion().map { JSONValue.string($0) } ?? .null
        env["build"] = appBuild().map { JSONValue.string($0) } ?? .null
        env["os"] = .string(Platform.osVersionString())
        env["model"] = .string(Platform.deviceModel())
        env["sdk"] = .string(sdkVersion)
        env["att"] = .string(attStatus())
        return env
    }

    private static func anyClassPresent(_ names: [String]) -> Bool {
        names.contains { NSClassFromString($0) != nil }
    }

    private static func appVersion() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private static func appBuild() -> String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    static func attStatus() -> String {
        #if canImport(AppTrackingTransparency)
        if #available(iOS 14, macOS 11, *) {
            switch ATTrackingManager.trackingAuthorizationStatus {
            case .authorized: return "authorized"
            case .denied: return "denied"
            case .restricted: return "restricted"
            case .notDetermined: return "not_determined"
            @unknown default: return "unknown"
            }
        }
        return "unavailable"
        #else
        return "unavailable"
        #endif
    }
}

/// Platform facts used in the envelope and environment snapshot.
enum Platform {

    /// The `rl` envelope value, e.g. "ios 17.5".
    static func osVersionString() -> String {
        #if canImport(UIKit) && !os(watchOS)
        return "ios \(UIDevice.current.systemVersion)"
        #else
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let text = v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
        #if os(macOS)
        return "macos \(text)"
        #else
        return "ios \(text)"
        #endif
        #endif
    }

    /// Coarse hardware model identifier, e.g. "iPhone15,3". Not a user
    /// identifier.
    static func deviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        let model = mirror.children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else { return }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return model.isEmpty ? "unknown" : model
    }

    static func bundleIdentifier() -> String {
        Bundle.main.bundleIdentifier ?? "unknown.bundle"
    }

    /// The `av` envelope value: marketing version plus build number joined
    /// with "+", e.g. "1.4.2+387". When only one of the two Info.plist values
    /// exists, the version ships alone and a lone build ships as "+build".
    /// Nil when the bundle carries neither (tests without a host app); the
    /// field is then omitted from the envelope.
    static func appVersionString() -> String? {
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        let build = (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String)
            .flatMap { $0.isEmpty ? nil : $0 }
        switch (version, build) {
        case let (v?, b?): return "\(v)+\(b)"
        case let (v?, nil): return v
        case let (nil, b?): return "+\(b)"
        default: return nil
        }
    }
}
