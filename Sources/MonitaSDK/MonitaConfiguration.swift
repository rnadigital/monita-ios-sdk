//
//  MonitaConfiguration.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 15.3.25..
//
import Foundation

struct MonitaConfiguration {
    
    private let defaultPOSTURLStirng = "https://dev-stream.getmonita.io/api/v1/"
    
    /// The primary endpoint for posting data to BE
    public var endpointPOSTURL: String
    
    /// Optionally, - This is for some future needs
    public var environment: String
    
    /// The maximum number of retry attempts for each request
    public var maxRetries: Int
    
    /// The base delay in seconds for the first retry, doubles each time (1, 2, 4...)
    public var baseDelay: Double
    private var token: String
    
    init(token: String = "",
         endpointPOSTURL: String? = nil,
         environment: String = "Production",
         maxRetries: Int = 3,
         baseDelay: Double = 1.0) {
        if let endpointPOSTURL {
            self.endpointPOSTURL = endpointPOSTURL
        } else {
            self.endpointPOSTURL = defaultPOSTURLStirng
        }
        self.token = token
        self.environment = environment
        self.maxRetries = maxRetries
        self.baseDelay = baseDelay
    }
    
    public func vendorsURL(_ useRefresh: Bool = false) -> URL? {
        let refresh = useRefresh ? "1" : "0"
        let unixTime = "\(Int(Date().timeIntervalSince1970))"
        return URL(string: "https://storage.googleapis.com/cdn-monita-dev/custom-config/\(token).json?v=\(unixTime)&monitarefresh=\(refresh)")
    }
}
