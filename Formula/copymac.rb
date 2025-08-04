class Copymac < Formula
  desc "Clipboard manager for macOS"
  homepage "https://github.com/alciu10/homebrew-copymac"
  url "https://github.com/alciu10/homebrew-copymac/releases/download/v1.3.9/copymac-1.3.9.zip"
  sha256 "23aad77f5fbaf8ef758ea9a7938cfa6e46330bed3475b1ce8c55e2355dd72e25"     version "1.3.9"
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