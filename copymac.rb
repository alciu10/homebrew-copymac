class Copymac < Formula
  desc "Clipboard manager app for macOS"
  homepage "https://github.com/alciu10/CopyMac-Repo"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.0.0/copymac.tar.gz"
  sha256 "1eef0596bdc8dfda0edec554119078c263c1a34200913e6ed164bc9c0f0c67e6"
  version "1.0.0"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end
