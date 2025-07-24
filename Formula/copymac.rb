class Copymac < Formula
  desc "macOS clipboard manager"
  homepage "https://github.com/alciu10/CopyMac-Repo"
  url "https://github.com/alciu10/CopyMac-Repo/releases/download/v1.0.0/copymac.tar.gz"
  sha256 "1eef0596bdc8dfda0edec554119078c263c1a34200913e6ed164bc9c0f0c67e6"
  version "1.0.0"

  def install
    prefix.install "CopyMac.app"
    bin.write_exec_script "#{prefix}/CopyMac.app/Contents/MacOS/CopyMac"
  end

  def caveats
    <<~EOS
      To launch CopyMac:
        open -a "#{prefix}/CopyMac.app"
    EOS
  end
end
