cask "copymac" do
  version "1.3.2"
  sha256 "0019dfc4b32d63c1392aa264aed2253c1e0c2fb09216f8e2cc269bbfb8bb49b5"

  url "https://github.com/alciu10/homebrew-copymac/releases/download/v#{version}/CopyMac.app.zip"
  name "CopyMac"
  desc "macOS clipboard manager with working global hotkeys"
  homepage "https://github.com/alciu10/homebrew-copymac"

  app "CopyMac.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-r", "-d", "com.apple.quarantine", "#{appdir}/CopyMac.app"],
                   sudo: false
  end
end
