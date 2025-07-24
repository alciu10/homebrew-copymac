class Copymac < Formula
  desc "macOS clipboard CLI manager"
  homepage "https://github.com/alciu10/CopyMac-Repo"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.0.0/copymac.tar.gz"
  sha256 "76433ad2a4538590017cb30375ff06cf91b6481fe6fcf7e7aae4b8fbc62b4a7b"
  version "1.0.0"

  def install
    bin.install "copymac-clipboard"
  end

  test do
    system "#{bin}/copymac-clipboard", "--help"
  end
end
