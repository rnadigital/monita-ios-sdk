//
//  MonitaRequestHandler.swift
//  Monita
//

import Foundation

class MonitaRequestHandler: SniffableRequestHandler {

    private let networkManager: MonitaNetworkManager
    private let serialQueue: DispatchQueue

    init(serialQueue: DispatchQueue, networkManager: MonitaNetworkManager) {
        self.networkManager = networkManager
        self.serialQueue = serialQueue
    }

    public func sniffRequest(urlRequest: URLRequest) {
        //let alternateRequest = URLRequestFactory().createURLRequest(originalUrlRequest: urlRequest)
        
    }
}
