class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.4.0/copymac-1.4.0.zip"
  sha256 "ac77d05de036529831d385779df6dc23cb65d7ab22134873c6fa224c4ac17018"
  version "1.4.0"
  license "MIT"

  def install
    prefix.install Dir["*"]
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