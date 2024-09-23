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

//Users/anismansuri63/Downloads/Quran Urdu/Urdu/001 Al Fatiha.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/002 Al Baqara.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/003 Aal e Imran.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/004 Al Nisa.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/005 Al Maeda.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/006 Al Anaam.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/007 Al Aaraf.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/008 Al Anfaal.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/009 Al Taubah.mp3 /Users/anismansuri63/Downloads/Quran Urdu/Urdu/010 Younus.mp3 > part1.mp3
