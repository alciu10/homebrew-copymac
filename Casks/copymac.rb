cask "copymac" do
  version "1.5.1"
  sha256 "bcec883488c2adfd292ab199d92f0141c505132c98878c7cf48598164c75f31f"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
