cask "copymac" do
  version "1.3.0"
  sha256 "228dd5167a6d6b17122851b841c112f5db9628e77d680c417f5b5a3e91ea97b3"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"
end
