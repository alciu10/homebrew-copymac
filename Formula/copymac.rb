class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.8/copymac-1.3.8.zip"
  sha256 "9016ba0fc9a8b80de89352610d1f72617b78bbb2eaac62a85689ff765a1f7e18"
  version "1.3.8"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end