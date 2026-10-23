require "test_helper"

class SessionCleanupJobTest < ActiveJob::TestCase
  test "deletes expired sessions and keeps live ones" do
    live = users(:one).sessions.create!
    old = users(:one).sessions.create!(created_at: Session::TTL.ago - 1.minute)
    SessionCleanupJob.perform_now
    assert Session.exists?(live.id)
    assert_not Session.exists?(old.id)
  end

  test "is scheduled in recurring.yml for production" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    assert_equal "SessionCleanupJob", config.dig("production", "session_cleanup", "class")
    assert_equal "SessionCleanupJob", config.dig("development", "session_cleanup", "class")
  end
end
