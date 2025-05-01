//
//  VendrosConfig.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 23.2.25..
//

// VendorsConfig.swift
import Foundation

final class VendorsConfig {
    nonisolated(unsafe) static let shared = VendorsConfig()
    private init() {}

    private(set) var vendors: [Vendor] = []

    // Example load from local JSON or a hard-coded list
    func loadFromJSON(_ data: Data) {
        do {
            let decodedResponse = try JSONDecoder().decode(MonitoringResponse.self, from: data)
            vendors = decodedResponse.vendors ?? []
            MonitaLogger.shared.debug(message: .message("Vendors Loaded successfully \(vendors)"))
        } catch {
            MonitaLogger.shared.debug(message: .message("Failed to decode vendor config: \(error)"))
        }
    }

    func matchedVendors(for urlString: String) -> [Vendor] {
        vendors.filter { vendor in
            //Substring match for Vendor URL:
            return vendor.urlPatternMatches?.contains { pattern in
                MonitaLogger.shared.debug(message: .message("\nMatching URL: \(urlString),against Pattern: \(pattern)"))
                return urlString.contains(pattern)
            } ?? false
        }
    }
}
