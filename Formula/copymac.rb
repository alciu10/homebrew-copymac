class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.7/copymac-1.3.7.zip"
  sha256 "071bc6faf1a30e3f7a38fd17f052299a65a328ea2e03373cc77d40596635746e"
  version "1.3.7"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end