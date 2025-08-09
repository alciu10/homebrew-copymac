cask "copymac" do
  version "1.5.0"
  sha256 "0ed313217ff7382561df2a9c4e1e3bec8e605c3c0a8bb6a6af40af310468e226"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
