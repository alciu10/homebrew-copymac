class Copymac < Formula
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.0/copymac.tar.gz"
  sha256 "d6ac7b7e17d9a20c3bfb2ad3393f5559846f4f93c7c3da083a7a887db9310cc4"
  version "1.3.0"

  def install
    prefix.install Dir["*"]
    bin.install "CopyMac.app/Contents/MacOS/CopymacClipboard"
  end

  test do
    system "#{bin}/CopymacClipboard", "--help"
  end
end