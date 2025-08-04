class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.6/copymac-1.3.6.zip"
  sha256 "ef9352c3ed2e5f693a13fe8a2b8c73b13c934e4f4a6960fda1410598308ccd2d"
  version "1.3.6"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end