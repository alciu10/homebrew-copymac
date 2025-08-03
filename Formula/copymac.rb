class Copymac < Formula
  desc "macOS clipboard CLI manager"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.3.0/copymac.tar.gz"
  sha256 "53ea5b5e53564bdc7fe3a241536ff39cb620a769bb3e224eb5648caf4f9e001a"
  version "1.3.0"

  def install
    bin.install "copymac-clipboard"
  end

  test do
    system "#{bin}/copymac-clipboard", "--help"
  end
end
