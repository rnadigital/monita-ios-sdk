// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation
import UIKit
extension UserDefaults {
    enum Keys: String {
        case requestListCall = "RequestListCall"
        case requestList = "RequestList"
        
    }
    func setVal(value: Any, key: Keys) {
        setValue(value, forKey: key.rawValue)
    }
    func getVal(key: Keys) -> Any? {
        return value(forKey: key.rawValue)
    }
}

public class MonitaSDK: NSObject {
    static let shared = MonitaSDK()
    let task = URLSession.shared
    private var serverURL: URL?
                                        //https://storage.googleapis.com/cdn-monita-dev/custom-config/$token.json?v=$unixTime
    private var configURL: URL {
        let unixTime = "\(Int(Date().timeIntervalSince1970))"
        return URL(string: "https://storage.googleapis.com/cdn-monita-dev/custom-config/\(token).json?v=\(unixTime)")!
    }
    private let fetchInterval: TimeInterval = 5 * 24 * 60 * 60 // 5 days in seconds
    private let lastFetchDateKey = "LastFetchDate"
    var token: String = ""
    // Call this method in AppDelegate's didFinishLaunchingWithOptions
    public static func configure() {
        if let token = Bundle.main.infoDictionary?["MonitaSDKToken"] as? String {
            MonitaSDK.shared.token = token
        } else {
            UIApplication.showAlert(message: "Token not available in plist file")
        }

        
        // Register the URL Protocol
       UserDefaults.standard.setVal(value: [], key: .requestListCall)
       let queue = DispatchQueue(label: "com.example.myqueue", qos: .userInitiated)
       
       queue.async {
           URLProtocol.registerClass(RequestInterceptor.self)
           // Perform method swizzling for URLSession
                 URLSession.swizzleDataTask
//                 URLSession.swizzleDataTaskWithURL
       }
       
       MonitaSDK.shared.checkAndFetchConfiguration()
        
    }
    func delay(_ delay: Double, closure:@escaping () -> Void) {
        let when = DispatchTime.now() + delay
        DispatchQueue.main.asyncAfter(deadline: when, execute: closure)
    }
    
    // Check if it's time to fetch the configuration and do it if needed
    private func checkAndFetchConfiguration() {
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
//
//        return
        task.dataTask(with: configURL) {  data, response, error in
            print("api called")
            if let error = error {
                print("Failed to fetch configuration: \(error)")
                self.fetchConfigurationLocally()
                return
            }
            
            guard let data = data else {
                print("No data received")
                self.fetchConfigurationLocally()
                return
            }
            
            let config = RequestManager.shared.loadConfiguration(from: data)
            if config == nil {
                self.fetchConfigurationLocally()
            }
        }.resume()
        
        
    }
    
    func fetchConfigurationLocally() {
        
        guard let bundle = Bundle(identifier: Constant.bundle),  let url = bundle.url(forResource: "AppGlobalConfigNew", withExtension: "json") else {
                print("Failed to find AppGlobalConfig.json in bundle.")
                return
            }

            do {
                // Load the file data
                let data = try Data(contentsOf: url)
                print("Step 1")
                print("Configuration Detail")
                print(String(data: data, encoding: .utf8) ?? "")
                // Decode the JSON data
                let decoder = JSONDecoder()
                RequestManager.shared.loadConfiguration(from: data)
                
            } catch {
                print("Error decoding JSON: \(error)")
                return
            }
    }
    public static func getConfigList() -> String {
        var string = ""
        let vendors = RequestManager.shared.configuration?.vendors ?? []
        
        for vendor in vendors {
            string.append("Name: \(vendor.vendorName)\n")
            string.append("Patterns: \(vendor.urlPatternMatches)\n\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }
    public static func getInterceptedRequestList() -> String {
        var string = ""
        
        let lists = UserDefaults.standard.getVal(key: .requestList) as? [[String: Any]] ?? []
        
        for list in lists where list["filtered"] as! Bool == true {
            string.append("\(list)\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }
    public static func getInterceptedRequestListAll() -> String {
        var string = ""
        var lists = UserDefaults.standard.getVal(key: .requestList) as? [[String: Any]] ?? []
        
        for list in lists {
            string.append("\(list)\n")
            string.append("---------------------------------------------\n\n")
        }
        return string
    }
}

