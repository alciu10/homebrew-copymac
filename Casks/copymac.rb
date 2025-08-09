cask "copymac" do
  version "1.5.2"
  sha256 "6879affd906ff5d2ce9b1dacea2ba0076df4aa6bdd6c3a6d416b36e53cb27c07"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/copymac-#{version}.zip"
  name "CopyMac"
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
