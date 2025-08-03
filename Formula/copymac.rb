class Copymac < Formula
  desc "macOS clipboard CLI manager"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.3.0/copymac.tar.gz"
  sha256 "48055275b03793f6682a0348ea34998dd381c0a39d59a4b297457e753c8a80fd"
  version "1.3.0"

  def install
    bin.install "copymac-clipboard"
  end

  test do
    system "#{bin}/copymac-clipboard", "--help"
  end
end
