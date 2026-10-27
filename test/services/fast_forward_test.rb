require "test_helper"

class FastForwardTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @nine = calibers(:nine_mm)
    @start = @user.game_time.utc
    fund(@user)
  end

  test "each jump moves the game clock forward by its calendar span" do
    spans = { "day" => @start.advance(days: 1), "week" => @start.advance(weeks: 1), "month" => @start.advance(months: 1),
              "quarter" => @start.advance(months: 3), "year" => @start.advance(years: 1) }
    assert_equal FastForward::JUMPS.keys, spans.keys
    spans.each do |jump, expected|
      user = User.create!(email_address: "#{jump}@example.com", password: "password123", game_time: @start)
      assert_equal expected, FastForward.call(user, jump)
      assert_equal expected, user.reload.game_time
    end
  end

  test "the price world is generated up to the new game time, and no further" do
    FastForward.call(@user, "week")
    assert_equal @start.advance(weeks: 1), PriceTick.maximum(:as_of)
  end

  test "players have independent clocks but share one price history" do
    FastForward.call(@user, "month")
    other = users(:two)
    assert_equal @start, other.reload.game_time
    assert_equal @start, Ledger.now_for(other).utc
    assert_equal @start.advance(months: 1), Ledger.now_for(@user.reload).utc
    assert_not_equal Ledger.latest_prices(at: @user.game_time), Ledger.latest_prices(at: other.game_time),
      "the same world, seen at different game times"
  end

  test "holdings are revalued every game day passed, so the books and the chart cover the skip" do
    Ledger::Buy.call(@user, @nine, 1000)
    assert_difference "LedgerTransaction.revalue.count", 7 do
      FastForward.call(@user, "week")
    end
    days = @user.ledger_transactions.revalue.order(:occurred_at).pluck(:occurred_at)
    assert_equal (1..7).map { |day| @start.advance(days: day) }, days
    price = Ledger.latest_prices(at: @user.reload.game_time).fetch(@nine.id)
    assert_equal LedgerEngine.market_value(1000, price), Ledger::Balances.sheet(@user).holdings
    assert LedgerEngine.audit_chain(@user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
  end

  test "with no holdings nothing is posted" do
    assert_no_difference "LedgerTransaction.count" do
      FastForward.call(@user, "month")
    end
  end

  test "after a fast-forward trades happen at the new game time and prices" do
    FastForward.call(@user, "month")
    trade = Ledger::Buy.call(@user, @nine, 10)
    assert_equal @start.advance(months: 1), trade.occurred_at
    assert_equal Ledger.latest_prices(at: @user.game_time).fetch(@nine.id), trade.price_centicents
  end

  test "an unknown jump is refused and changes nothing" do
    [ "decade", "", nil, "-1 day" ].each do |jump|
      error = assert_raises(Ledger::Refused) { FastForward.call(@user, jump) }
      assert_equal "Choose how far to fast-forward.", error.message
    end
    assert_equal @start, @user.reload.game_time
  end

  test "the game ends MAX_YEARS after the start" do
    last = Rails.configuration.x.game_start.advance(years: FastForward::MAX_YEARS)
    @user.update!(game_time: last.advance(days: -1))
    extended = []
    # generating 128 years of daily prices is not what is under test here
    with_singleton(Timeline, :extend_to, ->(time, **) { extended << time }) do
      assert_equal last, FastForward.call(@user, "day")
      @error = assert_raises(Ledger::Refused) { FastForward.call(@user, "day") }
      assert_equal [ last ], extended, "a refused jump generates nothing"
    end
    assert_match "The game ends on 2154-01-01", @error.message
    assert_equal last, @user.reload.game_time
  end

  test "a failure part-way leaves the clock and the ledger untouched" do
    Ledger::Buy.call(@user, @nine, 1000)
    before = LedgerTransaction.count
    calls = 0
    original = Ledger::Revalue.method(:call)
    third_fails = lambda do |user, **kwargs|
      calls += 1
      raise LedgerEngine::Error.new(:internal_error, :revalue) if calls == 3

      original.call(user, **kwargs)
    end
    with_singleton(Ledger::Revalue, :call, third_fails) do
      assert_raises(LedgerEngine::Error) { FastForward.call(@user, "week") }
    end
    assert_equal @start, @user.reload.game_time
    assert_equal before, LedgerTransaction.count
  end
end
