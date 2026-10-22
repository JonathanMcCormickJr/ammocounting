require "test_helper"

class PriceIndexMockTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 5, 1, 12, 7, 30)

  test "returns one quote per caliber with the documented shape" do
    quotes = PriceIndex::Mock.new(seed: 1).current_prices(now: NOW)
    assert_equal 2, quotes.size
    quote = quotes.first
    assert_equal %i[as_of caliber_id price_centicents slug], quote.keys.sort
    assert_equal calibers(:nine_mm).id, quote[:caliber_id]
    assert_equal "9mm", quote[:slug]
    assert_equal Time.utc(2026, 5, 1, 12, 5), quote[:as_of]
    assert_kind_of Integer, quote[:price_centicents]
  end

  test "is deterministic for the same seed and different across seeds" do
    a = PriceIndex::Mock.new(seed: 1).current_prices(now: NOW)
    assert_equal a, PriceIndex::Mock.new(seed: 1).current_prices(now: NOW)
    steps = (1..20).map { PriceIndex::Mock.new(seed: _1).step_bps(1, NOW) }
    assert_operator steps.uniq.size, :>, 1
  end

  test "step_bps stays within plus or minus 2 percent over many ticks" do
    mock = PriceIndex::Mock.new(seed: 7)
    steps = (0...5000).map { mock.step_bps(3, NOW + (_1 * 300)) }
    assert_operator steps.min, :>=, -200
    assert_operator steps.max, :<=, 200
    assert_operator steps.min, :<, -150
    assert_operator steps.max, :>, 150
  end

  test "continues from the latest tick with a bounded move" do
    quote = PriceIndex::Mock.new(seed: 1).current_prices(now: NOW).first
    previous = price_ticks(:nine_mm_latest).price_centicents
    assert_operator (quote[:price_centicents] - previous).abs, :<=, previous * 2 / 100
  end

  test "uses the starting price when there are no ticks" do
    PriceTick.delete_all
    quote = PriceIndex::Mock.new(seed: 1).current_prices(now: NOW).first
    start = calibers(:nine_mm).starting_price_centicents
    assert_operator (quote[:price_centicents] - start).abs, :<=, start * 2 / 100
  end

  test "is idempotent for a tick time that already exists" do
    PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 4242, as_of: Time.utc(2026, 5, 1, 12, 5))
    quote = PriceIndex::Mock.new(seed: 1).current_prices(now: NOW).first
    assert_equal 4242, quote[:price_centicents]
  end

  test "apply_step truncates and respects floor and ceiling" do
    assert_equal 2550, PriceIndex::Mock.apply_step(2500, 200)
    assert_equal 2450, PriceIndex::Mock.apply_step(2500, -200)
    assert_equal 2500, PriceIndex::Mock.apply_step(2500, 0)
    assert_equal 101, PriceIndex::Mock.apply_step(101, -1)
    assert_equal 100, PriceIndex::Mock.apply_step(100, -200)
    assert_equal 100, PriceIndex::Mock.apply_step(101, -200)
    assert_equal 100_000, PriceIndex::Mock.apply_step(100_000, 200)
    assert_equal 100_000, PriceIndex::Mock.apply_step(99_999, 200)
  end

  test "a long walk never leaves the bounds and never uses floats" do
    mock = PriceIndex::Mock.new(seed: 99)
    price = 100
    5000.times do |i|
      price = PriceIndex::Mock.apply_step(price, mock.step_bps(9, NOW + (i * 300)))
      assert_kind_of Integer, price
      assert_includes 100..100_000, price
    end
  end
end
