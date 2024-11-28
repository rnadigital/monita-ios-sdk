//
//  ConsoleLoggerSniffableRequestHandler.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public enum ConsoleLoggingMode {
    case print, nslog
}

public class ConsoleLoggerSniffableRequestHandler: SniffableRequestHandler {
    
    let loggingMode: ConsoleLoggingMode
    public init(loggingMode: ConsoleLoggingMode){
        self.loggingMode = loggingMode
    }
    
    fileprivate var requestCount: Int = 0
    public func sniffRequest(urlRequest: URLRequest) {
        requestCount = requestCount + 1
        let loggableText = "Request #\(requestCount): CURL => \(urlRequest.cURL)"
        switch self.loggingMode {
        case .nslog:
            NSLog(loggableText)
        case .print:
            print(loggableText)
        }
    }
}
