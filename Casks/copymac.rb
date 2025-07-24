cask "copymac" do
  version "1.0.0"
  sha256 "ac157304f058fc0dce998e9c12983a29da3e3cec7b7c98275004411811da7ff4"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
