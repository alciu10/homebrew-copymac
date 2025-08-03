class Copymac < Formula
  desc "macOS clipboard CLI manager"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.3.0/copymac.tar.gz"
  sha256 "8ddcd57f800663e52a1afcc5a2832bd8c36ef4ccd9d6f5800057ad68205e912a"
  version "1.3.0"

  def install
    bin.install "copymac-clipboard"
  end

  test do
    system "#{bin}/copymac-clipboard", "--help"
  end
end
