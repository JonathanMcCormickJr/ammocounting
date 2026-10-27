require "test_helper"

class MarketEventTest < ActiveSupport::TestCase
  KIND = MarketEvent::Kind.new(headline: "Headline", resolution: "Resolved", ramp_days: 10, slugs: %w[9mm])
  START = Time.utc(2030, 1, 1)
  EVENT = MarketEvent::Event.new(index: 0, kind: KIND, starts_at: START, peak_at: START.advance(days: 10),
    ends_at: START.advance(days: 20), drift_bps: 150)

  def with_schedule(events, &)
    with_singleton(MarketEvent, :all, ->(**) { events }, &)
  end

  test "the schedule is deterministic, and different seeds give different histories" do
    assert_equal MarketEvent.all(seed: 1776), MarketEvent.all(seed: 1776)
    assert_not_equal MarketEvent.all(seed: 1776).map(&:starts_at), MarketEvent.all(seed: 1).map(&:starts_at)
    assert_equal MarketEvent.all, MarketEvent.all(seed: Rails.configuration.x.price_index_seed)
  end

  test "events come 6 to 10 years apart, the first after the game start, and fit in the game" do
    [ 1776, 1, 2, 3 ].each do |seed|
      events = MarketEvent.all(seed: seed)
      assert_operator events.size, :>=, 10, "a 128 year game has roughly a dozen events"
      starts = [ Rails.configuration.x.game_start, *events.map(&:starts_at) ]
      starts.each_cons(2) do |before, after|
        assert_operator after, :>=, before.advance(years: 6)
        assert_operator after, :<=, before.advance(years: 10)
      end
      assert_operator events.last.ends_at, :<=, Rails.configuration.x.game_start.advance(years: 138)
      assert(events.all? { _1.starts_at < _1.peak_at && _1.peak_at < _1.ends_at })
      assert(events.all? { MarketEvent::DRIFT_BPS.cover?(_1.drift_bps) && MarketEvent::KINDS.include?(_1.kind) })
    end
  end

  test "every kind has a headline, a resolution and a ramp short enough never to overlap the next event" do
    MarketEvent::KINDS.each do |kind|
      assert kind.headline.present? && kind.resolution.present?
      assert_operator kind.ramp_days.pred * 2, :<, 6 * 365
    end
    assert MarketEvent::KINDS.any? { _1.slugs.nil? }
    assert MarketEvent::KINDS.any? { _1.slugs }
  end

  test "an event rises, then unwinds, then is over" do
    assert_nil EVENT.phase(START.advance(seconds: -1))
    assert_equal :rising, EVENT.phase(START)
    assert_equal :rising, EVENT.phase(START.advance(days: 9))
    assert_equal :unwinding, EVENT.phase(START.advance(days: 10))
    assert_equal :unwinding, EVENT.phase(START.advance(days: 19))
    assert_nil EVENT.phase(START.advance(days: 20))
  end

  test "the news is the crisis while it builds and its end while it unwinds" do
    assert_equal "Headline", EVENT.news(START)
    assert_equal "Resolved", EVENT.news(START.advance(days: 12))
  end

  test "affects? honours the caliber list, and nil means every caliber" do
    assert EVENT.affects?("9mm")
    assert_not EVENT.affects?("22-lr")
    assert EVENT.with(kind: KIND.with(slugs: nil)).affects?("22-lr")
  end

  test "drift_bps is up while rising, down while unwinding, 0 when over or unaffected" do
    with_schedule([ EVENT ]) do
      assert_equal 150, MarketEvent.drift_bps("9mm", START)
      assert_equal(-150, MarketEvent.drift_bps("9mm", START.advance(days: 15)))
      assert_equal 0, MarketEvent.drift_bps("9mm", START.advance(days: 20))
      assert_equal 0, MarketEvent.drift_bps("22-lr", START)
      assert_equal 0, MarketEvent.drift_bps("9mm", START.advance(days: -1))
    end
  end

  test "current, started_by and between only look at the given times" do
    later = EVENT.with(index: 1, starts_at: START.advance(years: 7), peak_at: START.advance(years: 7, days: 10), ends_at: START.advance(years: 7, days: 20))
    with_schedule([ EVENT, later ]) do
      assert_equal EVENT, MarketEvent.current(START.advance(days: 3))
      assert_nil MarketEvent.current(START.advance(days: 100))
      assert_empty MarketEvent.started_by(START.advance(days: -1))
      assert_equal [ EVENT ], MarketEvent.started_by(START)
      assert_equal [ EVENT, later ], MarketEvent.started_by(START.advance(years: 8))
      assert_equal [ EVENT ], MarketEvent.between(START.advance(days: -1), START)
      assert_empty MarketEvent.between(START, START.advance(years: 1)), "an event that began at `from` was not skipped"
      assert_equal [ later ], MarketEvent.between(START, START.advance(years: 8))
    end
  end
end
