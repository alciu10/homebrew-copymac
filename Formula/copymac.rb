class Copymac < Formula
  desc "macOS clipboard CLI manager"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.3.0/copymac.tar.gz"
  sha256 "4f5a7d64465182621bfa7435ff32475c665649aac416898bdeab3037943e947f"
  version "1.3.0"

  def install
    bin.install "copymac-clipboard"
  end

  test do
    system "#{bin}/copymac-clipboard", "--help"
  end
end