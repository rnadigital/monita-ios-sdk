//
//  Vendor.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 23.2.25..
//
import Foundation

struct MonitoringResponse: Codable {
    let monitoringVersion: String
    let vendors: [Vendor]?
}

extension Vendor: @unchecked Sendable {}

// MARK: - Vendor Model
public struct Vendor: Codable, Identifiable, Hashable {
    public var id =  UUID()
    public let vendorName: String?
    public let urlPatternMatches: [String]?
    let eventParamter: String?
    let execludeParameters: [String]?
    let filters: [Filter]?
    let filtersJoinOperator: String?
    var isFiltersJoinOperatorAvailable: Bool {
        if filtersJoinOperator != nil {
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
    
    private enum CodingKeys: String, CodingKey {
           case vendorName,
                urlPatternMatches,
                eventParamter,
                execludeParameters,
                filters,
                filtersJoinOperator
       }
}
