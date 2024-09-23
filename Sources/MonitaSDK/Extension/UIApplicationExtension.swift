//
//  UIApplicationExtension.swift
//  AppGlobaliOS
//
//  Created by Anis Mansuri on 14/09/24.
//

import UIKit
public extension UIApplication {

    class func getTopMostViewController() -> UIViewController? {
        let keyWindow = UIApplication.shared.windows.filter {$0.isKeyWindow}.first
        if var topController = keyWindow?.rootViewController {
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            return topController
        } else {
            return nil
        }
    }
    class func showAlert(title: String = "", message: String) {
        let ac = UIAlertController(title: title, message: message, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        DispatchQueue.main.async {
            getTopMostViewController()?.present(ac, animated: true)
        }
    }
}
