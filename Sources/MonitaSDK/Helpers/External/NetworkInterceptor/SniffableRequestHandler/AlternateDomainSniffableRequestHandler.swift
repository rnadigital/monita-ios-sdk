//
//  AlternateDomainSniffableRequestHandler.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public class AlternateDomainSniffableRequestHandler: SniffableRequestHandler {

    let domainURL: URL

    public init(domainURL: URL){
        self.domainURL = domainURL
    }
    
    public func sniffRequest(urlRequest: URLRequest) {
        let alternateRequest = URLRequestFactory().createURLRequest(originalUrlRequest: urlRequest, url: self.domainURL)
        NetworkInterceptor.shared.refireURLRequest(urlRequest: alternateRequest as URLRequest)
    }
    
}
