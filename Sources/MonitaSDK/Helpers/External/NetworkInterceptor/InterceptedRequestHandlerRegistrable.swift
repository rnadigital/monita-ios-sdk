//
//  InterceptedRequestHandlerRegistrable.swift
//  NetworkInterceptor
//
// 
//

import Foundation

public enum SniffableRequestHandlerRegistrable {
    case console(logginMode: ConsoleLoggingMode)
    case slack(slackToken: String, channel: String, username: String)
    case alternateDomain(domainURL: URL)
    case slackHook(hooksUrl: String)
    
    func requestHandler() -> SniffableRequestHandler {
        switch self {
        case .console(let loggingMode):
            return ConsoleLoggerSniffableRequestHandler(loggingMode: loggingMode)
        case .slack(let slackToken, let channel, let username):
            return SlackSniffableRequestHandler(slackToken: slackToken, channel: channel, username: username)
        case .alternateDomain(let domainURL):
            return AlternateDomainSniffableRequestHandler(domainURL: domainURL)
        case .slackHook(let hookUrl):
            return SlackHookSniffableRequestHandler(hookUrl: hookUrl)
        }
    }
}
