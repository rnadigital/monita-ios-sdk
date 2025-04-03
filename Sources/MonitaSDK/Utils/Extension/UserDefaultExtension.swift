//
//  Untitled.swift
//  MonitaSampleApp
//
//  Created by Anis Mansuri on 06/12/24.
//
import UIKit
typealias Parameter = [String: Any]
extension UserDefaults {
    enum Keys: String {
        case requestListCall = "RequestListCall"
        case requestList = "RequestList"
        case pendingServerReqests = "PendingServerReqests"
    }

    func setVal(value: Any, key: Keys) {
        setValue(value, forKey: key.rawValue)
    }

    func getVal(key: Keys) -> Any? {
        return value(forKey: key.rawValue)
    }
}
