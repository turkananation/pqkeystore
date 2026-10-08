#
# Shared iOS + macOS source (pubspec: sharedDarwinSource: true).
# Swift Package Manager users get the same sources via pqkeystore/Package.swift.
#
Pod::Spec.new do |s|
  s.name             = 'pqkeystore'
  s.version          = '0.1.0-dev.1'
  s.summary          = 'Post-quantum key custody: OS keychain storage backend.'
  s.description      = <<-DESC
Native storage backend for the pqkeystore Flutter package. Stores opaque
PQKS records in the data protection keychain. Implements platform channel
contract v1 (doc/PLATFORM_CONTRACT.md).
                       DESC
  s.homepage         = 'https://github.com/turkananation/pqkeystore'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Yardenah / Turkana Nation' => 'https://yardenah.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'pqkeystore/Sources/pqkeystore/**/*.swift'

  s.ios.deployment_target = '15.0'
  s.osx.deployment_target = '12.0'

  s.ios.dependency 'Flutter'
  s.osx.dependency 'FlutterMacOS'
  s.frameworks = 'Security', 'LocalAuthentication'

  # Flutter.framework does not contain an i386 slice.
  s.ios.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.osx.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.swift_version = '5.0'

  s.resource_bundles = { 'pqkeystore_privacy' => ['pqkeystore/Sources/pqkeystore/PrivacyInfo.xcprivacy'] }
end
