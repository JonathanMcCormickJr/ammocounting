require "test_helper"

# .ruby-version is the single source of truth for the Ruby version; everything
# else that names one must agree with it.
class RubyVersionTest < ActiveSupport::TestCase
  VERSION = Rails.root.join(".ruby-version").read.strip.delete_prefix("ruby-")

  test ".ruby-version names a full version" do
    assert_match(/\A\d+\.\d+\.\d+\z/, VERSION)
  end

  test "the running Ruby is the pinned one" do
    assert_equal VERSION, RUBY_VERSION
  end

  test "the Dockerfile builds on the pinned Ruby" do
    assert_equal VERSION, Rails.root.join("Dockerfile").read[/^ARG RUBY_VERSION=(\S+)/, 1]
  end

  test "the README names the pinned Ruby" do
    assert_includes Rails.root.join("README.md").read, "Ruby #{VERSION}"
  end

  test "CI never overrides the pinned Ruby" do
    assert_no_match(/^\s*ruby-version:/, Rails.root.join(".github/workflows/ci.yml").read)
  end
end
