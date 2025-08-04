class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/CopyMac"
  url "https://github.com/alciu10/CopyMac/releases/download/v1.3.3/copymac-1.3.3.zip"
  sha256 "fcfe6ae860d4921f65c16732c1e803de759565dbf09f01bbb41895e7c18a337d"
  version "1.3.3"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end