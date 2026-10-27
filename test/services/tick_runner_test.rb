require "test_helper"

class TickRunnerTest < ActiveSupport::TestCase
  NOW = Time.utc(2026, 5, 1, 12, 7)

  teardown { TickRunner.after_tick.clear }

  test "stores one tick per caliber" do
    assert_difference "PriceTick.count", 2 do
      ticks = TickRunner.call(now: NOW)
      assert_equal 2, ticks.size
    end
    assert_equal Time.utc(2026, 5, 1), calibers(:nine_mm).latest_tick.as_of
  end

  test "is idempotent for the same tick time" do
    TickRunner.call(now: NOW)
    assert_no_difference "PriceTick.count" do
      assert_empty TickRunner.call(now: NOW)
    end
  end

  test "is atomic when the index fails" do
    broken = Object.new
    def broken.current_prices(now:)
      [ { caliber_id: Caliber.first.id, as_of: now, price_centicents: 5 },
        { caliber_id: Caliber.last.id, as_of: now, price_centicents: 0 } ]
    end
    assert_no_difference "PriceTick.count" do
      assert_raises(ActiveRecord::RecordInvalid) { TickRunner.call(now: NOW, index: broken) }
    end
  end

  test "the index reads inside the tick's own transaction" do
    joinable = []
    index = Object.new
    index.define_singleton_method(:current_prices) do |now:|
      joinable << PriceTick.connection.current_transaction.joinable?
      []
    end
    TickRunner.call(now: NOW, index: index)
    assert_equal [ true ], joinable
  end

  test "an existing tick is skipped, never overwritten and never an error" do
    PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 4242, as_of: Time.utc(2026, 5, 1))
    ticks = nil
    assert_difference "PriceTick.count", 1 do
      ticks = TickRunner.call(now: NOW)
    end
    assert_equal [ calibers(:twenty_two).id ], ticks.map(&:caliber_id)
    assert_equal 4242, calibers(:nine_mm).latest_tick.price_centicents
  end


  test "after_tick callables receive the stored ticks" do
    received = []
    TickRunner.after_tick << ->(ticks) { received << ticks.size }
    TickRunner.call(now: NOW)
    assert_equal [ 2 ], received
  end

  test "defaults now to current time" do
    travel_to NOW do
      TickRunner.call
    end
    assert_equal Time.utc(2026, 5, 1), PriceTick.maximum(:as_of)
  end
end
