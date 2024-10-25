Pod::Spec.new do |s|
  s.name        = "ARCapture"
  s.version     = "0.2.3"
  s.summary     = "Utility allows to capture videos from ARKit scene and export to Photos app with LiDAR depth data"
  s.homepage    = "https://gitlab.com/seriyvolk83/ARCapture"
  s.license     = { :type => "MIT" }
  s.authors     = { "seriyvolk83" => "volk@frgroup.ru" }

  s.requires_arc = true
  s.swift_version = "5.2"
  s.ios.deployment_target = "13.0"
  s.source   = { :git => "https://gitlab.com/seriyvolk83/ARCapture.git", :tag => s.version }
  s.source_files = "Source/*.swift"
end
