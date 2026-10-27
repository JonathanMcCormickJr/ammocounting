module Ledger
  # A user's current position, computed from the ledger and trade history with
  # the engine. Everything is cents / centicents / whole rounds (Integers).
  #
  #   portfolio = Ledger::Portfolio.for(user)
  #   portfolio.cash           # Cash account balance
  #   portfolio.holdings_value # Holdings account (carrying) balance
  #   portfolio.net_worth      # total assets == total equity (liabilities are always 0)
  #   portfolio.positions      # Array<Position>, in caliber order, only calibers held
  #   portfolio.position_for(caliber) # Position or nil
  #   portfolio.sheet          # LedgerEngine::BalanceSheet
  class Portfolio
    Position = Data.define(:caliber, :quantity, :price_centicents, :market_value, :cost_basis, :unrealized_gain)

    attr_reader :user, :sheet, :positions

    # Raises Ledger::IntegrityError (loudly) if the engine's balance sheet check fails.
    # Reads inside one (deferred, read) transaction: the balance sheet, holdings
    # and trades all come from one database snapshot, never a mix of before and
    # after a concurrent trade.
    def self.for(user, now: user.game_time)
      ApplicationRecord.transaction(joinable: false) do
        sheet = balance_sheet(user, now)
        new(user, sheet, positions_for(user, now))
      end
    end

    def self.balance_sheet(user, now)
      Balances.sheet(user, now)
    rescue LedgerEngine::Error => e
      raise IntegrityError, "Ledger for user #{user.id} failed its balance sheet check (#{e.status}); assets != liabilities + equity"
    end
    private_class_method :balance_sheet

    def self.positions_for(user, now)
      quantities = Balances.quantities(user)
      return [] if quantities.empty?

      prices = Ledger.latest_prices(at: now)
      trades = user.trades.engine_rows.group_by(&:first)
      Caliber.ordered.where(id: quantities.keys).map do |caliber|
        position(user, caliber, quantities.fetch(caliber.id), prices.fetch(caliber.id), trades.fetch(caliber.id), now)
      end
    end
    private_class_method :positions_for

    def self.position(user, caliber, quantity, price, trades, now)
      market_value = LedgerEngine.market_value(quantity, price)
      basis = LedgerEngine.cost_basis(method: user.cost_basis_method, trades: trades, t_start: 0, t_end: now.to_i).basis_at_end
      Position.new(caliber: caliber, quantity: quantity, price_centicents: price, market_value: market_value,
        cost_basis: basis, unrealized_gain: LedgerEngine.portfolio_position(market_value, basis))
    end
    private_class_method :position

    def initialize(user, sheet, positions)
      @user = user
      @sheet = sheet
      @positions = positions
    end

    def cash
      sheet.cash
    end

    def holdings_value
      sheet.holdings
    end

    def net_worth
      sheet.total_equity
    end

    def position_for(caliber)
      positions.find { |position| position.caliber.id == caliber.id }
    end
  end
end
