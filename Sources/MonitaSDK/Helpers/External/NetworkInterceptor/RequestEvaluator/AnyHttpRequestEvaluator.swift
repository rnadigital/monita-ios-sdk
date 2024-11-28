//
//  AnyHttpRequestEvaluator.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public class AnyHttpRequestEvaluator: RequestEvaluator {
    
    public init(){}
    
    public func isActionAllowed(urlRequest: URLRequest) -> Bool {
        guard let scheme = urlRequest.url?.scheme else {
            return false
        }
        if ["https", "http"].contains(scheme) {
            return true
        }
        return false
    }
}
