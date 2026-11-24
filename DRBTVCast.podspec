Pod::Spec.new do |s|
  s.name             = 'DRBTVCast'
  s.version          = '0.1.0'
  s.summary          = 'DLNA cast module for DramaBox - pure Swift implementation.'

  s.description      = <<-DESC
  A lightweight, pure-Swift DLNA/UPnP casting library.
  Discovers AVTransport devices via SSDP multicast, controls playback
  via SOAP, and polls position for progress/completion callbacks.
                       DESC

  s.homepage         = 'https://gitlab.jiushik.cn/novel/drama_ios/DRBTVCast'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'dramabox' => 'dramabox@users.noreply.github.com' }
  s.source           = { :git => 'https://gitlab.jiushik.cn/novel/drama_ios/DRBCast.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.1'
  s.swift_versions = ['5.0', '6.0']

  s.source_files = 'DRBTVCast/Classes/**/*'

  s.frameworks = 'Foundation', 'Network', 'AVFoundation', 'AVKit'
  s.dependency 'google-cast-sdk'
end
