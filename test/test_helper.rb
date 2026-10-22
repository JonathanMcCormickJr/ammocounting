ENV["RAILS_ENV"] ||= "test"
require "simplecov" # must precede app code; configured in .simplecov
require_relative "../config/environment"
require "rails/test_help"
require_relative "test_helpers/session_test_helper"
require_relative "test_helpers/scripted_history"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)
    parallelize_setup { |worker| SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" }
    parallelize_teardown { |_worker| SimpleCov.result }

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Rate limiting counters live in the cache; isolate tests from each other.
    setup { ActionController::Base.cache_store.clear }

    # minitest 6 ships without minitest/mock: swap a singleton method for the
    # duration of the block.
    def with_singleton(object, name, implementation)
      original = object.method(name)
      object.define_singleton_method(name, &implementation)
      yield
    ensure
      object.define_singleton_method(name, original)
    end

    # Gives a user starting cash through the real ledger. Dated long ago so that
    # tests may then trade at any later explicit time (ledger rows are time ordered per user).
    def fund(user, cents = Signup::INITIAL_FUNDS_CENTS, at: Time.utc(2000, 1, 1))
      Ledger::Deposit.call(user, cents, at: at)
    end

    # Sum of debits and credits over every posting in the database.
    def ledger_totals
      [ LedgerPosting.where(side: 0).sum(:amount_cents), LedgerPosting.where(side: 1).sum(:amount_cents) ]
    end
  end
end
