class CalibersController < ApplicationController
  def index
    @calibers = Caliber.ordered
    @latest = PriceTick.latest_by_caliber
  end

  def show
    @caliber = Caliber.find_by!(slug: params[:slug])
    @range = ChartRange.parse(params[:range])
    @points = PriceHistory.series(@caliber, range: @range)
  end
end
