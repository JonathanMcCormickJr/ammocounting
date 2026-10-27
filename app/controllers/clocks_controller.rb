# Fast-forwards the signed-in player's own game clock; there is no way to address
# another player's clock.
class ClocksController < ApplicationController
  def create
    from = Current.user.game_time
    now = FastForward.call(Current.user, params.expect(:jump))
    news = MarketEvent.between(from, now).map { _1.kind.headline }
    redirect_to root_path, notice: [ "Fast-forwarded to #{now.to_date}.", *news ].join(" ")
  rescue Ledger::Refused => e
    redirect_to root_path, alert: e.message
  end
end
