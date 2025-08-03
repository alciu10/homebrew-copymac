cask "copymac" do
  version "1.3.0"
  sha256 "322b95efa0922720547a81a27ea7d05107d0d381cd22ec6e3c2103ce7aed58f4"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
