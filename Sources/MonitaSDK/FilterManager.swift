//
//  FilterManager.swift
//  MonitaSDK
//
//

import Foundation

public actor FilterManager {
    public static let shared = FilterManager()
    private init() {}
    static func checkPassOnFilters(data: Parameter, vendor: Vendor) -> Bool {
        let joinOperator = vendor.filtersJoinOperator ?? ""
        let filters = vendor.filters ?? []
        let exitImmediately = (joinOperator == "AND")
        var results: [Bool] = []
        
        for filter in filters {
            let key = filter.finalKey
            let op = filter.finalOp
            let filterValues = filter.finalVal
            var pass = true
            
            if ["eq", "contains"].contains(op) {
                let val = fillParamsFromData(key: key, data: data)
                pass = false
                for filterValue in filterValues {
                    if filterValue == val as? String ?? "" {
                        pass = true
                        break
                    }
                }
                if !pass && exitImmediately {
                    return false
                }
            } else if op == "ne" {
                for filterValue in filterValues {
                    let compareVal = fillParamsFromData(key: key, data: data) as? String ?? ""
                    if compareVal == filterValue {
                        if exitImmediately {
                            return false
                        } else {
                            pass = false
                            break
                        }
                    }
                }
            } else if op == "blank" {
                let value = fillParamsFromData(key: key, data: data)
                if let valueString = value as? String, !valueString.isEmpty {
                    if exitImmediately { return false } else { pass = false }
                }
            } else if op == "not_blank" {
                let value = fillParamsFromData(key: key, data: data)
                if value == nil || (value as? String)?.isEmpty == true {
                    if exitImmediately { return false } else { pass = false }
                }
            } else if op == "exist" {
                let value = fillParamsFromData(key: key, data: data)
                if value == nil {
                    if exitImmediately { return false } else { pass = false }
                }
            } else if op == "not_exist" {
                let value = fillParamsFromData(key: key, data: data)
                if value != nil {
                    if exitImmediately { return false } else { pass = false }
                }
            }
            
            results.append(pass)
        }
        
        if exitImmediately {
            return true
        } else {
            return filters.isEmpty || results.contains(true)
        }
    }
    
    // Helper function to extract value from the data dictionary.
    private static func fillParamsFromData(key: String, data: Parameter) -> Any? {
        if let bodyDic = (data["body"] as? String)?.dictionary(),
           let array = (bodyDic["custom_events"] as? String)?.array() {
            for element in array {
                if let newVal = element[key] as? String {
                    return newVal
                }
            }
        }
        return data[key]
    }
}
