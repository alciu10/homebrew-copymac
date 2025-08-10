cask "copymac" do
  version "1.6.3"
  sha256 "a17537eb192f76e001171ff53d82187930936f8c13a8d017cd8fcc47061f7f6f"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
