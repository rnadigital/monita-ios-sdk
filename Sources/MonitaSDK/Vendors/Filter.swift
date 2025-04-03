//
//  MonitoringResponse.swift
//  AppGlobaliOS
//
//  Created by Coderon 11/09/24.
//

import Foundation


// MARK: - Root Model


// MARK: - Filter Model
public struct Filter: Codable, Identifiable, Hashable {
    public var id = UUID()
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
    
    private enum CodingKeys: String, CodingKey {
        case key, op, val
    }
    
}
