# Project Setup Instructions

## Framework Integration

1. Open Xcode

2. Click on your project in the navigator (left side)

3. Select your target "AppGlobalDemoIOS"

4. Go to the "General" tab

5. Scroll down to "Frameworks, Libraries, and Embedded Content"

6. Click the + button

7. Select "Add Other..." -> "Add Files..."

8. Navigate to your project folder and select "AppGlobaliOS.xcframework"

9. In the dialog that appears:
   - Ensure "Copy items if needed" is checked
   - For "Embed" option, select "Embed & Sign"

This will automatically update your project.pbxproj file to include the framework dependency.

## Adding Source Files

1. Right-click on your project in Xcode's navigator

2. Select "Add Files to 'AppGlobalDemoIOS'..."

3. Navigate to and select ListViewController.swift

4. In the dialog:
   - Make sure "Copy items if needed" is checked
   - In "Add to targets", ensure "AppGlobalDemoIOS" is selected

5. Click "Add"


## Installing Firebase

### Option 1: Using Swift Package Manager (Recommended)
1. In Xcode, select File → Add Packages

2. Enter the Firebase iOS SDK repository URL:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```

3. Select the Firebase products you want to use (e.g., Firebase Analytics)

4. Click "Add Package"

5. Firebase Console Setup:
   - Go to [Firebase Console](https://console.firebase.google.com/)
   - Create a new project or select existing one
   - Click "Add app" and select iOS
   - Enter your app's bundle identifier
   - Download the `GoogleService-Info.plist` file

6. Add Firebase configuration file:
   - Drag the downloaded `GoogleService-Info.plist` into your Xcode project navigator
   - Make sure "Copy items if needed" is checked
   - Select the appropriate target(s)

### Option 2: Using CocoaPods
1. Install CocoaPods if not already installed:
   ```bash
   sudo gem install cocoapods
   ```

2. Create a Podfile:
   ```bash
   pod init
   ```

3. Add the following to your Podfile:
   ```ruby
   platform :ios, '14.0'

   target 'AppGlobalDemoIOS' do
     use_frameworks!

     # Add the Firebase pods you want to use
     pod 'Firebase/Core'
   end
   ```

4. Install the pods:
   ```bash
   pod install
   ```

5. Close Xcode and open the newly created `.xcworkspace` file

6. Build the project

7. In Xcode:
   - Go to Build Settings
   - Search for "User Script Sandboxing"
   - Set it to "No"
