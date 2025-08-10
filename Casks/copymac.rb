cask "copymac" do
  version "1.5.7"
  sha256 "66f4feb1319ed90380d0b0f35ae5c501a605d2ff84c04b741a26983c9eb77458"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
