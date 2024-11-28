//
//  AlternateUrlRequestRedirector.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public class AlternateUrlRequestRedirector: RedirectableRequestHandler {
    
    let url: URL
    
    public init(url: URL){
        self.url = url
    }
    
    public func redirectedRequest(originalUrlRequest: URLRequest) -> URLRequest {
        let mutableRequest = (originalUrlRequest as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        mutableRequest.url = self.url
        return mutableRequest as URLRequest
    }
}
