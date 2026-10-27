require "test_helper"

class LedgerTest < ActiveSupport::TestCase
  test "vocabulary matches the engine ABI" do
    assert_equal({ cash: 1, holdings: 2, owners_capital: 3, trading_gain: 4, trading_costs: 5 }, Ledger::ACCOUNTS)
    assert_equal({ debit: 0, credit: 1 }, Ledger::SIDES)
    assert_not Ledger.const_defined?(:TRADE_LIMIT), "the engine has no trade limit any more"
  end

  test "default costs are 50 bps spread and 100 bps fee" do
    assert_equal 50, Ledger.spread_bps
    assert_equal 100, Ledger.fee_bps
  end

  test "latest_prices maps caliber id to the newest tick" do
    assert_equal({ calibers(:nine_mm).id => 2550, calibers(:twenty_two).id => 1000 }, Ledger.latest_prices)
  end

  test "there is no real-time revaluation hook: revaluation happens when a player fast-forwards" do
    assert_not Ledger.const_defined?(:TICK_HOOK)
    assert_not Ledger.respond_to?(:register_tick_hook)
  end
end
