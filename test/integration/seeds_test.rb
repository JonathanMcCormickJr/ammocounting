require "test_helper"

class SeedsTest < ActionDispatch::IntegrationTest
  test "db/seeds.rb is idempotent" do
    2.times { load Rails.root.join("db/seeds.rb") }
    assert_equal 15, Caliber.count
  end
end
