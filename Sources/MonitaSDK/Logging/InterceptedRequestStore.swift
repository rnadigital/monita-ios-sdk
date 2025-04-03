//
//  InterceptedRequestStore.swift
//  MonitaSDK
//
//  Created by Igor  Vojinovic on 23.2.25..
//

// InterceptedRequestStore.swift
import Foundation

public actor InterceptedRequestStore {
    static let shared = InterceptedRequestStore()
    private init() {
        items = Self.loadItemsFromDisk()
    }
    
    private var items: [InterceptedRequest] = []
    
    private static let storeKey = "com.monitaSDK.interceptedRequests"
    
    // Adds an intercepted request to the array and persists.
    func add(_ request: InterceptedRequest) {
        items.append(request)
        saveToDisk()
        // If items >= batchSize, trigger the upload
        if items.count >= MonitaSDK.shared.batchSize {
            Task {
                await RequestManager.shared.sendInterceptedRequestsOneByOne()
            }
        }
    }
    
    /// Return a copy of the current items (in memory).
    func allRequests() -> [InterceptedRequest] {
        return items
    }
    
    /// Drains the entire array, returning them and clearing local store
    func drainAll() -> [InterceptedRequest] {
        let result = items
        items.removeAll()
        saveToDisk()
        return result
    }
    
    func remove(_ request: InterceptedRequest) {
            if let idx = items.firstIndex(where: { $0 == request }) {
                items.remove(at: idx)
                saveToDisk()
            }
        }
    
    // MARK: - Persistence
    
    /// Saves `items` to UserDefaults as Data (JSON-encoded).
    private func saveToDisk() {
        do {
            let data = try JSONEncoder().encode(items)
            UserDefaults.standard.set(data, forKey: InterceptedRequestStore.storeKey)
        } catch {
            print("Failed to encode InterceptedRequest array: \(error)")
        }
    }
    
    /// Loads `items` from UserDefaults if available.
    private static func loadItemsFromDisk() -> [InterceptedRequest] {
        guard let data = UserDefaults.standard.data(forKey: storeKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([InterceptedRequest].self, from: data)
        } catch {
            print("Failed to decode InterceptedRequest array: \(error)")
            return []
        }
    }
}

