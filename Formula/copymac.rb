class Copymac < Formula
  desc "macOS clipboard GUI manager with smooth animations and favorites"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.2.1/CopyMac.app.zip"
  sha256 "119e1df12efa6afbb1f7bb0daf621d9720f46eaae4f27e4cbdbdbe0865985fbb"
  version "1.2.1"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end
