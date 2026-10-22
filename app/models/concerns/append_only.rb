# Ledger rows are never changed or removed once written. Persisted records are
# read-only, so update/destroy raise ActiveRecord::ReadOnlyRecord. (Bulk SQL
# such as update_all/delete_all bypasses models; the application never uses it
# on these tables.)
module AppendOnly
  extend ActiveSupport::Concern

  def readonly?
    persisted? || super
  end

  # destroy/update check readonly?; delete skips callbacks, so refuse it too.
  def delete
    raise ActiveRecord::ReadOnlyRecord, "#{self.class.name} is append-only"
  end
end
