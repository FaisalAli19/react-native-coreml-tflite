require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "react-native-coreml-tflite"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.description  = <<-DESC
                  react-native-coreml-tflite
                   DESC
  s.homepage     = "https://github.com/FaisalAli19/react-native-coreml-tflite"
  s.license      = "MIT"
  # s.license    = { :type => "MIT", :file => "FILE_LICENSE" }
  s.authors      = {"FaisalAli" => "faisalali1901@gmail.com"}
  s.platforms    = {:ios => "9.0"}
  s.source       = { :git => "https://github.com/FaisalAli19/react-native-coreml-tflite", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m}"
  s.requires_arc = true

  s.dependency "React"
  # ...
  # s.dependency "..."
end
