# Vendors the LocalDrop Rust engine as a dynamic framework so Dart can open it
# with DynamicLibrary.open('LocalDropEngine.framework/LocalDropEngine').
# Build it first on macOS:  native/scripts/build-ios.sh
Pod::Spec.new do |s|
  s.name             = 'localdrop_engine'
  s.version          = '0.1.0'
  s.summary          = 'LocalDrop native engine (Rust)'
  s.description      = 'Local HTTP/WebSocket server, sessions, uploads and downloads for LocalDrop.'
  s.homepage         = 'https://github.com/iamfaiz123/LocalDrop'
  s.license          = { :type => 'Proprietary' }
  s.author           = { 'LocalDrop' => 'dev@localdrop.app' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.0'
  s.vendored_frameworks = 'Frameworks/LocalDropEngine.xcframework'
  s.frameworks       = 'Security', 'SystemConfiguration'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version    = '5.0'
end
