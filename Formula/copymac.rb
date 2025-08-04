class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.3/copymac-1.3.3.zip"
  sha256 "4bded454fd9be4fc7c4f41fdd5e817de0b315576e586420c72b204276f382d22"
  version "1.3.3"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end