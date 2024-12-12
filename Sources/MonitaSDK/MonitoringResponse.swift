//
//  MonitoringResponse.swift
//  AppGlobaliOS
//
//  Created by Coderon 11/09/24.
//

import Foundation


// MARK: - Root Model
struct MonitoringResponse: Codable {
    let monitoringVersion: String
    let vendors: [Vendor]?
}

// MARK: - Vendor Model
struct Vendor: Codable {
    let vendorName: String?
    let urlPatternMatches: [String]?
    let eventParamter: String?
    let execludeParameters: [String]?
    let filters: [Filter]?
    let filtersJoinOperator: String?
    var isFiltersJoinOperatorAvailable: Bool {
        if let filtersJoinOperator = filtersJoinOperator {
            return true
        }
        return false
    }
    var isValueANY: Bool {
        return (filtersJoinOperator ?? "").lowercased() == "any"
    }
    var isValueOR: Bool {
        return (filtersJoinOperator ?? "").lowercased() == "or"
    }
    static func parseVendor(from dic: Parameter) -> Vendor? {
        do {
            guard let jsonData = dic.jsonString.data(using: .utf8) else { return nil }
            let decoder = JSONDecoder()
            return try decoder.decode(Vendor.self, from: jsonData)

        } catch {
            
        }
        return nil
    }
    
}

// MARK: - Filter Model
struct Filter: Codable {
    private let key: String?
    private let op: String?
    private let val: [String]?
    var finalKey: String {
        return key ?? ""
    }
    var finalOp: String {
        return op ?? ""
    }
    var finalVal: [String] {
        return val ?? []
    }
}


// Define a struct for the vendor
//struct Vendor: Codable {
//    let vendorName: String
//    let urlPatternMatches: [String]
//    let execludeParameters: [String] // Note the typo here: "execludeParameters" should be "excludeParameters"
//    let filters: [String]
//}
//
//// Define a struct for the root JSON object
//struct MonitoringResponse: Codable {
//    let monitoringVersion: String
//    let vendors: [Vendor]
//}
