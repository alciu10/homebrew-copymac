cask "copymac" do
  version "1.5.3"
  sha256 "909e3f82ce2889fad46215022d891f7c0f5fdfbd8879b3d433740834a3e95661"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
