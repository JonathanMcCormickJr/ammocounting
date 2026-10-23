# One buy or sell of whole rounds of a caliber, tied to its ledger transaction.
# quantity_after is the engine's units held of the caliber after this trade
# (LedgerEngine.apply_trade_quantity); the holding is that of the latest trade.
class Trade < ApplicationRecord
  include AppendOnly

  # The latest trade (occurred_at, then id) of a user + caliber is found with one
  # LIMIT 1 lookup on the (user_id, caliber_id, occurred_at, id) index per caliber,
  # never by scanning (or summing) the user's history.
  HOLDINGS_SQL = <<~SQL.squish.freeze
    SELECT calibers.id, trades.quantity_after FROM calibers
    INNER JOIN trades ON trades.id = (SELECT latest.id FROM trades latest
      WHERE latest.user_id = ? AND latest.caliber_id = calibers.id
      ORDER BY latest.occurred_at DESC, latest.id DESC LIMIT 1)
    WHERE trades.quantity_after > 0
  SQL
  HOLDER_USER_IDS_SQL = <<~SQL.squish.freeze
    SELECT DISTINCT users.id FROM users CROSS JOIN calibers
    INNER JOIN trades ON trades.id = (SELECT latest.id FROM trades latest
      WHERE latest.user_id = users.id AND latest.caliber_id = calibers.id
      ORDER BY latest.occurred_at DESC, latest.id DESC LIMIT 1)
    WHERE trades.quantity_after > 0
  SQL

  belongs_to :user
  belongs_to :caliber
  belongs_to :ledger_transaction

  enum :side, { buy: 0, sell: 1 }, validate: true

  validates :quantity, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10**9 }
  validates :quantity_after, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 10**9 }
  validates :price_centicents, numericality: { only_integer: true, greater_than: 0 }
  validates :value_cents, :spread_cents, :fee_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :occurred_at, presence: true
  validates :nonce, format: { with: Ledger::NONCE_FORMAT }, allow_nil: true

  # Ids of users holding any rounds, in one query (latest trade per user + caliber with rounds left).
  def self.holder_user_ids
    connection.select_values(HOLDER_USER_IDS_SQL)
  end

  # { caliber_id => whole rounds held } for the user's calibers with a positive balance.
  def self.holdings(user)
    connection.select_rows(sanitize_sql_array([ HOLDINGS_SQL, user.id ])).to_h
  end

  # Whole rounds the user holds of the caliber (0 if never traded).
  def self.held(user, caliber)
    where(user_id: user.id, caliber_id: caliber.id).order(occurred_at: :desc, id: :desc).pick(:quantity_after) || 0
  end

  # Engine-ready rows [[caliber_id, side, qty, value_cents, epoch_seconds], ...]
  # in the order cost_basis requires: caliber, then time, then id. Call on a scope:
  # user.trades.engine_rows.
  def self.engine_rows
    order(:caliber_id, :occurred_at, :id).pluck(:caliber_id, :side, :quantity, :value_cents, :occurred_at).map do |caliber_id, side, qty, value, at|
      [ caliber_id, sides.fetch(side), qty, value, at.to_i ]
    end
  end
end
