//
//  AlternateDomainRequestRedirector.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public class AlternateDomainRequestRedirector: RedirectableRequestHandler {
    
    let domainURL: URL
    
    public init(domainURL: URL){
        self.domainURL = domainURL
    }
    
    public func redirectedRequest(originalUrlRequest: URLRequest) -> URLRequest {
        let redirectedRequest = URLRequestFactory().createURLRequest(originalUrlRequest: originalUrlRequest, url: self.domainURL)
        return redirectedRequest
    }
}
