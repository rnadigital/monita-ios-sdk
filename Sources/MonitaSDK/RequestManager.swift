//
//  RequestManager.swift
//  AppGlobalDemo
//
//  Created by Anis Mansuri on 10/09/24.
//

import Foundation
import UIKit

class RequestManager {
    static let shared = RequestManager()
    var configuration: MonitoringResponse?

    private init() {}

    func loadConfiguration(from jsonData: Data) -> MonitoringResponse? {
        configuration = parseConfiguration(from: jsonData)
        return configuration
    }
    func parseConfiguration(from jsonData: Data) -> MonitoringResponse? {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(MonitoringResponse.self, from: jsonData)

        } catch {
            print(error)
            UIApplication.showAlert(title: "Configuration Parsing Error, Loading local",message: error.localizedDescription)
        }
        return nil
    }

    func shouldSendRequest(url: URL) -> (filtered: Bool, vender: Vendor?) {
        guard let config = configuration else { return (false, nil) }
        
        let urlString = url.absoluteString
        
        for vendor in config.vendors ?? [] {
            for pattern in vendor.urlPatternMatches ?? [] {
                if urlString.contains(pattern) {
                    return (true, vendor)
                }
            }
        }
        
        return (false, nil)
    }

    func sendToServer(requestDetails: [String: Any], vender: Vendor) {

        // Define the URL
        guard let url = URL(string: "https://dev-stream.getmonita.io/api/v1/") else {
            print("Invalid URL")
            return
        }

        // Create the URLRequest object
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let venderName = vender.vendorName ?? ""
        let bundle = Bundle.main
           
           // Retrieve the version number
        //let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let timestamp = Date().timeIntervalSince1970.description
       
        //let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let urlToSend = requestDetails["url"] as? String ?? ""
        let methodToSendt = requestDetails["method"] as? String ?? ""
        var requestToSend = requestDetails
        requestToSend.removeValue(forKey: "vendor")
        requestToSend.removeValue(forKey: "filtered")

        //mv: SDK Version
        var frameworkVersion = "1.0"
        if let frameworkBundle = Bundle(identifier: Constant.bundle),
           let infoDictionary = frameworkBundle.infoDictionary {
            frameworkVersion = infoDictionary["CFBundleShortVersionString"] as? String ?? ""
        }
        let mainBundle = Bundle.main
           
           // Retrieve the bundle identifier from the host app's bundle
        let bundleIdentifier = mainBundle.bundleIdentifier ?? ""
        var dtValues = ""
        var event = ""
        do {
            // Convert array to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: [requestDetails], options: .prettyPrinted)

            // Convert JSON data to a string (for display or logging)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
                dtValues = jsonString
                if dtValues.contains(vender.eventParamter ?? "") {
                    event = vender.eventParamter ?? ""
                }
            }
        } catch {
            print("Error converting array to JSON: \(error.localizedDescription)")
        }
        
        // Define the JSON payload
        let payload: [String: Any] = [
            "t": "fe041147-0600-48ad-a04e-d3265becc4eb",
            "dm": "app",
            "mv": frameworkVersion,
            "sv": systemVersion,
            "tm": timestamp,
            "e": event,
            "vn": venderName,
            "st": "success",
            "m": methodToSendt,
            "vu": urlToSend,
            "u": bundleIdentifier,
            "p": "",
            "dt": [requestDetails],
            "s": "ios-sdk",
            "rl": frameworkVersion,
            "env": "production",
            "et": "1",
            "vid": "1",
            "cn": "",
            "sid": "",
            "cid": "",
            "ev": ""
        ]
        print("Step 4")
        print("Request Sending to server")
        print(payload)

        // Convert the payload to JSON data
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])
        } catch {
            print("Error serializing JSON: \(error)")
            return
        }

        // Create a URLSession data task
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error)")
                return
            }

            // Check for valid response and data
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                print("Invalid response or data")
                return
            }
            print("Step 5")
            print("HttpResponse StatusCode")
            print(httpResponse.statusCode)
            

            // Handle the response data
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response data:\n\(responseString)")
            }
        }

        // Start the data task
        task.resume()

    }
    
}
/*
t: User-provided token
dm: Deployment method. "app" for SDK based deployments
mv: SDK Version
tm: Unix time in seconds with milliseconds (optional) as decimals
e: Vendor Event. The event is evaluated in the following order:
SDK config: event evaluation function (future release)
Vendor event field in Deployment config eventParameter
event parameter value if the key exists
ev parameter value if the key exists

vn: Vendor name (case senstive and with spaces preserved)
st: tag status (can we get HTTP call status? 200) If so, value is either success or failed
m: HTTP method
vu: captured HTTP call endpoint URL
u: App ID
p: App area (future release) or NULL if not provided
dt: Payload content as JSON in Array, so top level of JSON is Array of payload objects. This si useful where calls and payloads are batched
s: System : android-sdk or ios-sdk
rl: Release aka SDK version number
env: Default "production". Can be user configured in future releases
do: Host app version
et: executon time in seconds, or 0
vid: hard-coded "1"
cn: Consent string value
sid: Session ID. SDK generated by default or can be overwritten in SDK config by a dynamic evaluation function
cid: Customer ID. null or SDK generated by default or can be overwritten in SDK config by a dynamic evaluation function
*/
