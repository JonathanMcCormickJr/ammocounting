module ApplicationHelper
  # "2026-01-31 23:59:59 UTC". All statement times are UTC.
  def format_utc(time)
    time.utc.strftime("%Y-%m-%d %H:%M:%S UTC")
  end

  # Human label for a cost basis method value.
  def cost_basis_label(method)
    { "weighted_average" => "Weighted average", "fifo" => "FIFO" }.fetch(method.to_s)
  end
end
