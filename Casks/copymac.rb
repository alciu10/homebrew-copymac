cask "copymac" do
  version "1.6.5"
  sha256 "1b0033ce66f0d4e45f91c1f28d2c6f3059eeffc96dc0f012546ccead2ed9917f"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
