cask "copymac" do
  version "1.7.0"
  sha256 "f872ab81ee442bdc4977fb3f1ef8d9dce0f101ebadd3020559afd01f5e885cf2"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
