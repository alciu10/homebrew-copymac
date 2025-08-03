cask "copymac" do
  version "1.3.1"
  sha256 "015540fc8ed610f3cfa252333136ed697d8450ac9cd1a105b6a87c70ac4cdd23"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager with global hotkey support"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
