cask "copymac" do
  version "1.5.9"
  sha256 "ba926b26119b94556525d099650bbc18d0f8083c084a198b26805a5fc50a63ed"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
