cask "copymac" do
  version "1.6.1"
  sha256 "29c17b4119f85ada4a772da850c0a6aab42cc3fa20b640cf6b255384d34178db"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
