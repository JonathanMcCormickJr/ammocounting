# Creates a user account and grants the $1,776.00 starting deposit in the same
# DB transaction: if the ledger refuses the deposit, no user is created (the
# error propagates).
class Signup
  INITIAL_FUNDS_CENTS = 177_600

  Result = Struct.new(:user) do
    def success?
      user.persisted?
    end
  end

  def self.call(attributes)
    new.call(attributes)
  end

  def call(attributes)
    user = User.new(attributes)
    User.transaction do
      grant_initial_funds(user) if user.save
    end
    Result.new(user)
  end

  # Dr Cash / Cr Owner's Capital for INITIAL_FUNDS_CENTS.
  def grant_initial_funds(user)
    Ledger::Deposit.call(user, INITIAL_FUNDS_CENTS, description: "Initial funds")
  end
end
