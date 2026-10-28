#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint xue_hua_navite_auto_update.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'xue_hua_navite_auto_update'
  s.version          = '1.0.0'
  s.summary          = 'Flutter desktop auto-update and self-relaunch plugin with out-of-process native progress UI.'
  s.description      = <<-DESC
A production-grade Flutter desktop (macOS, Windows, Linux) auto-update and self-relaunch plugin supporting standard installer packages (.dmg, .pkg, .exe, .AppImage, .deb, .rpm), out-of-process native progress dialogs, on-demand privilege elevation, and automatic rollback.
                       DESC
  s.homepage         = 'https://github.com/Matkurban/xue_hua_navite_auto_update'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Matkurban' => '3496354336@qq.com' }

  s.source           = { :path => '.' }
  s.source_files = 'xue_hua_navite_auto_update/Sources/xue_hua_navite_auto_update/**/*.swift'
  s.resource_bundles = {'xue_hua_navite_auto_update_privacy' => ['xue_hua_navite_auto_update/Sources/xue_hua_navite_auto_update/PrivacyInfo.xcprivacy']}

  s.dependency 'FlutterMacOS'

  s.platform = :osx, '12.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.9'
end
