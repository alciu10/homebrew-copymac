class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.9/copymac-1.3.9.zip"
  sha256 "73740bc6f7fad4b782bfeb0acb59ebc95cdfa1b51e88ffa618da968afe7aadc9"
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
