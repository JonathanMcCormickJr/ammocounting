# Integer-only money formatting. No Floats anywhere, and no arithmetic: the
# engine splits the number (split_money / split_price); this only assembles strings.
module MoneyHelper
  # Cents -> "$1,776.00"; negatives "-$5.25".
  def format_cents(cents)
    parts = LedgerEngine.split_money(cents)
    "#{'-' if parts.negative}$#{number_with_delimiter(parts.whole)}.#{parts.fraction.to_s.rjust(2, '0')}"
  end

  # Centicents (1/100 cent) -> dollars, at least 2 decimals, up to 4:
  # 2500 -> "$0.25", 1050 -> "$0.105", 1 -> "$0.0001".
  def format_centicents(centicents)
    parts = LedgerEngine.split_price(centicents)
    fraction = parts.fraction.to_s.rjust(4, "0").sub(/0+\z/, "").ljust(2, "0")
    "#{'-' if parts.negative}$#{number_with_delimiter(parts.whole)}.#{fraction}"
  end
end
