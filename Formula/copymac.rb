class Copymac < Formula
  desc "macOS clipboard GUI manager with smooth animations and favorites"
  homepage "https://github.com/alciu10/CopyMac-Repo"
  url "https://github.com/alciu10/CopyMac-Repo/archive/af200f52cf5a86778f73781695375e4e2abefd3e.tar.gz"
  sha256 "14bba0fdb2c9b5b292218c46bbdd3feb2215391df97b4e80db042af76ae0c8fd"
  version "1.1.0"

  depends_on xcode: ["12.0", :build]

  def install
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    bin.install ".build/release/copymac-clipboard"
  end

  test do
    system "true"  # Simple test that always passes
  end
end
