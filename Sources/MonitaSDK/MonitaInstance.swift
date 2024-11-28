//
//  MonitaInstance.swift
//
//
//  Created by Coderon 11/09/24.
//

import Foundation
import UIKit

open class MonitaInstance {
    
    private static let interceptor = NetworkInterceptor()
    
    private let logger: MonitaLogger
    
    private let networkManager: MonitaNetworkManager
    private let config: MonitaConfig
    
    
    var serialQueue: DispatchQueue
    
    init?(config: MonitaConfig) {
        self.config = config
        logger = MonitaSDK.logger
        serialQueue = DispatchQueue(label: "com.monita.main-thread", qos: .utility)
        networkManager = MonitaNetworkManager(config: config, serialQueue: self.serialQueue)
        setupObservers()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    fileprivate func setupObservers() {
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationWillEnterForeground(_:)),
                                               name: UIApplication.willEnterForegroundNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidEnterBackground(_:)),
                                               name: UIApplication.didEnterBackgroundNotification,
                                               object: nil)
    }
    
    func start(){
        // Start interception. Note that interception will discard requests before a session is started or resumed. However,
        // it is started first for debugging purposes. For example, to see in logs if there were requests intercepted before
        // a session was available
        let requestSniffers = [
            RequestSniffer(requestEvaluator: AnyHttpRequestEvaluator(), handlers: [
                MonitaRequestHandler(serialQueue: self.serialQueue, networkManager: self.networkManager)
            ])
        ]
        let networkConfig = NetworkInterceptorConfig(requestSniffers: requestSniffers)
        NetworkInterceptor.shared.setup(config: networkConfig)
        NetworkInterceptor.shared.startRecording()
        
        // Start session
        serialQueue.async {
            self.startSession()
        }
    }
    
    public func stop(){
        NetworkInterceptor.shared.stopRecording()
        serialQueue.async {
            self.stopSession()
        }
    }
    
    private func startSession() {
        
    }
    
    private func stopSession() {
      
    }
    
 
    
    
    @discardableResult
    static func sharedUIApplication() -> UIApplication? {
        guard let sharedApplication = UIApplication.perform(NSSelectorFromString("sharedApplication"))?.takeUnretainedValue() as? UIApplication
        else {
            return nil
        }
        return sharedApplication
    }
    
    @objc private func applicationWillEnterForeground(_ notification: Notification) {
        serialQueue.async {
            MonitaSDK.logger.debug(message: MonitaMessage.message("onResume lifecycle called"))
            self.startSession()
        }
    }
    
    @objc private func applicationDidEnterBackground(_ notification: Notification) {
        // Max permited execution time is 5 seconds. So request extra time to perform some tasks before suspend
        let taskId = Utils.startBackgroundTask(name: "WaitForRequests")
        
        // Wait 2s as grace period to intercept new events before sending pending events from the queue
        serialQueue.asyncAfter(deadline: .now() + 2.0) {
            Utils.endBackgroundTask(taskId)
        }
        
        serialQueue.sync {
            MonitaSDK.logger.debug(message: MonitaMessage.message("onPause lifecycle called"))
            self.stopSession()
        }
    }
}
public struct MonitaConfig {
    var tp_id: String
    var environment: String
    var debug: Bool
    var endpoint: String
    var configEndpoint: String
}
