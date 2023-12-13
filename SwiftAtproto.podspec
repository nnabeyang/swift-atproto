Pod::Spec.new do |s|
  s.name         = "SwiftAtproto"
  s.version      = "0.4.1"
  s.summary      = "swift-atproto is a atproto library."
  s.homepage              = "https://github.com/nnabeyang/swift-atproto"
  s.license               = { :type => "MIT", :file => "LICENSE" }
  s.author                = { "nnabeyang" => "nabeyang@gmail.com" }
  s.ios.deployment_target = "16.0"
  s.osx.deployment_target = "13.0"

  s.source       = { :git => "https://github.com/nnabeyang/swift-atproto.git", :tag => "#{s.version}" }
  s.source_files  = "Sources/SwiftAtproto/*.swift"
  s.requires_arc = true
  s.swift_version = '5.9'
end
