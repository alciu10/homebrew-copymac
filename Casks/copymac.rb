cask "copymac" do
  version "1.6.7"
  sha256 "da459fa6a656675950e18ac195c85fa715768aff14db22469d49037281f878bd"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
