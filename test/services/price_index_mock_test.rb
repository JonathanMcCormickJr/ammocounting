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
    assert_equal Time.utc(2026, 5, 1), quote[:as_of]
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
    PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 4242, as_of: Time.utc(2026, 5, 1))
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

  test "apply_drift is a second engine step with a larger cap, bounded like the walk" do
    assert_equal 2537, PriceIndex::Mock.apply_drift(2500, 150)
    assert_equal 2463, PriceIndex::Mock.apply_drift(2500, -150)
    assert_equal 100_000, PriceIndex::Mock.apply_drift(100_000, 180)
    assert_equal 100, PriceIndex::Mock.apply_drift(100, -180)
  end

  EVENT_KIND = MarketEvent::Kind.new(headline: "Crisis", resolution: "Over", ramp_days: 20, slugs: %w[9mm])
  EVENT = MarketEvent::Event.new(index: 0, kind: EVENT_KIND, starts_at: Time.utc(2026, 1, 5), peak_at: Time.utc(2026, 1, 25),
    ends_at: Time.utc(2026, 2, 14), drift_bps: 180)

  # Daily prices of 9mm and .22 LR from 2026-01-01 over `days` days, with the given events.
  def walk(days, events)
    PriceTick.delete_all
    Caliber.find_each { |caliber| caliber.price_ticks.create!(as_of: Time.utc(2026, 1, 1), price_centicents: 2500) }
    with_singleton(MarketEvent, :all, ->(**) { events }) do
      mock = PriceIndex::Mock.new(seed: 7)
      (1..days).each { |day| TickRunner.call(now: Time.utc(2026, 1, 1).advance(days: day), index: mock) }
    end
    [ calibers(:nine_mm), calibers(:twenty_two) ].map { _1.price_ticks.order(:as_of).pluck(:price_centicents) }
  end

  test "an event spikes the affected caliber, then the crisis ends and the normal walk continues" do
    calm_nine, calm_other = walk(60, [])
    event_nine, event_other = walk(60, [ EVENT ])
    assert_equal calm_nine.first(4), event_nine.first(4), "nothing happens before the event"
    assert_operator event_nine[24], :>, calm_nine[24] * 13 / 10, "the spike at the peak"
    assert_operator event_nine[24], :>, event_nine[3] * 13 / 10
    assert_operator event_nine[60], :<, event_nine[24] * 8 / 10, "the crisis ended: prices came back down"
    assert_in_delta calm_nine[60], event_nine[60], calm_nine[60] * 0.3, "back near where the walk would have been"
    assert_equal calm_other, event_other, "unaffected calibers just walk"
    assert_not_equal calm_nine.last(10), event_nine.last(10)
  end
end
