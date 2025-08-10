cask "copymac" do
  version "1.5.6"
  sha256 "a339411b9b0c18f2ed2fe62523bf534e64d6ee8274c15acce5994f78edc1a7c6"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
