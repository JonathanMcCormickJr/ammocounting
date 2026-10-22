class DashboardController < ApplicationController
  # Cash, holdings, net worth and net worth history for the signed-in user
  # only; the market table holds the buy/sell forms.
  def show
    @user = Current.user
    @portfolio = Ledger::Portfolio.for(@user)
    @calibers = Caliber.ordered
    @prices = Ledger.latest_prices
    @range = ChartRange.parse(params[:range])
    @history = NetWorthHistory.series(@user, range: @range)
  end
end
