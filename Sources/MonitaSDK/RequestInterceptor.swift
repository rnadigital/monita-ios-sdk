//
//  RequestInterceptor.swift
//  AppGlobalDemo
//
//  Created by Anis Mansuri on 10/09/24.
//

import Foundation

class RequestInterceptor: URLProtocol {
    static let shared = RequestInterceptor()
    override class func canInit(with request: URLRequest) -> Bool {
        
        // Only handle HTTP and HTTPS requests
        guard let url = request.url, url.scheme == "http" || url.scheme == "https" else {
            return false
        }
       
        if url.absoluteString.contains("dev-stream.getmonita") {
            return false
        }
        
        // Save request details to UserDefaults
        let list = UserDefaults.standard.getVal(key: .requestListCall) as? [String] ?? []
        
        if list.isEmpty {
            return true
        }
        if !list.contains(url.absoluteString) {
            return true
        }
        print("Step 2")
        print("Intercepted URL")
        print(url)
        return false
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        // Mark the request as handled
        let newRequest = request
        // Intercept and handle the request here
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "Invalid URL", code: 0, userInfo: nil))
            return
        }
        var listAll = UserDefaults.standard.getVal(key: .requestListCall) as? [String] ?? []
        listAll.append(url.absoluteString)
        
        UserDefaults.standard.setVal(value: listAll, key: .requestListCall)
        
        
        // Continue loading the request
        let task = URLSession.shared.dataTask(with: newRequest) { data, response, error in
            
            // Save request details to UserDefaults
            _ = UserDefaults.standard.getVal(key: .requestList) as? [[String: Any]] ?? []
            if let error = error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else if let data = data, let response = response {
                //requestDetails["response"] = String(data: data, encoding: .utf8)
                
                self.client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .allowed)
                self.client?.urlProtocol(self, didLoad: data)
            }
            //print(requestDetails)
            self.client?.urlProtocolDidFinishLoading(self)
        }
        task.resume()
    }
    func savingData(request: URLRequest) {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: NSError(domain: "Invalid URL", code: 0, userInfo: nil))
            return
        }
        if url.absoluteString.contains("dev-stream.getmonita") {
            return
        }
        // Example: Send intercepted request details to a server
        let req = RequestManager.shared.shouldSendRequest(url: url)
        let requestDetails: [String : Any] = [
            "url": url.absoluteString,
            "method": request.httpMethod ?? "GET",
            "headers": request.allHTTPHeaderFields ?? [:],
            "body": String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
        ]
        
        var list = UserDefaults.standard.getVal(key: .requestList) as? [[String: Any]] ?? []
        list.append(requestDetails)
        UserDefaults.standard.setVal(value: list, key: .requestList)
        if req.filtered {
            print("Step 3")
            print("URL matches with Vendor pattern")
            print(requestDetails)
            // Send to your server
            self.sendToServer(requestDetails: requestDetails, vender: req.vender!)
        }
    }

    
    
    override func stopLoading() {
        // Handle any cleanup if necessary
    }
    
    private func sendToServer(requestDetails: [String: Any], vender: Vendor) {
        // Implement your server communication logic here
        
        RequestManager.shared.sendToServer(requestDetails: requestDetails, vender: vender)
    }
}


extension URLSession {
    
    static let swizzleDataTask: Void = {
        let originalSelector = #selector((URLSession.dataTask(with:completionHandler:)) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)

        let swizzledSelector = #selector((URLSession.custom_dataTask(with:completionHandler:)) as (URLSession) -> (URLRequest, @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask)
        
        guard let originalMethod = class_getInstanceMethod(URLSession.self, originalSelector),
              let swizzledMethod = class_getInstanceMethod(URLSession.self, swizzledSelector) else {
            return
        }
        
        let didAddMethod = class_addMethod(URLSession.self, originalSelector, method_getImplementation(swizzledMethod), method_getTypeEncoding(swizzledMethod))
        
        if didAddMethod {
            class_replaceMethod(URLSession.self, swizzledSelector, method_getImplementation(originalMethod), method_getTypeEncoding(originalMethod))
        } else {
            method_exchangeImplementations(originalMethod, swizzledMethod)
        }
    }()
    
    @objc func custom_dataTask(with request: URLRequest, completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void) -> URLSessionDataTask {
        // Optionally inspect or modify the request here
        //print("Intercepted request in swizzled dataTask: \(request)")
        RequestInterceptor.shared.savingData(request: request)
        // Call the swizzled implementation
        return custom_dataTask(with: request, completionHandler: completionHandler)
    }
}
