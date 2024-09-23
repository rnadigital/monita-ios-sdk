//
//  MonitoringResponse.swift
//  AppGlobaliOS
//
//  Created by Anis Mansuri on 11/09/24.
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
}

// MARK: - Filter Model
struct Filter: Codable {
    let key: String?
    let op: String?
    let val: [String]?
}
