require "test_helper"

# The engine's cost_basis is linear and has no trade limit: a user with
# thousands of trades still gets statements, a portfolio and a chart.
#
# The history is written in bulk (engine-built postings and totals, batched
# inserts) because replaying thousands of orders through the services one by
# one is slow; the services themselves are tested in test/services/ledger.
class LongHistoryTest < ActiveSupport::TestCase
  START = Time.utc(2026, 1, 1)
  TRADES = 3000
  PRICE = 2550

  def bulk_history(user, calibers)
    totals = Ledger::Totals.as_of(user)
    held = Hash.new(0)
    ledger_rows = []
    trade_rows = []
    postings_rows = []
    TRADES.times do |index|
      caliber = calibers[index % calibers.size]
      at = START + 60 + index # one trade a second
      sell = (index % 3).zero? && held[caliber.id].positive?
      quote = if sell
        LedgerEngine.quote_sell(qty: 1, qty_held: held[caliber.id], price: PRICE, spread_bps: 50, fee_bps: 100)
      else
        LedgerEngine.quote_buy(qty: 3, price: PRICE, spread_bps: 50, fee_bps: 100, cash_available: 10**11)
      end
      postings = sell ? LedgerEngine.build_sell(quote) : LedgerEngine.build_buy(quote)
      kind = sell ? :sell : :buy
      totals = LedgerEngine.apply_transaction(kind, postings, totals)
      held[caliber.id] = LedgerEngine.apply_trade_quantity(held[caliber.id], kind, sell ? 1 : 3)
      ledger_rows << { user_id: user.id, kind: LedgerEngine::KINDS.fetch(kind), occurred_at: at, description: "bulk" }
        .merge(LedgerTransaction.totals_attributes(totals))
      postings_rows << postings
      trade_rows << { user_id: user.id, caliber_id: caliber.id, side: LedgerEngine::SIDES.fetch(kind), quantity: sell ? 1 : 3,
                      quantity_after: held[caliber.id], price_centicents: PRICE, value_cents: quote.value, spread_cents: quote.spread,
                      fee_cents: quote.fee, occurred_at: at }
    end
    ledger_rows.each_slice(200).with_index do |slice, batch|
      ids = LedgerTransaction.insert_all!(slice, returning: %w[id]).rows.flatten
      LedgerPosting.insert_all!(ids.zip(postings_rows[batch * 200, 200]).flat_map do |id, postings|
        postings.map { |account, side, amount| { ledger_transaction_id: id, account: account, side: side, amount_cents: amount } }
      end)
      Trade.insert_all!(ids.zip(trade_rows[batch * 200, 200]).map { |id, row| row.merge(ledger_transaction_id: id) })
    end
  end

  test "a user with thousands of trades gets statements, portfolio and chart" do
    user = users(:one)
    user.update_columns(created_at: START)
    fund(user, 10**11, at: START)
    bulk_history(user, [ calibers(:nine_mm), calibers(:twenty_two) ])
    finish = START + 60 + TRADES

    assert_equal TRADES, user.trades.count
    assert_operator user.trades.sell.count, :>, 500

    rows = user.trades.engine_rows
    assert_equal TRADES, rows.size
    %i[weighted_average fifo].each do |method|
      basis = LedgerEngine.cost_basis(method: method, trades: rows, t_start: 0, t_end: finish.to_i)
      assert_equal basis.purchased, LedgerEngine.sum([ basis.consumed, basis.basis_at_end ]), "#{method}: cost is conserved"

      user.update!(cost_basis_method: method)
      period = Statements::Period.parse({ period: "max" }, origin: user.history_start, now: finish)
      report = Statements::Builder.period(user, period)
      assert_equal basis.realized_gain, report.income.realized_gain, method.to_s
      assert_equal report.closing.total_equity, Ledger::Balances.sheet(user, finish).total_equity
    end

    portfolio = Ledger::Portfolio.for(user, now: finish)
    assert_equal 2, portfolio.positions.size
    assert_equal Trade.holdings(user), portfolio.positions.to_h { [ _1.caliber.id, _1.quantity ] }
    chart = NetWorthHistory.series(user, range: "MAX", now: finish)
    assert_operator chart.size, :<=, NetWorthHistory::MAX_POINTS
    assert_equal [ START, finish ], [ chart.first.at, chart.last.at ]
    assert_equal portfolio.net_worth, chart.last.value
    assert LedgerEngine.audit_chain(user.ledger_transactions.order(:occurred_at, :id).map(&:totals))
  end
end
