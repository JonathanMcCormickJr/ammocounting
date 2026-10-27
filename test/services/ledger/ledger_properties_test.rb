require "test_helper"

module Ledger
  # Seeded random sequences of operations; the invariants must hold after every step.
  class LedgerPropertiesTest < ActiveSupport::TestCase
    SEEDS = [ 1776, 42, 2026 ].freeze

    SEEDS.each do |seed|
      test "debits equal credits and holdings track market value (seed #{seed})" do
        run_sequence(Random.new(seed))
      end
    end

    private

    def run_sequence(random)
      users = [ users(:one), users(:two) ]
      calibers = [ calibers(:nine_mm), calibers(:twenty_two) ]
      step_time = Time.utc(2026, 1, 2)
      performed = Hash.new(0)

      users.each { |user| fund(user, 5_000 + random.rand(200_000)) }

      120.times do |step|
        user = users.sample(random: random)
        caliber = calibers.sample(random: random)
        step_time += 30
        case random.rand(5)
        when 0
          Deposit.call(user, 1 + random.rand(50_000), at: step_time)
          performed[:deposit] += 1
        when 1, 2
          attempt(:buy, performed) { Buy.call(user, caliber, 1 + random.rand(400), at: step_time) }
        when 3
          attempt(:sell, performed) { Sell.call(user, caliber, 1 + random.rand(300), at: step_time) }
        else
          calibers.each do |each|
            price = [ [ Ledger.latest_prices.fetch(each.id) + random.rand(-300..300), 1 ].max, 10**5 ].min
            PriceTick.create!(caliber: each, price_centicents: price, as_of: step_time)
          end
          Revalue.all_holders(at: step_time)
          performed[:tick] += 1
        end

        assert_balanced("step #{step}")
        users.each { |each_user| assert_holdings_near_market(each_user, calibers.size, "step #{step}") }
      end

      users.each do |user|
        Revalue.call(user, at: step_time)
        assert_equal market_value(user), Balances.sheet(user).holdings, "holdings carrying equals engine market value"
        portfolio = Portfolio.for(user)
        assert_equal portfolio.cash + portfolio.holdings_value, portfolio.net_worth
      end
      assert_balanced("final")
      assert_each_transaction_balanced
      users.each { |user| assert_running_totals_chain(user) }
      assert_operator performed[:buy], :>, 5, "sequence should exercise buys: #{performed}"
      assert_operator performed[:sell], :>, 0, "sequence should exercise sells: #{performed}"
      assert_operator performed[:tick], :>, 0
    end

    def attempt(kind, performed)
      yield
      performed[kind] += 1
    rescue Refused
      performed[:"refused_#{kind}"] += 1
    end

    def assert_balanced(label)
      debits, credits = ledger_totals
      assert_equal debits, credits, "debits = credits across the whole ledger (#{label})"
      User.find_each do |user|
        sheet = Balances.sheet(user) # raises if the engine finds an imbalance or negative balance
        assert_equal sheet.total_assets, sheet.total_equity, label
      end
    end

    def assert_each_transaction_balanced
      LedgerTransaction.includes(:postings).find_each do |tx|
        sides = tx.postings.partition(&:debit?).map { |lines| lines.sum(&:amount_cents) }
        assert_equal sides.first, sides.last, "transaction #{tx.id} (#{tx.kind}) balances"
      end
    end

    # The persisted running totals are an engine-consistent chain (audit_chain: valid,
    # balanced, no negative cash/holdings, never decreasing), and the latest row equals an
    # independent SQL recount of the postings per kind/account/side; quantity_after
    # equals an independent recount of buys minus sells per caliber.
    def assert_running_totals_chain(user)
      rows = user.ledger_transactions.order(:occurred_at, :id)
      assert_operator rows.count, :>, 1
      assert LedgerEngine.audit_chain(rows.map(&:totals)), "audit_chain of user #{user.id}"

      counted = LedgerPosting.joins(:ledger_transaction).where(ledger_transactions: { user_id: user.id })
        .group("ledger_transactions.kind", :account, :side).sum(:amount_cents)
        .transform_keys { |kind, account, side| [ kind.is_a?(Integer) ? kind : LedgerTransaction.kinds.fetch(kind), account, side ] }
      expected = LedgerTransaction::TOTALS_COLUMNS.each_index.map do |index|
        cell, credit = index.divmod(2)
        kind, account = cell.divmod(5)
        counted.fetch([ kind, account + 1, credit ], 0)
      end
      assert_equal expected, rows.last.totals, "latest running totals equal the recounted postings"

      held = user.trades.group(:caliber_id).sum("CASE side WHEN 0 THEN quantity ELSE -quantity END").select { |_id, qty| qty > 0 }
      assert_equal held, Trade.holdings(user), "quantity_after equals the recounted holdings"
    end

    # After a trade the carrying value can differ from market by at most 1 cent
    # per caliber (per-trade rounding); a revaluation makes it exact.
    def assert_holdings_near_market(user, calibers, label)
      gap = (Balances.sheet(user).holdings - market_value(user)).abs
      assert_operator gap, :<=, calibers, "holdings within rounding of market (#{label})"
    end

    def market_value(user)
      prices = Ledger.latest_prices
      Balances.quantities(user).sum { |caliber_id, qty| LedgerEngine.market_value(qty, prices.fetch(caliber_id)) }
    end
  end
end
