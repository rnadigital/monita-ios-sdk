//  Copyright RNA Digital PTY LTD

import Foundation

/// Initialization options for the SDK.
///
/// `collectEndpoint` is the full collect URL (default
/// https://collect.monita.ai/api/v1) and `configEndpoint` is the full config
/// JSON URL for the property (default derived from the token as
/// https://cdn.monita.ai/custom-config/{token}.json). Both exist so customers
/// running reverse proxies or legacy hosts can point the SDK at their own
/// endpoints.
public struct MonitaConfiguration: Sendable {
    public var token: String
    public var collectEndpoint: String?
    public var configEndpoint: String?
    public var debugLogging: Bool

    public init(
        token: String,
        collectEndpoint: String? = nil,
        configEndpoint: String? = nil,
        debugLogging: Bool = false
    ) {
        self.token = token
        self.collectEndpoint = collectEndpoint
        self.configEndpoint = configEndpoint
        self.debugLogging = debugLogging
    }
}

enum MonitaDefaults {
    static let collectEndpoint = "https://collect.monita.ai/api/v1"
    static let configEndpointBase = "https://cdn.monita.ai/custom-config"
    static let sdkVersion = "2.0.0"
    static let infoPlistTokenKey = "MonitaSDKToken"

    static func configEndpoint(token: String) -> String {
        "\(configEndpointBase)/\(token).json"
    }
}
