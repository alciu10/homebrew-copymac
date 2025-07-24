class CopymacClipboard < Formula
  desc "Clipboard manager for macOS with hotkey support"
  homepage "https://github.com/copymac/MyClipboardApp"
  url "https://github.com/copymac/MyClipboardApp/archive/v1.0.0.tar.gz"
  sha256 "dadcae5bf8e302d95b463674ec47b43018f316ba45faf582b0f92e137be28267"
  license "MIT"

  depends_on xcode: ["12.0", :build]
  depends_on :macos

  def install
    system "swift", "build", "--disable-sandbox", "-c", "release"
    bin.install ".build/release/copymac-clipboard"
  end

  test do
    assert_match "CopyMac", shell_output("#{bin}/copymac-clipboard --help 2>&1", 1)
  end
end
