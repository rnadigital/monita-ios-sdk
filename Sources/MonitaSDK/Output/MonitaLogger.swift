//
//  MonitaLogger.swift
//  Monita
//
import Foundation

enum MonitaMessage{
    case message(String)
    case error(String, String)
    case success
}

class MonitaLogger {
    
    private let tagName: String
    private var enabled: Bool = false
    nonisolated(unsafe) static let shared = MonitaLogger(tagName: "Monita")
    
    init(tagName: String) {
        self.tagName = tagName
    }
    
    func enableLogging() {
        enabled = true
    }
    
    func debug(message: MonitaMessage) {
        
        if !enabled {
            return
        }
        
        switch message {
        case .error(let code, let message):
            print("\(tagName) ERROR Code: \(code), Message: \(message)\n")
        case .message(let msg):
            print("\(tagName) DEBUG: \(msg)\n")
        case .success:
            print("\(tagName) DEBUG: Success\n")
        }
    }
}
