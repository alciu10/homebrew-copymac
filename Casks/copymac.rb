cask "copymac" do
  version "1.4.0"
  sha256 "ac77d05de036529831d385779df6dc23cb65d7ab22134873c6fa224c4ac17018"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
