class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.9/copymac-1.3.9.zip"
  sha256 "49b05dd871262c824cc4b75998e7707520e30e04c62cc042187cfe6cd1508f15"
  version "1.3.9"
  license "MIT"

  def install
    prefix.install "CopyMac.app"
  end

  def caveats
    <<~EOS
      CopyMac has been installed as a GUI application.
      
      You can find it in your Applications folder or launch it with:
        open "#{prefix}/CopyMac.app"
      
      To create a symlink in Applications folder:
        ln -sf "#{prefix}/CopyMac.app" /Applications/
    EOS
  end

  test do
    assert_predicate prefix/"CopyMac.app", :exist?
  end
end