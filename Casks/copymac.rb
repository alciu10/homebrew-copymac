cask "copymac" do
  version "1.7.2"
  sha256 "58c33b31a2fd4ca3acc640c736a0e8724bd8cbb14b6ac3b0b4731645db9af637"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
