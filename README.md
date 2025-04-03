Monita iOS SDK

Monita iOS SDK is a lightweight library that intercepts network calls for selected vendors, applies filtering and excludes specified parameters, and can batch or upload them to a configured endpoint. It aims to help you analyze or monitor third-party network traffic within your iOS app without
manually writing instrumentation code.

Features

    Network Interception: Hooks into outgoing requests for selected vendors (e.g., Firebase, Facebook, Google).

    Vendor-Based Filtering: Each vendor can define certain URL patterns, parameters to exclude, or filters to apply.

    Batch and Upload: Collects matching requests and can upload them one-by-one or in batches to your endpoint.

    Exponential Backoff: Optionally retries failed uploads with increasing delay.

    Local Fallback: If fetching vendor configuration from the server fails, the SDK can fall back to an embedded JSON config.

Requirements

    iOS 12.0+ (adjust as needed for your codebase)

    Xcode 14+

    Swift 5.5+ for async/await features (if used)

Installation
Swift Package Manager

    In Xcode: File → Add Packages → add the repo URL, e.g. https://github.com/your-org/monita-ios-sdk.git.

    Select the appropriate package and version, then Xcode will integrate it into your project.

In your Package.swift (if you’re manually adding it):

dependencies: [
    .package(url: "https://github.com/your-org/monita-ios-sdk.git", from: "1.0.0")
]
Usage / Configure

In your AppDelegate or SceneDelegate (depending on your app structure), call:

import MonitaSDK

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        MonitaSDK.shared.configure(
            fetchLocally: false,
            enableLogger: true,
            batchSize: 10,
            cid: "customer-id",
            appVersion: "1.0",
            alternativeURL: nil,
            maxRetries: 3,
            baseDelay: 1.0
        )

        return true
    }
}

    fetchLocally: If true, fallback to a local JSON config after the initial fetch.

    enableLogger: Toggles logging.

    batchSize: Max number of requests to store before uploading.

    cid: A custom ID for your environment.

    alternativeURL: If you want to override the default upload endpoint.

    maxRetries + baseDelay: Control exponential backoff for repeated tries when uploads fail.

Starting Monitoring

Once configured, the SDK automatically begins intercepting network calls matching your vendor rules. By default, it uses a NetShears or custom URL protocol (depending on your code) to track requests.
Intercepting Requests

When your app’s code (or third-party libraries) make network calls to any URL patterns that match the vendor config, MonitaSDK will intercept them. Depending on your code, it logs or stores them in an InterceptedRequestStore.
Vendor Configuration

The SDK fetches a vendor config from a known endpoint or uses a local JSON fallback. A typical config might look like:

{
  "vendors": [
    {
      "vendorName": "Google Firebase",
      "urlPatternMatches": [
        "firebase.com",
        "fcm.googleapis.com"
      ],
      "eventParamter": "commerce.items[0].itemNumber",
      "execludeParameters": ["quantity"],
      "filters": []
    }
  ]
}

    vendorName: The name for reference.

    urlPatternMatches: All partial/substring matches to watch for.

    eventParamter: Tells the SDK which param to highlight in logs.

    execludeParameters: Key-value pairs in the body to exclude from final upload.

Excluding Parameters

If you specify execludeParameters as an array like [ "quantity", ...], the SDK will remove any fields with that value from the request body prior to uploading. This keeps sensitive info or irrelevant fields out of your analytics.
Advanced Topics
Exponential Backoff and Retries

If the upload fails (non-2xx or network error), the SDK can retry up to maxRetries times, each time doubling the wait (baseDelay, 2 * baseDelay, etc.). If all fail, it removes the request from the store so it doesn’t get stuck.
Fetch Vendors Regularly

In the absence of background modes, you can fetch the vendor config each time the app launches or resumes, checking if enough time has passed (e.g., 24 hours) to re-fetch. If you do have background tasks, you can schedule a periodic fetch.
Contributing

    Fork the repo and create a new branch for your feature or bugfix.

    Commit your changes with descriptive messages.

    Open a Pull Request. Our team will review and merge if it aligns with the roadmap.
