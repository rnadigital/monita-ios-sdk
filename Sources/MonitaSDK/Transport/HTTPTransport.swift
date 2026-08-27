//  Copyright RNA Digital PTY LTD

import Foundation

/// Minimal HTTP abstraction so config fetch and event upload are testable
/// with an injected transport. The status code is nil on transport errors.
public protocol HTTPTransport: Sendable {
    func perform(
        _ request: URLRequest,
        completion: @escaping @Sendable (Int?, [String: String], Data?) -> Void
    )
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
    }

    public func perform(
        _ request: URLRequest,
        completion: @escaping @Sendable (Int?, [String: String], Data?) -> Void
    ) {
        let task = session.dataTask(with: request) { data, response, _ in
            guard let http = response as? HTTPURLResponse else {
                completion(nil, [:], data)
                return
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let k = key as? String, let v = value as? String {
                    headers[k.lowercased()] = v
                }
            }
            completion(http.statusCode, headers, data)
        }
        task.resume()
    }
}
