//
//  NetworkInterceptorConfig.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public struct NetworkInterceptorConfig {
    let requestSniffers: [RequestSniffer]
    let requestRedirectors: [RequestRedirector]
    
    init(requestSniffers: [RequestSniffer] = [], requestRedirectors: [RequestRedirector] = []){
        self.requestSniffers = requestSniffers
        self.requestRedirectors = requestRedirectors
    }
}
