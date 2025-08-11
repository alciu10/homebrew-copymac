cask "copymac" do
  version "1.6.8"
  sha256 "d0bdf66f03685c8a7f6ba9edceb1538d9c4a72a739945959a1480883f6f86fbc"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
