cask "copymac" do
  version "1.7.1"
  sha256 "b2b6cdae1c9baa6c4085f111e88626b73856d5aaa221177dd1d044657348d650"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
