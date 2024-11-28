//
//  DomainHttpRequestEvaluator.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public class DomainHttpRequestEvaluator: RequestEvaluator {
    let domain: String
    public init(domain: String){
        self.domain = domain
    }
    
    public func isActionAllowed(urlRequest: URLRequest) -> Bool {
        guard AnyHttpRequestEvaluator().isActionAllowed(urlRequest: urlRequest) else {
            return false
        }
        guard let host = urlRequest.url?.host else {
            return false
        }
        if host == self.domain {
            return true
        }
        return false
    }
}
