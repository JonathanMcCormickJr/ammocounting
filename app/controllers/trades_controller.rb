# Buys and sells always act on the signed-in user; there is no way to address
# another user's ledger.
class TradesController < ApplicationController
  ORDERS = { "buy" => Ledger::Buy, "sell" => Ledger::Sell }.freeze

  def create
    order = ORDERS[trade_params[:side]] or raise Ledger::Refused, "Choose buy or sell."
    caliber = Caliber.find_by!(slug: trade_params[:caliber_slug])
    trade = order.call(Current.user, caliber, trade_params[:quantity], nonce: trade_params.require(:nonce))
    redirect_to root_path, notice: summary(trade)
  rescue Ledger::Replay => e
    redirect_to root_path, notice: "This order was already placed. #{summary(e.trade)}"
  rescue Ledger::Refused => e
    redirect_to root_path, alert: e.message
  end

  private

  def trade_params
    params.expect(trade: [ :caliber_slug, :side, :quantity, :nonce ])
  end

  def summary(trade)
    "#{trade.side.capitalize}: #{trade.quantity} x #{trade.caliber.name} at #{helpers.format_centicents(trade.price_centicents)}."
  end
end
