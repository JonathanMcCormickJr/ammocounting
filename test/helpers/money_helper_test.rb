require "test_helper"

class MoneyHelperTest < ActionView::TestCase
  test "format_cents" do
    assert_equal "$0.00", format_cents(0)
    assert_equal "$0.05", format_cents(5)
    assert_equal "$1,776.00", format_cents(177_600)
    assert_equal "$12,345,678.90", format_cents(1_234_567_890)
  end

  test "format_cents is computed by the engine: whole cents, extremes and negative zero dollars" do
    assert_equal "-$0.05", format_cents(-5)
    assert_equal "$92,233,720,368,547,758.07", format_cents(2**63 - 1)
    assert_equal "-$92,233,720,368,547,758.08", format_cents(-(2**63))
  end

  test "format_cents negatives" do
    assert_equal "-$5.25", format_cents(-525)
    assert_equal "-$1,776.00", format_cents(-177_600)
  end

  test "format_centicents" do
    assert_equal "$0.25", format_centicents(2500)
    assert_equal "$0.105", format_centicents(1050)
    assert_equal "$0.10", format_centicents(1000)
    assert_equal "$0.1005", format_centicents(1005)
    assert_equal "$0.0001", format_centicents(1)
    assert_equal "$0.00", format_centicents(0)
    assert_equal "$10.00", format_centicents(100_000)
    assert_equal "$1,234.5678", format_centicents(12_345_678)
  end

  test "format_centicents negatives" do
    assert_equal "-$0.105", format_centicents(-1050)
  end

  test "returns strings without floats" do
    assert_no_match(/e/, format_centicents(10**15))
  end
end
