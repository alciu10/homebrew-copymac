cask "copymac" do
  version "1.6.9"
  sha256 "eedb39bdb57a5d5fbf2bda58bbe7d023770c0f80415c568bc0b9af21cad3ff28"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
