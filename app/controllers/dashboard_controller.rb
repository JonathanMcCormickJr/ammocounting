class DashboardController < ApplicationController
  # Cash, holdings, net worth and net worth history for the signed-in user
  # only; the market table holds the buy/sell forms.
  def show
    @user = Current.user
    @portfolio = Ledger::Portfolio.for(@user)
    @calibers = Caliber.ordered
    @prices = Ledger.latest_prices(at: @user.game_time)
    @event = MarketEvent.current(@user.game_time)
    @past_events = MarketEvent.started_by(@user.game_time).last(5).reverse
    @range = ChartRange.parse(params[:range])
    @history = NetWorthHistory.series(@user, range: @range)
  end
end
