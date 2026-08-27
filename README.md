# MonitaSDK for iOS

MonitaSDK observes the vendor and analytics network calls your app already makes and reports them to your Monita workspace, using the same remote configuration, payload schema, and warehouse columns as Monita's web monitoring. It answers one question in production: are your marketing and analytics tags actually firing, with the right data?

Monitoring is passive. The SDK never blocks, mutates, delays, or re-issues a request, never reads response bodies, and every capture path is exception contained. If anything goes wrong inside the SDK, your app's networking behaves exactly as if the SDK were not there.

- Version: 2.0.0
- Platforms: iOS 14 and later
- Swift: 5.9 and later
- Dependencies: none

## Installation

### Swift Package Manager

In Xcode, choose File, Add Package Dependencies, and enter:

```
https://github.com/rnadigital/monita-ios-sdk
```

Or add it to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/rnadigital/monita-ios-sdk", from: "2.0.0")
]
```

### CocoaPods

```ruby
pod 'MonitaSDK', '~> 2.0'
```

## Quick start

```swift
import MonitaSDK

Monita.configure(token: "dom_xxxxxxxxxxxxxxxxxxxxxxxx")
```

That is the whole integration. Call `configure` early, ideally in `application(_:didFinishLaunchingWithOptions:)` or your `App` initializer, so launch time vendor traffic is observed. The SDK buffers requests seen before the remote configuration loads (up to 50 requests for 30 seconds) and evaluates them once the configuration arrives, so early traffic such as a Firebase first flush is not lost.

You can also configure with options:

```swift
Monita.configure(MonitaConfiguration(token: "dom_xxxxxxxxxxxxxxxxxxxxxxxx", collectEndpoint: nil, configEndpoint: nil, debugLogging: false))
```

Or with no arguments, reading the token from an `MonitaSDKToken` entry in your Info.plist:

```swift
Monita.configure()
```

`collectEndpoint` and `configEndpoint` are full URLs for customers running reverse proxies or dedicated hosts. When nil, the SDK uses the Monita production endpoints.

## How it works

1. On configure, the SDK loads its cached vendor configuration instantly and refreshes it in the background from the Monita CDN (conditional GET with ETag, refreshed on each cold start and every 6 hours while the app is in the foreground).
2. The SDK observes `URLSession` task starts in process. When a request URL matches a configured vendor pattern, the SDK snapshots the URL and request body (bodies over 64KB and binary bodies are not decoded), extracts the event name and parameters, and applies your configured filters and exclusions.
3. Matched events are batched (10 events or 2 seconds, whichever comes first, plus a flush when the app goes to background) into a single envelope and written to a persistent on disk queue.
4. The queue uploads to the collect endpoint and deletes an event only after the server acknowledges it with a 2xx response. Failed uploads retry with exponential backoff while the network is reachable. Delivery is at least once: in the rare case of a crash between the server's acknowledgement and the local delete, a batch can arrive twice.

Deleting a vendor from your Monita property, pausing monitoring, or removing the property takes effect at the next configuration refresh, and a paused or removed property also clears any queued events.

## API reference

All methods are safe to call from any thread.

| Method | Description |
| --- | --- |
| `Monita.configure()` | Configure using the `MonitaSDKToken` Info.plist entry. |
| `Monita.configure(token:)` | Configure with a property token. |
| `Monita.configure(_ configuration:)` | Configure with `MonitaConfiguration(token:collectEndpoint:configEndpoint:debugLogging:)`. |
| `Monita.setCustomerId(_:)` | Attach your user identifier to payloads (`cid`). Pass nil to remove. |
| `Monita.setSessionId(_:)` | Override the SDK managed session id. Pass nil to return to automatic rotation (30 minutes of inactivity). |
| `Monita.setScreen(_:)` | Set the current screen name, reported with every event. |
| `Monita.setConsent(_:)` | Override consent auto detection with an explicit consent string. |
| `Monita.setConsentProvider(_:)` | Supply the consent string dynamically from your CMP. |
| `Monita.setEventFilter(_:)` | Gate every outgoing event. Return false to drop it. |
| `Monita.setEventResolver(_:)` | Name events yourself before configured extraction runs. |
| `Monita.send(vendor:event:data:)` | Send a manual event. Requires manual monitoring enabled on your property and a configured vendor name. |
| `Monita.optOut()` / `Monita.optIn()` | Stop or resume monitoring for this install. Opt out clears all queued data and persists across launches. |
| `Monita.flush()` | Flush batched events and attempt an upload now. |
| `Monita.refreshConfig()` | Force a configuration refresh, bypassing the CDN cache. |
| `Monita.setDebugLogging(_:)` | Verbose logging plus unbatched delivery, one POST per event. Default off. |
| `Monita.version` | The SDK version string. |

## Consent

The SDK does not collect consent itself. It reports the consent state your CMP already manages so your monitoring data carries the same consent context as your tags.

Auto detection, re-read for every batch: the SDK reads the IAB standard strings that CMP SDKs write to `UserDefaults`, in this order:

1. `IABTCF_TCString` (TCF v2)
2. `IABGPP_HDR_GppString` (GPP)
3. `IABUSPrivacy_String` (US Privacy)

Overrides: `setConsent("...")` wins over auto detection; `setConsentProvider { ... }` is called at build time for dynamic values.

By default the SDK keeps monitoring regardless of consent state, matching Monita's web behavior, because tag monitoring is typically run as a fraud and compliance measurement function. If your policy requires gating delivery on consent, wire your CMP callback:

```swift
Monita.setEventFilter { _ in
    MyCMP.shared.hasAnalyticsConsent
}
```

Returning false drops events before they are queued.

## Coverage and limitations

| Traffic | Covered |
| --- | --- |
| `URLSession` requests made in process (app code and most vendor SDKs, including Firebase, Meta, AppsFlyer, Adjust, Branch) | Yes |
| Request URL, method, query parameters, and JSON, form encoded, or key value bodies up to 64KB | Yes |
| Response status codes (tag success or failure) | Yes |
| `WKWebView` traffic | No |
| Background `URLSession` transfers | No |
| Raw sockets and custom network stacks that bypass `URLSession` | No |
| Response bodies | Never read, by design |
| Bodies over 64KB, streamed bodies (`httpBodyStream`), and binary or protobuf bodies | URL parameters only |

## Privacy

- No fingerprinting, no IDFA, no advertising identifiers, no cookie or credential harvesting.
- The visitor id (`vid`) and session id (`sid`) are SDK generated UUIDs. The visitor id persists per install, the session id rotates after 30 minutes of inactivity.
- Captured vendor parameters are capped at 100 per event and pass your property's exclusion rules before leaving the device.
- Queued payloads are stored in the app's Caches directory, excluded from backups.
- Payload bodies are never logged unless debug logging is explicitly enabled.

## Troubleshooting

**No events arrive.**
Check the token. Then call `Monita.setDebugLogging(true)` and watch the console (subsystem `ai.monita.sdk`): the SDK logs the configuration load and a match, no match, or filter decision line for each observed request. If the configuration never loads, the property may be paused or removed, or the config endpoint is unreachable.

**A vendor call is not captured.**
Confirm the vendor is enabled for your property and its URL pattern actually appears in the request URL. Remember the coverage table above: WKWebView and background session traffic are not observed.

**Events are captured but arrive late.**
Delivery is store and forward. Events are batched for up to 2 seconds, then queued on disk and uploaded when the network is reachable, so offline sessions arrive after the next launch with connectivity. `Monita.flush()` forces an immediate attempt.

**The first launch reports nothing.**
On the very first launch there is no cached configuration yet, so monitoring starts once the first configuration fetch completes. Requests seen in the 30 seconds before that are buffered and evaluated retroactively.

**Debug logging shows "circuit breaker tripped".**
The SDK captured more than 100 events in 6 seconds and turned itself off for the rest of the process lifetime as a safety valve. This usually means a vendor pattern is far too broad.

**Does the SDK slow my networking down?**
No. The SDK does not sit in the request path. It snapshots request metadata at send time and does all processing on its own background queue.

## Requirements recap

iOS 14+, Swift 5.9+, Xcode 15+. The SDK links only Foundation and Network, plus AppTrackingTransparency weakly for status reporting.

Copyright RNA Digital PTY LTD
