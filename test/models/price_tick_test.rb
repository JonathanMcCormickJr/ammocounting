require "test_helper"

class PriceTickTest < ActiveSupport::TestCase
  test "latest_by_caliber returns the newest tick per caliber" do
    latest = PriceTick.latest_by_caliber
    assert_equal price_ticks(:nine_mm_latest), latest[calibers(:nine_mm).id]
    assert_equal price_ticks(:twenty_two_first), latest[calibers(:twenty_two).id]
    assert_equal 2, latest.size
  end

  test "floor_time aligns to the interval" do
    assert_equal Time.utc(2026, 1, 1), PriceTick.floor_time(Time.utc(2026, 1, 1, 12, 9, 59)), "one tick per game day by default"
    assert_equal Time.utc(2026, 1, 1, 12, 5), PriceTick.floor_time(Time.utc(2026, 1, 1, 12, 9, 59), interval_minutes: 5)
    assert_equal Time.utc(2026, 1, 1, 12, 0), PriceTick.floor_time(Time.utc(2026, 1, 1, 12, 14), interval_minutes: 15)
  end

  test "validates price and uniqueness at the database" do
    assert_not PriceTick.new(caliber: calibers(:nine_mm), price_centicents: 0, as_of: Time.current).valid?
    assert_not PriceTick.new(caliber: calibers(:nine_mm), price_centicents: 5).valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 5, as_of: price_ticks(:nine_mm_first).as_of)
    end
  end
end
