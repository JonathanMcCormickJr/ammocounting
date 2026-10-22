require "test_helper"

module Ledger
  class PosterTest < ActiveSupport::TestCase
    AT = Time.utc(2026, 2, 3, 4, 5, 6)
    DEPOSIT_500 = [ [ 1, 0, 500 ], [ 3, 1, 500 ] ].freeze

    test "persists a validated transaction with its postings and running totals" do
      tx = Poster.call(users(:one), kind: :deposit, at: AT, description: "Gift", postings: DEPOSIT_500)
      assert_predicate tx, :persisted?
      assert_equal "deposit", tx.kind
      assert_equal AT, tx.occurred_at
      assert_equal "Gift", tx.description
      assert_equal DEPOSIT_500, tx.postings.order(:id).pluck(:account, :side, :amount_cents)
      assert_equal [ 500, 0, 0, 0, 0, 500 ], tx.totals.first(6)
      assert_equal [ 0 ] * 34, tx.totals.last(34)
    end

    test "each transaction continues the user's latest totals, per kind" do
      first = Poster.call(users(:one), kind: :deposit, at: AT, postings: DEPOSIT_500)
      second = Poster.call(users(:one), kind: :deposit, at: AT + 1, postings: LedgerEngine.build_deposit(70))
      assert_equal [ 570, 0, 0, 0, 0, 570 ], second.totals.first(6)
      assert_equal [ 500, 0, 0, 0, 0, 500 ], first.reload.totals.first(6), "earlier rows are never rewritten"
    end

    test "totals of other users are untouched" do
      Poster.call(users(:one), kind: :deposit, at: AT, postings: DEPOSIT_500)
      other = Poster.call(users(:two), kind: :deposit, at: AT, postings: LedgerEngine.build_deposit(7))
      assert_equal [ 7, 0, 0, 0, 0, 7 ], other.totals.first(6)
    end

    test "refuses unbalanced postings and persists nothing" do
      assert_no_difference [ "LedgerTransaction.count", "LedgerPosting.count" ] do
        error = assert_raises(LedgerEngine::Error) do
          Poster.call(users(:one), kind: :deposit, at: AT, postings: [ [ 1, 0, 500 ], [ 3, 1, 499 ] ])
        end
        assert_equal :unbalanced, error.status
      end
    end

    test "refuses an empty transaction" do
      error = assert_raises(LedgerEngine::Error) { Poster.call(users(:one), kind: :deposit, at: AT, postings: []) }
      assert_equal :bad_argument, error.status
    end

    test "refuses a withdrawal that would make cash negative" do
      error = assert_raises(LedgerEngine::Error) do
        Poster.call(users(:one), kind: :buy, at: AT, postings: [ [ 2, 0, 100 ], [ 1, 1, 100 ] ])
      end
      assert_equal :negative_balance, error.status
    end

    test "refuses an entry older than the user's latest entry" do
      Poster.call(users(:one), kind: :deposit, at: AT, postings: DEPOSIT_500)
      assert_no_difference "LedgerTransaction.count" do
        error = assert_raises(Poster::OutOfOrder) { Poster.call(users(:one), kind: :deposit, at: AT - 1, postings: DEPOSIT_500) }
        assert_includes error.message, "older than the latest entry"
      end
      assert Poster.call(users(:one), kind: :deposit, at: AT, postings: DEPOSIT_500), "the same second is fine"
    end

    test "rolls back the transaction if a posting cannot be saved" do
      with_singleton(LedgerEngine, :apply_transaction, ->(_kind, _postings, _previous) { LedgerEngine::ZERO_TOTALS }) do
        assert_no_difference "LedgerTransaction.count" do
          assert_raises(ActiveRecord::RecordInvalid) do
            Poster.call(users(:one), kind: :deposit, at: AT, postings: [ [ 1, 0, 10**13 ], [ 3, 1, 10**13 ] ])
          end
        end
      end
    end
  end
end
