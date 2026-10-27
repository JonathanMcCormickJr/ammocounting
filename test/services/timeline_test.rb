require "test_helper"

class TimelineTest < ActiveSupport::TestCase
  setup do
    PriceTick.delete_all
    Caliber.seed_catalog!(now: Time.utc(2026, 1, 1)) # fixtures' two calibers plus the catalog
  end

  def times
    PriceTick.where(caliber: calibers(:nine_mm)).order(:as_of).pluck(:as_of)
  end

  test "extends the price world one tick per game day for every caliber" do
    stored = Timeline.extend_to(Time.utc(2026, 1, 4, 15))
    assert_equal (1..3).map { |day| Time.utc(2026, 1, 1 + day) }, times.drop(1)
    assert_equal Caliber.count * 3, stored.size
    assert_equal Time.utc(2026, 1, 4), PriceTick.maximum(:as_of)
  end

  test "is idempotent and never goes backwards" do
    Timeline.extend_to(Time.utc(2026, 1, 4))
    assert_no_difference "PriceTick.count" do
      assert_empty Timeline.extend_to(Time.utc(2026, 1, 4))
      assert_empty Timeline.extend_to(Time.utc(2026, 1, 2))
    end
  end

  test "is deterministic: the same seed gives every player the same prices" do
    Timeline.extend_to(Time.utc(2026, 1, 10))
    first = PriceTick.order(:caliber_id, :as_of).pluck(:caliber_id, :as_of, :price_centicents)
    PriceTick.where("as_of > ?", Time.utc(2026, 1, 1)).delete_all
    Timeline.extend_to(Time.utc(2026, 1, 10))
    assert_equal first, PriceTick.order(:caliber_id, :as_of).pluck(:caliber_id, :as_of, :price_centicents)
  end

  test "prices stay inside the index bounds" do
    Timeline.extend_to(Time.utc(2027, 1, 1))
    prices = PriceTick.pluck(:price_centicents)
    assert_operator prices.min, :>=, PriceIndex::Mock::FLOOR_CENTICENTS
    assert_operator prices.max, :<=, PriceIndex::Mock::CEILING_CENTICENTS
  end

  test "rolls old history up into buckets" do
    Timeline.extend_to(Time.utc(2026, 3, 1))
    assert_operator PriceBucket.count, :>, 0
  end

  test "without any price history there is nothing to extend" do
    PriceTick.delete_all
    assert_empty Timeline.extend_to(Time.utc(2026, 1, 4))
  end
end
