cask "copymac" do
  version "1.3.0"
  sha256 "a877224271b29323acd501b18de1a52d27689f2a21837376d5c7fe288e6de151"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
