//
//  RequestManager.swift
//  AppGlobalDemo
//
//  Created by Coderon 10/09/24.
//

import Foundation
import UIKit

class RequestManager {
    static let shared = RequestManager()
    var configuration: MonitoringResponse?

    private init() {}
    @discardableResult
    func loadConfiguration(from jsonData: Data) -> MonitoringResponse? {
        configuration = parseConfiguration(from: jsonData)
        return configuration
    }
    func parseConfiguration(from jsonData: Data) -> MonitoringResponse? {
        do {
            let decoder = JSONDecoder()
            return try decoder.decode(MonitoringResponse.self, from: jsonData)

        } catch {
            UIApplication.showAlert(title: "Configuration Parsing Error, Loading local",message: error.localizedDescription)
        }
        return nil
    }

    func shouldSendRequest(url: URL) -> (filtered: Bool, vendor: Vendor?) {
        guard let config = configuration else { return (false, nil) }
        
        let urlString = url.absoluteString
        
        for vendor in config.vendors ?? [] {
            let urlPatternMatches = vendor.urlPatternMatches ?? []
            for pattern in urlPatternMatches where urlString.contains(pattern) {
                return (true, vendor)
            }
        }
        return (false, nil)
    }
   
    func sendToServer(payload: Parameter, completion: @escaping (Bool) -> Void) {
       
        // Create the URLRequest object
        // Define the URL
        let url = URL(string: "https://dev-stream.getmonita.io/api/v1/")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        MonitaSDK.logger.debug(message: MonitaMessage.message("\nStep 4:\nRequest Sending to server\n\(payload)"))
        
        // Convert the payload to JSON data
        request.httpBody = try! JSONSerialization.data(withJSONObject: payload, options: [])

        // Create a URLSession data task
        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                MonitaSDK.logger.debug(message: MonitaMessage.message("Error: \(error)"))
                completion(true)
                return
            }

            // Check for valid response and data
            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let data = data else {
                return
            }
            
            MonitaSDK.logger.debug(message: MonitaMessage.message("\nStep 5:\nHttpResponse StatusCode\n\(httpResponse.statusCode)"))
            completion(true)
            // Handle the response data
            if let responseString = String(data: data, encoding: .utf8) {
            }
        }

        // Start the data task
        task.resume()

    }
    


    func checkPassOnFilters(data: Parameter, vendor: Vendor) -> Bool {
        let joinOperator = vendor.filtersJoinOperator ?? ""
        let filters = vendor.filters ?? []
        let exitImmediately = (joinOperator == "AND")
        var results: [Bool] = []
        
        for filter in filters {
            let key = filter.finalKey
            let op = filter.finalOp
            let filterValues = filter.finalVal
            var pass = true
            
            if ["eq", "contains"].contains(op) {
                let checkFn: (Any, String) -> Bool = (op == "eq") ?
                    { val, filterVal in "\(val)" == "\(filterVal)" } :
                    { val, filterVal in
                        guard let valString = val as? String else { return false }
                        return valString.contains(filterVal)
                    }
                
                let val = fillParamsFromData(key: key, data: data)
                
                pass = false
                for filterValue in filterValues {
                    
                    if checkFn(val, filterValue) {
                        pass = true
                        break
                    }
                }
                if !pass && exitImmediately {
                    return false
                }
            } else if op == "ne" {
                for filterValue in filterValues {
                    let compareVal = fillParamsFromData(key: key, data: data) as? String ?? ""
                    if compareVal == filterValue {
                        if exitImmediately {
                            return false
                        } else {
                            pass = false
                            break
                        }
                    }
                }
            } else if op == "blank" {
                let value = fillParamsFromData(key: key, data: data)
                if let valueString = value as? String, !valueString.isEmpty {
                    if exitImmediately {
                        return false
                    } else {
                        pass = false
                    }
                }
            } else if op == "not_blank" {
                let value = fillParamsFromData(key: key, data: data)
                if value == nil || (value as? String)?.isEmpty == true {
                    if exitImmediately {
                        return false
                    } else {
                        pass = false
                    }
                }
            } else if op == "exist" {
                let value = fillParamsFromData(key: key, data: data)
                if value == nil {
                    if exitImmediately {
                        return false
                    } else {
                        pass = false
                    }
                }
            } else if op == "not_exist" {
                let value = fillParamsFromData(key: key, data: data)
                if value != nil {
                    if exitImmediately {
                        return false
                    } else {
                        pass = false
                    }
                }
            }
            
            results.append(pass)
        }
        
        if exitImmediately {
            return true
        } else {
            return filters.isEmpty || results.contains(true)
        }
    }

    // Helper function to extract value from the data dictionary.
    func fillParamsFromData(key: String, data: Parameter) -> Any? {
        return data[key]
    }

    
}

extension RequestManager {
    var pendingServerReqests: [Parameter] {
        get {
            return UserDefaults.standard.getVal(key: .pendingServerReqests) as? [Parameter] ?? []
        }
        set {
            UserDefaults.standard.setVal(value: newValue, key: .pendingServerReqests)
        }
    }
    
    func savePendingServerReqest(request: Parameter) {
        var reqs = pendingServerReqests
        reqs.append(request)
        UserDefaults.standard.setVal(value: reqs, key: .pendingServerReqests)
        if reqs.count >= MonitaSDK.shared.batchSize {
            uploadRequestsSequentially()
        }
    }
    func addToBatch(requestDetail: Parameter, vendor: Vendor) {
        let vendorName = vendor.vendorName
        let bundle = Bundle.main
           
           // Retrieve the version number
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let timestamp = Date().timeIntervalSince1970.description
       
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let urlToSend = requestDetail["url"] as? String ?? ""
        let methodToSendt = requestDetail["method"] as? String ?? ""
        var requestToSend = requestDetail
        requestToSend.removeValue(forKey: "vendor")
        requestToSend.removeValue(forKey: "name")
        requestToSend.removeValue(forKey: "filtered")
        requestToSend.removeValue(forKey: "method")
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
            let jsonData = try JSONSerialization.data(withJSONObject: requestDetail, options: .prettyPrinted)

            // Convert JSON data to a string (for display or logging)
            if let jsonString = String(data: jsonData, encoding: .utf8) {
                dtValues = jsonString
                if dtValues.contains(vendor.eventParamter ?? "") {
                    event = vendor.eventParamter ?? ""
                }
            }
        } catch {
            
        }
        if let body = requestDetail["body"] as? String, let execludeParameters = vendor.execludeParameters {
            var bodyDic = body.dictionary()
            //remove excluded parameters from dt
            for excludeParameter in execludeParameters {
                bodyDic.forEach {
                    if ($0.value as? String ?? "") == excludeParameter {
                        bodyDic.removeValue(forKey: $0.key)
                    }
                }
            }
            requestToSend["body"] = bodyDic.jsonString
        }
        if !checkPassOnFilters(data: requestToSend, vendor: vendor) {
            return
        }
        
        // Define the JSON payload
        let payload: Parameter = [
            "t": MonitaSDK.shared.token,
            "dm": "app",
            "mv": frameworkVersion,
            "sv": systemVersion,
            "tm": timestamp,
            "e": event,
            "vn": vendorName ?? "",
            "st": "success",
            "m": methodToSendt,
            "vu": urlToSend,
            "u": bundleIdentifier,
            "p": "",
            "dt": [requestToSend],
            "s": "ios-sdk",
            "rl": frameworkVersion,
            "env": "production",
            "et": "1",
            "vid": "1",
            "cn": "",
            "sid": "",
            "cid": MonitaSDK.shared.cid,
            "ev": ""
        ]
        savePendingServerReqest(request: payload)
    }
    func uploadRequestsSequentially() {
        var requests = pendingServerReqests
        if requests.isEmpty { return }
        let payload = requests[0]
        sendToServer(payload: payload) { [weak self] status in
            guard let strongSelf = self else { return }
            if status {
                requests.remove(at: 0)
                strongSelf.pendingServerReqests = requests
                strongSelf.uploadRequestsSequentially()
            }
        }

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
