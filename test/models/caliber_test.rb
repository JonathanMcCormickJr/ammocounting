require "test_helper"

class CaliberTest < ActiveSupport::TestCase
  test "catalog has 15 unique calibers with positive integer prices" do
    assert_equal 15, Caliber::CATALOG.size
    assert_equal 15, Caliber::CATALOG.map { _1[1] }.uniq.size
    assert(Caliber::CATALOG.all? { |_, _, price| price.is_a?(Integer) && price.positive? })
  end

  test "seed_catalog! creates calibers with starting ticks and is idempotent" do
    PriceTick.delete_all
    now = Time.utc(2026, 3, 1, 12, 3)
    2.times { Caliber.seed_catalog!(now: now) }
    assert_equal 15, Caliber.count
    nine = Caliber.find_by!(slug: "9mm")
    assert_equal 2500, nine.starting_price_centicents
    assert_equal [ Time.utc(2026, 3, 1) ], nine.price_ticks.where(as_of: now.beginning_of_day..).pluck(:as_of)
    assert_equal 1, Caliber.find_by!(slug: "12-gauge").price_ticks.count
  end

  test "seed_catalog! keeps existing ticks and refreshes name and position" do
    PriceTick.delete_all
    Caliber.seed_catalog!
    caliber = Caliber.find_by!(slug: "9mm")
    caliber.update!(name: "old", position: 99)
    Caliber.seed_catalog!
    assert_equal "9mm", caliber.reload.name
    assert_equal 9, caliber.position
    assert_equal 1, caliber.price_ticks.count
  end

  test "validations" do
    assert_not Caliber.new(name: "", slug: "", starting_price_centicents: 0).valid?
    assert_not Caliber.new(name: "x", slug: "9mm", starting_price_centicents: 1).valid?
  end

  test "to_param is the slug" do
    assert_equal "9mm", calibers(:nine_mm).to_param
  end

  test "latest_tick returns the newest tick" do
    assert_equal price_ticks(:nine_mm_latest), calibers(:nine_mm).latest_tick
  end

  test "ordered sorts by position" do
    assert_equal [ calibers(:nine_mm), calibers(:twenty_two) ], Caliber.ordered.to_a
  end
end
