require "test_helper"

class StatementsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    ScriptedHistory.build(@user, calibers(:nine_mm))
  end

  test "every statement page requires authentication" do
    [ balance_sheet_statements_path, income_statement_statements_path, cash_flow_statements_path ].each do |path|
      get path
      assert_redirected_to new_session_path
    end
  end

  test "balance sheet as of the end of a day (hand computed)" do
    sign_in_as(@user)
    get balance_sheet_statements_path(as_of: "2026-02-05")
    assert_response :success
    assert_select "#bs-cash", "$1,375.35"
    assert_select "#bs-holdings", "$450.00"
    assert_select "#bs-assets", "$1,825.35"
    assert_select "#bs-liabilities", "$0.00"
    assert_select "#bs-capital", "$1,776.00"
    assert_select "#bs-income", "$49.35"
    assert_select "#bs-equity", "$1,825.35"
    assert_match "UTC", response.body
  end

  test "balance sheet defaults to now" do
    sign_in_as(@user)
    get balance_sheet_statements_path
    assert_response :success
    assert_select "#bs-equity", "$1,825.35"
  end

  test "income statement shows the cost basis method and its realized/unrealized split" do
    sign_in_as(@user)
    get income_statement_statements_path(from: "2026-02-01", to: "2026-02-05")
    assert_response :success
    assert_select "#method strong", "Weighted average"
    assert_select "#is-realized", "$22.50"
    assert_select "#is-unrealized", "$37.50"
    assert_select "#is-gain", "$60.00"
    assert_select "#is-costs", "-$10.65"
    assert_select "#is-net", "$49.35"

    @user.fifo!
    get income_statement_statements_path(from: "2026-02-01", to: "2026-02-05")
    assert_select "#method strong", "FIFO"
    assert_select "#is-realized", "$35.00"
    assert_select "#is-unrealized", "$25.00"
    assert_select "#is-net", "$49.35"
  end

  test "cash flow statement" do
    sign_in_as(@user)
    get cash_flow_statements_path(from: "2026-02-01", to: "2026-02-05")
    assert_response :success
    assert_select "#cf-operating", "-$10.65"
    assert_select "#cf-investing", "-$390.00"
    assert_select "#cf-financing", "$1,776.00"
    assert_select "#cf-net", "$1,375.35"
    assert_select "#cf-opening", "$0.00"
    assert_select "#cf-closing", "$1,375.35"
  end

  test "period presets render with a note when clamped" do
    sign_in_as(@user)
    get income_statement_statements_path(period: "past_year")
    assert_response :success
    assert_select "p.flash", /before your account began/
    get cash_flow_statements_path(period: "max")
    assert_response :success
    assert_select "nav[aria-label='Period presets'] a.active", "MAX"
  end

  test "bad periods show a clear error and never a 500" do
    sign_in_as(@user)
    [ { from: "garbage" }, { from: "2026-02-05", to: "2026-02-01" }, { to: "2999-01-01" },
      { from: "2026-02-30" }, { period: "decade" }, { to: "2000-01-01" }, { from: [ "x" ] }, { from: { a: "b" } } ].each do |params|
      [ income_statement_statements_path(params), cash_flow_statements_path(params) ].each do |path|
        get path
        assert_response :unprocessable_content, params.inspect
        assert_select "p.errors[role=alert]"
        assert_select "form.picker"
        assert_select "#income-statement", false
      end
    end
  end

  test "bad as-of dates are rejected" do
    sign_in_as(@user)
    [ "nope", "2999-01-01", "2000-01-01", [ "x" ] ].each do |value|
      get balance_sheet_statements_path(as_of: value)
      assert_response :unprocessable_content
      assert_select "p.errors"
      assert_select "#balance-sheet", false
      assert_select "input[name=as_of]"
    end
  end

  test "users only see their own statements" do
    other = users(:two)
    Ledger::Deposit.call(other, 999)
    sign_in_as(other)
    get balance_sheet_statements_path
    assert_select "#bs-equity", "$9.99"
    get income_statement_statements_path(period: "max")
    assert_select "#is-net", "$0.00"
    get cash_flow_statements_path(period: "max")
    assert_select "#cf-financing", "$9.99"
    assert_no_match "1,825", response.body
  end

  test "an engine integrity failure is not rendered" do
    sign_in_as(@user)
    failing = ->(*) { raise LedgerEngine::Error.new(:unbalanced, :balance_sheet) }
    with_singleton(LedgerEngine, :balance_sheet, failing) do
      assert_raises(Ledger::IntegrityError) { get balance_sheet_statements_path }
    end
  end

  test "a ledger the trades disagree with is a loud error, never an income statement" do
    sign_in_as(@user)
    unreconciled = ->(*) { raise LedgerEngine::Error.new(:not_reconciled, :period_report_checked) }
    with_singleton(LedgerEngine, :period_report_checked, unreconciled) do
      assert_raises(Ledger::IntegrityError) { get income_statement_statements_path(period: "max") }
      assert_raises(Ledger::IntegrityError) { get cash_flow_statements_path(period: "max") }
    end
  end
end
