# Balance sheet, income statement and cash flows for the signed-in user only.
# Dates are UTC. Unusable dates render the page's picker with an error (422).
class StatementsController < ApplicationController
  rescue_from Statements::Invalid, with: :invalid_request

  def balance_sheet
    @as_of = Statements::Period.as_of(params[:as_of], origin: Current.user.history_start)
    @sheet = Statements::Builder.balance_sheet(Current.user, @as_of)
  end

  def income_statement
    load_report
  end

  def cash_flow
    load_report
  end

  private

  def load_report
    @report = Statements::Builder.period(Current.user, Statements::Period.parse(params, origin: Current.user.history_start))
  end

  def invalid_request(error)
    @error = error.message
    render :invalid, status: :unprocessable_content
  end
end
