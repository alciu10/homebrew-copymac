class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/myofer/CopyMac"
  url "https://github.com/myofer/CopyMac/releases/download/v1.3.1/copymac-1.3.1.zip"
  sha256 "feac041d0cc8a4dfa8a0e460937a4eedc224335c9313d54456bc7c75a8bff083"
  version "1.3.1"
  license "MIT"

  def install
    bin.install "copymac"
  end

  test do
    system "#{bin}/copymac", "--help"
  end
end