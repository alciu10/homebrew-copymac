cask "copymac" do
  version "1.2.1"
  sha256 "119e1df12efa6afbb1f7bb0daf621d9720f46eaae4f27e4cbdbdbe0865985fbb"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
