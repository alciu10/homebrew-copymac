cask "copymac" do
  version "1.3.2"
  sha256 "22a280289dc791646cd162045a3fb414392994469c4f78b7546c3e3d87034278"

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
