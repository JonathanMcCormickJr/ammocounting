require "test_helper"

class LedgerTest < ActiveSupport::TestCase
  teardown { TickRunner.after_tick.clear }

  test "vocabulary matches the engine ABI" do
    assert_equal({ cash: 1, holdings: 2, owners_capital: 3, trading_gain: 4, trading_costs: 5 }, Ledger::ACCOUNTS)
    assert_equal({ debit: 0, credit: 1 }, Ledger::SIDES)
    assert_not Ledger.const_defined?(:TRADE_LIMIT), "the engine has no trade limit any more"
  end

  test "default costs are 50 bps spread and 100 bps fee" do
    assert_equal 50, Ledger.spread_bps
    assert_equal 100, Ledger.fee_bps
  end

  test "now is the current time in whole seconds" do
    assert_equal 0, Ledger.now.usec
    assert_in_delta Time.current.to_f, Ledger.now.to_f, 2
  end

  test "latest_prices maps caliber id to the newest tick" do
    assert_equal({ calibers(:nine_mm).id => 2550, calibers(:twenty_two).id => 1000 }, Ledger.latest_prices)
  end

  test "register_tick_hook is idempotent" do
    Ledger.register_tick_hook
    Ledger.register_tick_hook
    assert_equal [ Ledger::TICK_HOOK ], TickRunner.after_tick
  end

  test "the tick hook revalues holders" do
    fund(users(:one))
    Ledger::Buy.call(users(:one), calibers(:nine_mm), 1000)
    PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 2600, as_of: Time.utc(2026, 1, 1, 0, 10))
    assert_difference "LedgerTransaction.revalue.count", 1 do
      Ledger::TICK_HOOK.call([])
    end
  end

  test "a failed revaluation fails the tick job loudly after the ticks and the other users are stored" do
    Ledger.register_tick_hook
    fund(users(:one))
    Ledger::Buy.call(users(:one), calibers(:nine_mm), 1000)
    index = Object.new
    index.define_singleton_method(:current_prices) do |now:|
      [ { caliber_id: Caliber.find_by!(slug: "9mm").id, as_of: now, price_centicents: 2700 } ]
    end
    failing = ->(*) { raise LedgerEngine::Error.new(:out_of_range, :revalue) }
    with_singleton(LedgerEngine, :revalue, failing) do
      assert_raises(Ledger::RevalueFailed) { TickRunner.call(now: Time.utc(2026, 1, 1, 0, 10), index: index) }
    end
    assert_equal 2700, PriceTick.latest_by_caliber[calibers(:nine_mm).id].price_centicents
  end

  test "TickRunner revalues holders after a tick when the hook is registered" do
    Ledger.register_tick_hook
    fund(users(:one))
    Ledger::Buy.call(users(:one), calibers(:nine_mm), 1000)
    index = Object.new
    index.define_singleton_method(:current_prices) do |now:|
      [ { caliber_id: Caliber.find_by!(slug: "9mm").id, as_of: now, price_centicents: 2700 } ]
    end
    TickRunner.call(now: Time.utc(2026, 1, 1, 0, 10), index: index)
    assert_equal 27_000, Ledger::Balances.sheet(users(:one)).holdings
    assert_no_difference "LedgerTransaction.count" do
      TickRunner.call(now: Time.utc(2026, 1, 1, 0, 10), index: index) # same tick again
    end
  end
end
