cask "copymac" do
  version "1.5.5"
  sha256 "c72322cc6eaba133863a4a8df78d0271691e7b60bb86572370580bbfe3a5c688"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
