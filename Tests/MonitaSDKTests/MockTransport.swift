//  Copyright RNA Digital PTY LTD

import Foundation
@testable import MonitaSDK

/// Scriptable transport for tests. Routes by URL substring; records every
/// request it sees.
final class MockTransport: HTTPTransport, @unchecked Sendable {

    struct Response {
        var status: Int?
        var headers: [String: String] = [:]
        var body: Data?
    }

    struct Seen {
        let url: String
        let method: String
        let body: Data?
        let headers: [String: String]
    }

    private let lock = NSLock()
    private var routes: [(String, () -> Response)] = []
    private var seen: [Seen] = []

    func route(_ substring: String, _ response: @escaping () -> Response) {
        lock.lock()
        routes.append((substring, response))
        lock.unlock()
    }

    var requests: [Seen] {
        lock.lock()
        defer { lock.unlock() }
        return seen
    }

    func requests(matching substring: String) -> [Seen] {
        requests.filter { $0.url.contains(substring) }
    }

    func perform(
        _ request: URLRequest,
        completion: @escaping @Sendable (Int?, [String: String], Data?) -> Void
    ) {
        let url = request.url?.absoluteString ?? ""
        var headers: [String: String] = [:]
        for (k, v) in request.allHTTPHeaderFields ?? [:] {
            headers[k.lowercased()] = v
        }
        lock.lock()
        seen.append(Seen(url: url, method: request.httpMethod ?? "GET", body: request.httpBody, headers: headers))
        let handler = routes.first { url.contains($0.0) }?.1
        lock.unlock()
        let response = handler?() ?? Response(status: nil)
        completion(response.status, response.headers, response.body)
    }
}
