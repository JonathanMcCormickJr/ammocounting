class CalibersController < ApplicationController
  def index
    @calibers = Caliber.ordered
    @latest = PriceTick.latest_by_caliber(at: Current.user.game_time)
  end

  def show
    @caliber = Caliber.find_by!(slug: params[:slug])
    @range = ChartRange.parse(params[:range])
    @points = PriceHistory.series(@caliber, range: @range, now: Current.user.game_time)
  end
end
