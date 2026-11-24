Pod::Spec.new do |s|
  s.name             = 'DRBTVCastUI'
  s.version          = '0.1.0'
  s.summary          = 'TV Cast UI module archive for DramaBox.'

  s.description      = <<-DESC
  TV Cast UI controllers, models, views and resources archived for modular recoverability.
                       DESC

  s.homepage         = 'https://gitlab.jiushik.cn/novel/drama_ios/DRBTVCastUI'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'dramabox' => 'dramabox@users.noreply.github.com' }
  s.source           = { :git => 'https://gitlab.jiushik.cn/novel/drama_ios/DRBTVCastUI.git', :tag => s.version.to_s }

  s.ios.deployment_target = '15.1'
  s.swift_versions = ['5.0', '6.0']

  s.source_files = 'Controller/**/*', 'Model/**/*', 'View/**/*'
  s.resources = 'Resources/**/*'

  s.frameworks = 'UIKit', 'Foundation'
  s.dependency 'DRBTVCast'
  s.dependency 'SnapKit'
  s.dependency 'ObjectMapper'
end
