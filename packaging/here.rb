class Here < Formula
  desc "Universal package manager that speaks your system's language"
  homepage "https://github.com/your-repo/here"
  url "https://github.com/your-repo/here/archive/v1.0.0.tar.gz"
  sha256 "SKIP"  # Will be updated with actual SHA256
  license "MIT"
  head "https://github.com/your-repo/here.git", branch: "main"

  depends_on "zig" => :build

  def install
    system "zig", "build", "-Doptimize=ReleaseFast"
    bin.install "zig-out/bin/here"

    # Install documentation
    doc.install "README.md"
    doc.install "CHANGELOG.md"
  end

  test do
    # Test basic functionality
    output = shell_output("#{bin}/here version")
    assert_match "here 1.0.0", output
    assert_match "Universal package manager", output

    # Test help command
    output = shell_output("#{bin}/here help")
    assert_match "Usage: here <command>", output
    assert_match "install", output
    assert_match "search", output
    assert_match "remove", output
  end

  def caveats
    <<~EOS
      here is a universal package manager that works with your system's existing
      package managers. It automatically detects available package sources and
      provides intelligent fallbacks.

      To get started:
        here help
        here search <package>
        here install <package>

      For more information, visit: https://github.com/your-repo/here
    EOS
  end
end
