class Copymac < Formula
  desc "Clipboard manager app for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.2.1/CopyMac.app.zip"
  sha256 "PASTE_THE_SHA256_HERE"
  version "1.2.1"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end
