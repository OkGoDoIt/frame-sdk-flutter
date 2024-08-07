#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint frame_sdk.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'frame_sdk'
  s.version          = '0.0.2'
  s.summary          = 'The Flutter SDK for the Frame from Brilliant Labs'
  s.description      = <<-DESC
The Flutter SDK for the Frame from Brilliant Labs
DESC
  s.homepage         = 'https://github.com/OkGoDoIt/frame-sdk-flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Roger Pincombe' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
