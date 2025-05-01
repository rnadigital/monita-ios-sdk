// The Swift Programming Language
// https://docs.swift.org/swift-book
// re-try with expo back-off and a max re-try
////136973f0-26f5-48db-b159-a923200a7867
import Foundation
import UIKit
import NetShears

public class MonitaSDK: @unchecked Sendable {
    //    internal static let logger = MonitaLogger(tagName: "Monita") /// this needs to be verified.
    public static let shared = MonitaSDK()
    public static let sdk = "ios"
    
    // please update to match the release version
    public static let sdkVersion = "1.3.0"
    
    // Internal background queue (serial) for concurrency safety
    private let queue = DispatchQueue(label: "com.monita.sdk.queue")
    var configuration: MonitaConfiguration?
    
    private static let fetchInterval: TimeInterval = 5 * 24 * 60 * 60 // 5 days in seconds
    private var lastFetchDateKey = "LastFetchDate"
    var token: String = ""
    var fetchLocally = false
    var batchSize: Int = 5
    var enableLogger: Bool = false
    var cid: String = ""
    
    private init() { }
    
    /// Configures and starts the Monita SDK.
    ///
    /// - Parameters:
    ///   - fetchLocally: When `true`, falls back to the bundled JSON vendor configuration if the remote fetch fails. Default **false**.
    ///   - enableLogger: Toggles `MonitaLogger`; set to `true` for debug output in Xcode console. Default **true**.
    ///   - batchSize: Number of intercepted requests to cache before triggering an upload. Default **10**.
    ///   - cid: Customer‑ID.
    ///   - appVersion: Optional host‑app version to include in analytics; not used internally, but stored in payloads.
    ///   - alternativeURL: Overrides the default upload endpoint (`endpointPOSTURL`). Useful for staging or QA.
    ///   - sid: Session‑ID (`"sid"` field).
    ///   - consentString: Consent.
    ///   - maxRetries: Maximum upload attempts per payload when a request fails. Retries use exponential back‑off. Default **3**.
    ///   - baseDelay: Initial delay (seconds) for exponential back‑off. Each retry doubles this value. Default **1.0**.
    ///
    /// Call this **once**—ideally from *AppDelegate*’s
    /// `application(_:didFinishLaunchingWithOptions:)`—before network traffic starts.
    public func configure(fetchLocally: Bool = false,
                          enableLogger: Bool = true,
                          batchSize: Int = 10,
                          cid: String = "",
                          appVersion: String = "",
                          alternativeURL: String? = nil,
                          sid: String = "",
                          consentString: String = "",
                          maxRetries: Int = 3,
                          baseDelay: Double = 1.0) {
        queue.async {
            self._configure(
                fetchLocally: fetchLocally,
                enableLogger: enableLogger,
                batchSize: batchSize,
                cid: cid,
                appVersion: appVersion,
                alternativeURL: alternativeURL,
                sid: sid,
                consentString: consentString,
                maxRetries: maxRetries,
                baseDelay: baseDelay
            )
        }
    }
    
    private func _configure(
        fetchLocally: Bool,
        enableLogger: Bool,
        batchSize: Int,
        cid: String,
        appVersion: String,
        alternativeURL: String? = nil,
        sid: String,
        consentString: String,
        maxRetries: Int,
        baseDelay: Double
    ) {
        self.fetchLocally = fetchLocally
        self.enableLogger = enableLogger
        self.batchSize = batchSize
        self.cid = cid
        
        guard let tokenFromPlist = Bundle.main.infoDictionary?["MonitaSDKToken"] as? String else {
            DispatchQueue.main.async {
                print("Monita Token not available in plist file. To get a token you must sign up at getmonita.io and add a new domain for monitoring")
            }
            return
        }
        self.token = tokenFromPlist
        if enableLogger {
            MonitaLogger.shared.enableLogging()
        }
        let newURL = alternativeURL ?? nil
        configuration = MonitaConfiguration(token: tokenFromPlist, endpointPOSTURL: newURL, cid: cid, sid: sid, cn: consentString)
        RequestManager.shared.setConfiguration(configuration: configuration)
        
        checkAndFetchConfiguration()
    }
    
    public func getVendors() -> [Vendor] {
        return VendorsConfig.shared.vendors
    }
    
    
    // Check if it's time to fetch the configuration and do it if needed
    private func checkAndFetchConfiguration() {
        
        Task {
            //Fetch configuration now.
            await fetchConfiguration()
            
            // Then do repeated fetches at a set interval, e.g., every 12 hours.
            let fetchIntervalSeconds: Double = 12 * 60 * 60  // 12 hours
            while true {
                do {
                    try await Task.sleep(nanoseconds: UInt64(fetchIntervalSeconds * 1_000_000_000))
                } catch {
                    // If the Task got canceled, exit the loop
                    break
                }
                // Attempt a new fetch
                await fetchConfiguration(true)
            }
        }
    }
    
    private func fetchConfiguration( _ withRefresh: Bool = false) async {
        guard let configURL = configuration?.vendorsURL(withRefresh) else {
            // If invalid URL, fallback to local
            fetchConfigurationLocally()
            return
        }
        
        do {
            // Perform the network call using async/await
            let (data, _) = try await URLSession.shared.data(from: configURL)
            
            // If you still want to handle the response on your serial queue, wrap in a continuation:
            await withCheckedContinuation { continuation in
                self.queue.async {
                    self.handleConfigResponse(data: data, error: nil)
                    continuation.resume()
                }
            }
        } catch {
            // On error, fallback or pass the error to handleConfigResponse
            await withCheckedContinuation { continuation in
                self.queue.async {
                    self.handleConfigResponse(data: nil, error: error)
                    continuation.resume()
                }
            }
        }
    }
    
    private func handleConfigResponse(data: Data?, error: Error?) {
        if let _ = error {
            MonitaLogger.shared.debug(message: .message("Handling error - Error:\(error) -> getting Vendors locally"))
            fetchConfigurationLocally()
            return
        }
        
        guard let data = data else {
            MonitaLogger.shared.debug(message: .message("Handling error - Data nil or missing -> getting Vendors locally"))
            fetchConfigurationLocally()
            return
        }
        
        VendorsConfig.shared.loadFromJSON(data)
        MonitaSDK.startMonitoring()
        
        if fetchLocally {
            fetchConfigurationLocally()
        }
    }
    
    func fetchConfigurationLocally() {
        guard let data = jsonFIle.data(using: .utf8) else {
            return
        }
        
        VendorsConfig.shared.loadFromJSON(data)
        MonitaSDK.startMonitoring()
    }
    
    private static func startMonitoring() {
        NetShears.shared.startListener()
        NetShears.shared.startLogger()   
        RequestBroadcast.shared.setDelegate(NetShearsInterceptorDelegate.shared)
    }
    
    public static func getConfigList() -> String {
        var string = ""
        let vendors = VendorsConfig.shared.vendors
        
        for vendor in vendors {
            string.append("Name: \(vendor.vendorName ?? "")\n")
            string.append("Patterns: \(vendor.urlPatternMatches ?? [])\n\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
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
