//
//  Requestee.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 23.2.25..
//
import Foundation

struct InterceptedRequest: Codable {
    let vendors: [Vendor]
    let url: String
    let method: String
    let statusCode: Int?
    let headers: [String: String]
    let body: Data?
    let responseBody: Data?
}
extension InterceptedRequest: @unchecked Sendable {}
extension InterceptedRequest: Equatable {
    static func == (lhs: InterceptedRequest, rhs: InterceptedRequest) -> Bool {
        return lhs.url == rhs.url &&
        lhs.method == rhs.method &&
        lhs.statusCode == rhs.statusCode &&
        lhs.headers == rhs.headers &&
        lhs.body == rhs.body &&
        lhs.responseBody == rhs.responseBody &&
        lhs.vendors.first?.vendorName == rhs.vendors.first?.vendorName
        
    }
}

