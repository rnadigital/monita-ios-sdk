# MonitaSDK Integration Guide
This document outlines the steps required to integrate MonitaSDK into your iOS application.

Requirements
iOS 13.0 or later

Xcode 12.0 or later

Swift 5.0 or later


Step 1: Install MonitaSDK
Swift Package Manager (SPM)
Open your project in Xcode.

Go to File > Add Packages.

In the search bar, enter the URL of the MonitaSDK repository:


  https://github.com/your_repo/MonitaSDK.git
  
Select the appropriate version and click Add Package.


Step 2: Add MonitaSDKToken to Info.plist
Open your project in Xcode and navigate to your Info.plist file.
Add a new key called MonitaSDKToken with your SDK token as the value:

  `<key>MonitaSDKToken</key>`
  
  `<string>Your-Token-Here</string>`

Step 3: Update AppDelegate.swift
Open your AppDelegate.swift file.

Import the MonitaSDK at the top of the file:

swift
Copy code
import MonitaSDK
Add the following line inside the application(_:didFinishLaunchingWithOptions:) method to initialize the SDK:

swift

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

    // Configure MonitaSDK
    
    MonitaSDK.configure()
    
    return true
    
    }
    
Step 4: Run the App
Build and run your app.
The MonitaSDK should be successfully integrated, and it will initialize when the app is launched.
Additional Information
For more information on how to use the SDK, refer to the official documentation.
If you encounter any issues, please check the FAQ section or open an issue in our repository.


