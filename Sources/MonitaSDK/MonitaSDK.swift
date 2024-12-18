// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import UIKit


public class MonitaSDK: NSObject {
    internal static let logger = MonitaLogger(tagName: "Monita")

    public static let sdk = "ios"

    // please update to match the release version
    public static let sdkVersion = "1.3.0"


    private var mainInstance: MonitaInstance?

    static let shared = MonitaSDK()
    let task = URLSession.shared
    private var serverURL: URL?
    // https://storage.googleapis.com/cdn-monita-dev/custom-config/$token.json?v=$unixTime
    private var configURL: URL {
        let unixTime = "\(Int(Date().timeIntervalSince1970))"
        return URL(string: "https://storage.googleapis.com/cdn-monita-dev/custom-config/\(token).json?v=\(unixTime)")!
    }

    private static let fetchInterval: TimeInterval = 5 * 24 * 60 * 60 // 5 days in seconds
    private static let lastFetchDateKey = "LastFetchDate"
    var token: String = ""
    var fetchLocally = false
    var batchSize: Int = 5
    var enableLogger: Bool = false
    var cid: String = ""
    // Call this method in AppDelegate's didFinishLaunchingWithOptions
    public static func configure(fetchLocally: Bool = false, enableLogger: Bool, batchSize: Int, cid: String, appVersion: String) {
        MonitaSDK.shared.fetchLocally = fetchLocally
        guard let token = Bundle.main.infoDictionary?["MonitaSDKToken"] as? String else {
            UIApplication.showAlert(message: "Token not available in plist file")
            return
        }
        MonitaSDK.shared.token = token
        MonitaSDK.shared.batchSize = batchSize
        MonitaSDK.shared.cid = cid
        MonitaSDK.shared.enableLogger = enableLogger
        // Register the URL Protocol
        UserDefaults.standard.setVal(value: [], key: .requestListCall)
        UserDefaults.standard.setVal(value: [], key: .requestList)
        checkAndFetchConfiguration()
        
        
    }
//    func configuration() -> MonitaConfig {
//        return mainInstance!.config.endpoint
//    }

    func delay(_ delay: Double, closure: @escaping () -> Void) {
        let when = DispatchTime.now() + delay
        DispatchQueue.main.asyncAfter(deadline: when, execute: closure)
    }

    // Check if it's time to fetch the configuration and do it if needed
    private static func checkAndFetchConfiguration() {
        let userDefaults = UserDefaults.standard

        // Get the last fetch date from UserDefaults
        let lastFetchDate = userDefaults.object(forKey: lastFetchDateKey) as? Date
        let currentDate = Date()
//
//        if let lastFetchDate = lastFetchDate, currentDate.timeIntervalSince(lastFetchDate) < fetchInterval {
//            // No need to fetch the configuration yet
//            return
//        }

        // Fetch the configuration from the server
        MonitaSDK.shared.fetchConfiguration()

        // Update the last fetch date in UserDefaults
        userDefaults.set(currentDate, forKey: lastFetchDateKey)
    }

    // Fetch configuration from the server
    private func fetchConfiguration() {
        task.dataTask(with: configURL) { data, _, error in
            if let error = error {
                MonitaSDK.logger.debug(message: MonitaMessage.message("Loading from local"))
                self.fetchConfigurationLocally()
                return
            }

            guard let data = data else {
                MonitaSDK.logger.debug(message: MonitaMessage.message("Loading from local"))
                self.fetchConfigurationLocally()
                return
            }

            let config = RequestManager.shared.loadConfiguration(from: data)
            if config == nil {
                MonitaSDK.logger.debug(message: MonitaMessage.message("\nStep 1:\nConfig loading failed from monita server"))
                self.fetchConfigurationLocally()
            } else {
                MonitaSDK.logger.debug(message: MonitaMessage.message("\nStep 1:\nConfig file loaded from monita server:\n\(String(data: data, encoding: .utf8)!)"))
                MonitaSDK.shared.start()
            }
            if self.fetchLocally {
                MonitaSDK.logger.debug(message: MonitaMessage.message("Loading from local"))
                self.fetchConfigurationLocally()
            }
            
        }.resume()
    }

    func fetchConfigurationLocally() {
//        guard let bundle = Bundle(identifier: Constant.bundle), let url = bundle.url(forResource: "AppGlobalConfigNew", withExtension: "json") else {
//            print("Failed to find AppGlobalConfig.json in bundle.")
//            return
//        }
        
        guard let data = jsonFIle.data(using: .utf8) else {
            return
        }
        MonitaSDK.logger.debug(message: MonitaMessage.message("Step 1:\nConfiguration Detail"))
        RequestManager.shared.loadConfiguration(from: data)
        MonitaSDK.shared.start()
        
    }

    public static func getConfigList() -> String {
        var string = ""
        let vendors = RequestManager.shared.configuration?.vendors ?? []

        for vendor in vendors {
            string.append("Name: \(vendor.vendorName ?? "")\n")
            string.append("Patterns: \(vendor.urlPatternMatches ?? [])\n\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }

    public static func getInterceptedRequestList() -> String {
        var string = ""

        let lists = UserDefaults.standard.getVal(key: .requestList) as? [Parameter] ?? []

        for list in lists where list["filtered"] as? Bool ?? false {
            var requestToSend = list
            let name = requestToSend["name"] as? String ?? ""
            requestToSend.removeValue(forKey: "vendor")
            requestToSend.removeValue(forKey: "name")
            requestToSend.removeValue(forKey: "filtered")
            string.append("Vendor:\(name)\n")
            string.append("\(requestToSend)\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }

    public static func getInterceptedRequestListAll() -> String {
        var string = ""
        var lists = UserDefaults.standard.getVal(key: .requestList) as? [Parameter] ?? []

        for list in lists {
            var requestToSend = list
            let name = requestToSend["name"] as? String ?? ""
            requestToSend.removeValue(forKey: "vendor")
            requestToSend.removeValue(forKey: "name")
            requestToSend.removeValue(forKey: "filtered")
            string.append("Vendor:\(name)\n")
            string.append("\(requestToSend)\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }
}
extension MonitaSDK {
    func start() {
        initialize(
            tp_id: token,
            environment: "UAT",
            sourceAlias: "ios",
            debug: enableLogger,
            endpoint: "https://dev-stream.getmonita.io/api/v1/",
            configEndpoint: "https://dev-stream.getmonita.io/api/v1/"
        )
    }
    @discardableResult
    func initialize(
        tp_id: String,
        environment: String,
        sourceAlias: String,
        debug: Bool,
        endpoint: String,
        configEndpoint: String) -> MonitaInstance?
    {
        if mainInstance != nil {
            return mainInstance
        }

        if debug {
            MonitaSDK.logger.enableLogging()
        }
        
        let config = MonitaConfig(
            tp_id: tp_id,
            environment: environment,
            debug: debug,
            endpoint: endpoint,
            configEndpoint: configEndpoint
        )

        // Start
        if let instance = MonitaInstance(config: config) {
            mainInstance = instance
            mainInstance?.start()
            MonitaSDK.logger.debug(message: MonitaMessage.message("Monita v\(MonitaSDK.sdkVersion) started"))
        } else {
            MonitaSDK.logger.debug(message: MonitaMessage.message("Monita start failed"))
        }
        
        return mainInstance
    }
}
let jsonFIle = """
{
  "monitoringVersion": "23",
  "vendors": [
    {
      "vendorName": "Google Firebase",
      "urlPatternMatches": [
        "fcm.googleapis.com",
        "firebase.com",
        "firebase.google.com",
        "firebase.googleapis.com",
        "firebaseapp.com",
        "firebaseappcheck.googleapis.com",
        "firebasedynamiclinks-ipv4.googleapis.com",
        "firebasedynamiclinks-ipv6.googleapis.com",
        "firebasedynamiclinks.googleapis.com",
        "firebaseinappmessaging.googleapis.com",
        "firebaseinstallations.googleapis.com",
        "firebaseio.com",
        "firebaselogging-pa.googleapis.com",
        "firebaselogging.googleapis.com",
        "firebaseperusertopics-pa.googleapis.com",
        "firebaseremoteconfig.googleapis.com",
        "app-analytics-services",
      ],
      "eventParamter": "commerce.items[0].itemNumber",
      "execludeParameters": [
        "quantity"
      ],
      "filters": [
        {
          "key": "itemNumber",
          "op": "eq",
          "val": [
            "ABC123"
          ]
        },
        {
          "key": "quantity",
          "op": "ne",
          "val": [
            "2.0"
          ]
        },
        {
          "key": "itemName",
          "op": "ne",
          "val": [
            "Adidas"
          ]
        }
      ],
      "filtersJoinOperator": "OR"
    },
    {
      "vendorName": "Facebook (Meta Pixel)",
      "urlPatternMatches": [
        "facebook",
        "graph.facebook"
      ],
      "eventParamter": "event-ev1",
      "execludeParameters": [],
      "filters": []
    },
    {
      "vendorName": "Google AdWords",
      "urlPatternMatches": [
        "app-analytics",
        "googleadservices.com",
        "googleads.g.doubleclick.net",
        "pagead2.googleadservices"
      ],
      "eventParamter": "label",
      "execludeParameters": [],
      "filters": []
    },
    {
      "vendorName": "Adobe Analytics",
      "urlPatternMatches": [
        "assets.adobedtm"
      ],
      "eventParamter": "events",
      "execludeParameters": [],
      "filters": []
    }
  ]
}

"""
