require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "unexpired excludes sessions older than the TTL" do
    fresh = users(:one).sessions.create!
    stale = users(:one).sessions.create!(created_at: Session::TTL.ago - 1.second)
    assert_includes Session.unexpired, fresh
    assert_not_includes Session.unexpired, stale
    assert_includes Session.expired, stale
    assert_not_includes Session.expired, fresh
  end
end
