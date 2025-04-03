//
//  UIApplicationExtension.swift
//  AppGlobaliOS
//
//  Created by Coderon 14/09/24.
//

import UIKit
public extension UIApplication {

    class func getTopMostViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        if var topController = keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        } else {
            return nil
        }
    }
    class func showAlert(title: String = "", message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        DispatchQueue.main.async {
            getTopMostViewController()?.present(ac, animated: true)
        }
    }
}
extension Dictionary {
    var jsonString:String {
        let jsonData = try? JSONSerialization.data(withJSONObject: self, options: [])
        guard jsonData != nil else {return ""}
        let jsonString = String(data: jsonData!, encoding: .utf8)
        guard jsonString != nil else {return ""}
        return jsonString!
    }
    
}
extension Array {
    var jsonString: String {
        let jsonData = try? JSONSerialization.data(withJSONObject: self, options: [])
        guard jsonData != nil else {return ""}
        let jsonString = String(data: jsonData!, encoding: .utf8)
        guard jsonString != nil else {return ""}
        return jsonString!
    }
}

extension String {
    func dictionary() -> Parameter {
        var returnValue = Parameter()
        if isEmpty {
            return returnValue
        }
        if let jsonData = data(using: .utf8) {
            do {
                // Deserialize the Data into a dictionary
                if let dictionary = try JSONSerialization.jsonObject(with: jsonData, options: []) as? Parameter {
                    
                    returnValue = dictionary
                } else {
//                    MonitaSDK.logger.debug(message: MonitaMessage.message("Failed to convert JSON string to dictionary."))
                }
            } catch {
            }
        } else {
//            MonitaSDK.logger.debug(message: MonitaMessage.message("Failed to convert string to data."))
        }
        return returnValue
    }
    func array() -> [Parameter] {
        guard let data = data(using: .utf8, allowLossyConversion: false) else { return [] }
        let value = try? JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [Parameter]
        return value ?? []
    }
}


extension Bundle {
    public var appName: String           { getInfo("CFBundleName")  }
    public var displayName: String       { getInfo("CFBundleDisplayName")}
    public var language: String          { getInfo("CFBundleDevelopmentRegion")}
    public var identifier: String        { getInfo("CFBundleIdentifier")}
    public var copyright: String         { getInfo("NSHumanReadableCopyright").replacingOccurrences(of: "\\\\n", with: "\n") }

    public var appBuild: String          { getInfo("CFBundleVersion") }
    public var appVersionLong: String    { getInfo("CFBundleShortVersionString") }

    fileprivate func getInfo(_ str: String) -> String { infoDictionary?[str] as? String ?? "⚠️" }
}

let defaultProviderDomains: Dictionary<String, String> =
[
    "google-analytics.com": "googleanalytics",
    "analytics.google.com": "googleanalytics",
    "api.segment.io": "segment",
    "segmentapi": "segment",
    "seg-api": "segment",
    "segment-api": "segment",
    "api.amplitude.com": "amplitude",
    "api2.amplitude.com": "amplitude",
    "braze.com/api": "braze",
    "braze.eu/api": "braze",
    "ping.chartbeat.net": "chartbeat",
    "api.mixpanel.com/track": "mixpanel",
    "api-eu.mixpanel.com/track": "mixpanel",
    "trk.kissmetrics.io": "kissmetrics",
    "ct.pinterest.com": "pinterest",
    "facebook.com/tr/": "facebook",
    "track.hubspot.com/__": "hubspot",
    "klaviyo.com/api/track": "klaviyo",
    "app.pendo.io/data": "pendo",
    "matomo.php": "matomo",
    "rs.fullstory.com/rec%8137": "fullstory",
    "rs.fullstory.com/rec%8193": "fullstory",
    "logx.optimizely.com/v1/events": "optimizely",
    "track.customer.io/events/": "customerio",
    "alb.reddit.com/rp.gif": "reddit",
    "px.ads.linkedin.com": "linkedin",
    "/i/adsct": "twitter",
    "bat.bing.com": "bing",
    "pdst.fm": "podsights",
    // Firebase
    "app-measurement.com": "googleanalyticsfirebase",
    "app-analytics-services.com": "googleanalyticsfirebase",
    "app-analytics-services-att.com": "googleanalyticsfirebase",
    "firebaselogging": "firebaselogging"
]
