cask "copymac" do
  version "1.6.0"
  sha256 "d01adfbb72e3a7eaf6ad33aa6e8369adcf308e667365384af5cbf8043c7ccf49"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
