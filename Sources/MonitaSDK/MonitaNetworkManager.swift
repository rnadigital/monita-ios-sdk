//
//  MonitaNetworkManager.swift
//  Monita
//

import Foundation
import UIKit


class MonitaNetworkManager {
    private let config: MonitaConfig
    private let logger: MonitaLogger
    private let serialQueue: DispatchQueue
    private var watcher: DispatchWorkItem?

    init(config: MonitaConfig, serialQueue: DispatchQueue) {
        self.config = config
        self.serialQueue = serialQueue
        logger = MonitaSDK.logger
    }

}
