# Buys and sells always act on the signed-in user; there is no way to address
# another user's ledger.
class TradesController < ApplicationController
  ORDERS = { "buy" => Ledger::Buy, "sell" => Ledger::Sell }.freeze

  def create
    order = ORDERS[trade_params[:side]] or raise Ledger::Refused, "Choose buy or sell."
    caliber = Caliber.find_by!(slug: trade_params[:caliber_slug])
    trade = order.call(Current.user, caliber, trade_params[:quantity])
    redirect_to root_path, notice: "#{trade.side.capitalize}: #{trade.quantity} x #{caliber.name} at #{helpers.format_centicents(trade.price_centicents)}."
  rescue Ledger::Refused => e
    redirect_to root_path, alert: e.message
  end

  private

  def trade_params
    params.expect(trade: [ :caliber_slug, :side, :quantity ])
  end
end
