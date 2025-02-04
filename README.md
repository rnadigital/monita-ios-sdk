
# Monita SDK for iOS

Monita SDK provides robust monitoring and analytics capabilities for your iOS applications, including request monitoring, analytics integration, and performance tracking.

## Table of Contents

- [Overview](#overview)
- [Installation](#installation)
- [Usage](#usage)
- [Features](#features)
- [Troubleshooting](#troubleshooting)
- [License](#license)
- [Contact](#contact)

## Overview

Monita SDK empowers developers with powerful tools to monitor network requests, integrate popular analytics platforms, and track app performance with ease. Designed for seamless integration into your iOS projects, it helps you gain valuable insights into your app’s behavior and performance.

## Installation

Follow these steps to integrate Monita SDK into your iOS project:

### Step 1: Add the Package Dependency

1. Open Xcode and navigate to **File > Swift Packages > Add Package Dependency**.
2. In the search box, enter the URL:  
   ```
   https://github.com/rnadigital/monita-ios-sdk.git
   ```
3. Click **Next**.
4. Select the **branch** option and enter `master` as the branch name.
5. Click **Finish**. The SDK will be added under **Swift Package Dependencies**.

### Step 2: Configure the SDK Token

1. Open your project's `Info.plist` file in Xcode.
2. Add a new key called `MonitaSDKToken` with your SDK token as the value:

   ```xml
   <key>MonitaSDKToken</key>
   <string>Your-Token-Here</string>
   ```

## Usage

After installing the SDK, initialize it in your application delegate. For example, update your `AppDelegate.swift` as follows:

```swift
import MonitaSDK

func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Initialize Monita SDK with your custom configuration
    MonitaSDK.configure(
        enableLogger: true,
        batchSize: 10,
        customerId: "123456",
        consentString: "Granted",
        sessionId: "123456",
        appVersion: "1.0"
    )
    
    return true
}
```

## Features

- **Automatic Request Monitoring:** Seamlessly track and log network requests.
- **Analytics Integration:** Integrates with Google Analytics, Facebook Analytics, and Firebase.
- **Performance Tracking:** Monitor and optimize your app's performance.
- **Easy Integration:** A straightforward setup process gets you up and running quickly.

## Troubleshooting

If you encounter issues during setup, try resetting your package caches in Xcode:

1. Navigate to **File > Packages > Reset Package Caches**.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

For any questions or support, please reach out to:  
**support@monita.com**
```

Once you create and commit this file to your GitHub repository, visitors will have a clear overview of the project, its installation instructions, and usage details.
