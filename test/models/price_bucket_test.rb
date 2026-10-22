require "test_helper"

class PriceBucketTest < ActiveSupport::TestCase
  def build(**attrs)
    PriceBucket.new({ caliber: calibers(:nine_mm), resolution: "hourly", bucket_start: Time.utc(2026, 1, 1),
                      open_centicents: 1, high_centicents: 1, low_centicents: 1, close_centicents: 1,
                      tick_count: 1, last_as_of: Time.utc(2026, 1, 1) }.merge(attrs))
  end

  test "valid bucket" do
    assert_predicate build, :valid?
  end

  test "rejects unknown resolution" do
    assert_not build(resolution: "yearly").valid?
  end

  test "requires times" do
    assert_not build(bucket_start: nil).valid?
    assert_not build(last_as_of: nil).valid?
  end
end
