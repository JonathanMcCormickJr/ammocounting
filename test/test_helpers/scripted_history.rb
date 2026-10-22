# A small hand-computable trading history for statement tests (9mm only;
# spread 50 bps, fee 100 bps; price is centicents per round, 2500 = $0.25).
#
#   T0 02-01 00:00  price 2500; deposit 177_600; user created
#   T1 02-02 12:00  buy 1000 @2500  value 25_000, spread 125, fee 250 (costs 375), cash out 25_375
#   T2 02-03 12:00  price 3000 (tick 02-03 00:00); buy 1000 @3000 after revaluing
#                   1000 held 25_000 -> 30_000 (+5_000); value 30_000, costs 150+300 = 450, cash out 30_450
#   T3 02-04 12:00  price 3200 (tick 02-04 00:00); revalue 2000 held 60_000 -> 64_000 (+4_000);
#                   sell 500 @3200 value 16_000, costs 80+160 = 240, net cash in 15_760
#   T4 02-05 00:00  price 3000; revalue 1500 held 48_000 -> 45_000 (-3_000)
#
# End state: cash 137_535, holdings 45_000, equity 182_535 = capital 177_600 +
# net income 4_935 (gain 6_000 - costs 1_065).
module ScriptedHistory
  T0 = Time.utc(2026, 2, 1)
  T1 = Time.utc(2026, 2, 2, 12)
  T2 = Time.utc(2026, 2, 3, 12)
  T3 = Time.utc(2026, 2, 4, 12)
  T4 = Time.utc(2026, 2, 5)

  def self.build(user, caliber)
    user.update_columns(created_at: T0)
    tick = ->(price, at) { PriceTick.create!(caliber: caliber, price_centicents: price, as_of: at) }
    tick.(2500, T0)
    Ledger::Deposit.call(user, 177_600, at: T0, description: "Initial funds")
    Ledger::Buy.call(user, caliber, 1000, at: T1)
    tick.(3000, Time.utc(2026, 2, 3))
    Ledger::Buy.call(user, caliber, 1000, at: T2)
    tick.(3200, Time.utc(2026, 2, 4))
    Ledger::Sell.call(user, caliber, 500, at: T3)
    tick.(3000, T4)
    Ledger::Revalue.call(user, at: T4)
  end
end
