require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "format_utc renders UTC seconds" do
    assert_equal "2026-02-01 03:04:05 UTC", format_utc(Time.utc(2026, 2, 1, 3, 4, 5))
    assert_equal "2026-02-01 03:04:05 UTC", format_utc(Time.new(2026, 2, 1, 5, 4, 5, "+02:00"))
  end

  test "cost_basis_label names both methods" do
    assert_equal "Weighted average", cost_basis_label("weighted_average")
    assert_equal "FIFO", cost_basis_label(:fifo)
    assert_raises(KeyError) { cost_basis_label("lifo") }
  end
end
