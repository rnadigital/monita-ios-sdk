//
//  NetShearsInterceptorDelegate.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 23.2.25..
//

import Foundation
import NetShears

final class NetShearsInterceptorDelegate: RequestBroadcastDelegate {
    
    // Singleton style for testing purposes I would personaly avoid using in not necessary.
    nonisolated(unsafe) static let shared = NetShearsInterceptorDelegate()
    private init() {}
    // Data Entry point
    func newRequestArrived(_ request: NetShearsRequestModel) {
        
        guard request.code != 0 else { return }
        
        let localURL = request.url
            let localMethod = request.method
            let localCode = request.code
            let localHeaders = request.headers
            let localBody = request.httpBody
            let localResponse = request.dataResponse

            Task.detached(priority: .userInitiated) { [localURL, localMethod, localCode, localHeaders, localBody, localResponse] in
                await NetShearsInterceptorDelegate.processRequest(
                    url: localURL,
                    method: localMethod,
                    code: localCode,
                    headers: localHeaders,
                    requestBody: localBody,
                    responseBody: localResponse
                )
            }
    }
    
    // Proecessing the request.
    private nonisolated static func processRequest(
        url: String,
        method: String,
        code: Int,
        headers: [String: String],
        requestBody: Data?,
        responseBody: Data?
    ) async {

        // Match the vendors by URL pattern
        let matchedVendors = VendorsConfig.shared.matchedVendors(for: url)
            guard !matchedVendors.isEmpty else {
                MonitaLogger.shared.debug(message: .message("No Vendors Detected matching the URL."))
                return
            }

            // Build a record (requestDetail) for filter checking
            let method = method
            let statusCode = code
            let headers = headers
            let requestBody = requestBody
            let responseBody = responseBody
            
            var requestDetail: Parameter = [
                "url": url,
                "method": method,
                "statusCode": "\(statusCode)"
            ]
            if let bodyData = requestBody,
               let bodyString = String(data: bodyData, encoding: .utf8) {
                requestDetail["body"] = bodyString
            }
            if let respData = responseBody,
               let respString = String(data: respData, encoding: .utf8) {
                requestDetail["responseBody"] = respString
            }

            // For each vendor individually, run filter checks
            for vendor in matchedVendors {
                // FilterManager Further filters Vendors.
                let pass = FilterManager.checkPassOnFilters(data: requestDetail, vendor: vendor)
                if pass {
                    MonitaLogger.shared.debug(message: .message("Matched Vendor has passed filtering."))
                    // Create a single-vendor InterceptedRequest (only this vendor)
                    let intercepted = InterceptedRequest(
                        vendors: [vendor],  // <— Only one vendor at a time
                        url: url,
                        method: method,
                        statusCode: statusCode,
                        headers: headers,
                        body: requestBody,
                        responseBody: responseBody
                    )

                    // Store it.
                    await InterceptedRequestStore.shared.add(intercepted)
                }
            }
        }
    
}
