Pod::Spec.new do |s|
  s.name             = 'MonitaSDK'
  s.version          = '2.0.0'
  s.summary          = 'Passive on device vendor network call monitoring for iOS apps.'
  s.description      = <<-DESC
MonitaSDK observes the vendor and analytics network calls your app already
makes (Firebase, Meta, AppsFlyer, Adjust, Branch, and any vendor configured
for your property) and reports them to your Monita workspace. Interception is
passive: the SDK never blocks, mutates, or re-issues a request, and every
capture path is exception contained.
                       DESC
  s.homepage         = 'https://monita.ai'
  s.license          = { :type => 'Proprietary', :text => 'Copyright RNA Digital PTY LTD' }
  s.author           = { 'RNA Digital' => 'support@monita.ai' }
  s.source           = { :git => 'https://github.com/rnadigital/monita-ios-sdk.git', :tag => s.version.to_s }

  s.platform         = :ios, '14.0'
  s.swift_versions   = ['5.9']
  s.source_files     = 'Sources/MonitaSDK/**/*.swift'
  s.frameworks       = 'Foundation', 'Network'
  s.weak_frameworks  = 'AppTrackingTransparency'
end
