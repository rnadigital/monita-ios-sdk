//
//  RequestBatchManager.swift
//  AppGlobalDemo
//
//  Created by Anis Mansuri on 10/09/24.
//
import Foundation
class RequestBatchManager {
    static let shared = RequestBatchManager()
    private var requestQueue = [[String: Any]]()
    private let maxBatchSize = 10
    private let batchInterval: TimeInterval = 60 // seconds
    
    private init() {
        Timer.scheduledTimer(withTimeInterval: batchInterval, repeats: true) { _ in
            self.flushBatch()
        }
    }
    
    func addRequest(_ requestDetails: [String: Any]) {
        requestQueue.append(requestDetails)
        if requestQueue.count >= maxBatchSize {
            flushBatch()
        }
    }
    
    private func flushBatch() {
        guard !requestQueue.isEmpty else { return }
        
        let batch = requestQueue
        requestQueue.removeAll()
        
        // Send batch to server
        //RequestManager.shared.sendToServer(requestDetails: ["batch": batch], vender: <#Vendor#>)
    }
}

