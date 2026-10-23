require "test_helper"

# Boundary hardening of the ffi wrapper (audit F1-F4): nothing reaches the
# engine unless it is an in-range Integer of the right width.
class LedgerEngineStrictTest < ActiveSupport::TestCase
  E = LedgerEngine

  def error_of(&)
    assert_raises(E::Error, &)
  end

  # --- F1: library loading and status codes ---

  test "verify_version! accepts only engine version 300" do
    assert_nil E.verify_version!(300)
    error = assert_raises(E::LibraryMissing) { E.verify_version!(200) }
    assert_includes error.message, "200"
    assert_includes error.message, "300"
  end

  test "the loaded library reports the expected version" do
    assert_equal E::EXPECTED_VERSION, E.version
  end

  test "an unknown status code is wrapped in LedgerEngine::Error" do
    error = assert_raises(E::Error) { E.send(:check!, 99, :anything) }
    assert_equal :unknown_status, error.status
    assert_equal 99, error.code
    assert_equal :anything, error.operation
    assert_includes error.message, "99"
  end

  test "known statuses carry no code beyond the symbol" do
    error = assert_raises(E::Error) { E.send(:check!, 2, :x) }
    assert_equal :out_of_range, error.status
  end

  test "LEDGER_CORE_LIB is honoured outside production" do
    env = { "LEDGER_CORE_LIB" => "/opt/x.so" }
    assert_equal "/opt/x.so", E.library_path(env: env, production: false)
  end

  test "LEDGER_CORE_LIB is ignored in production when absent or untrusted" do
    default = Rails.root.join("ledger_core/lib/libLedger_Core.so").to_s
    assert_equal default, E.library_path(env: {}, production: true)
    assert_equal default, E.library_path(env: { "LEDGER_CORE_LIB" => "/nonexistent/x.so" }, production: true)
    assert_equal default, E.library_path(env: { "LEDGER_CORE_LIB" => "relative/x.so" }, production: true)
  end

  test "in production LEDGER_CORE_LIB is used only if absolute, owned by us and not group/world writable" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "libx.so")
      File.write(lib, "")
      env = { "LEDGER_CORE_LIB" => lib }
      File.chmod(0o755, dir)
      File.chmod(0o644, lib)
      assert_equal lib, E.library_path(env: env, production: true)

      File.chmod(0o664, lib)
      assert_not_equal lib, E.library_path(env: env, production: true), "group-writable file"
      File.chmod(0o646, lib)
      assert_not_equal lib, E.library_path(env: env, production: true), "world-writable file"

      File.chmod(0o644, lib)
      File.chmod(0o775, dir)
      assert_not_equal lib, E.library_path(env: env, production: true), "group-writable directory"
      File.chmod(0o755, dir)
    end
  end

  test "in production a library owned by someone else is rejected" do
    Dir.mktmpdir do |dir|
      lib = File.join(dir, "libx.so")
      File.write(lib, "")
      File.chmod(0o644, lib)
      with_singleton(Process, :euid, -> { 0 }) do
        assert_not_equal lib, E.library_path(env: { "LEDGER_CORE_LIB" => lib }, production: true)
      end
    end
  end

  # --- F2: strict integers ---

  test "coerce_int64 passes in-range Integers through" do
    [ 0, 1, -1, 10**12, -9_223_372_036_854_775_808, 9_223_372_036_854_775_807 ].each do |n|
      assert_equal n, E.coerce_int64(n, :op)
    end
  end

  test "coerce_int64 rejects everything else with LedgerEngine::Error" do
    [ 1.0, 1000.9, Float::NAN, Float::INFINITY, "1000", nil, true, false, :a, [ 1 ], 1r, 1i ].each do |bad|
      error = assert_raises(E::Error, bad.inspect) { E.coerce_int64(bad, :op) }
      assert_equal :invalid_argument, error.status
      assert_equal :op, error.operation
    end
    [ 9_223_372_036_854_775_808, -9_223_372_036_854_775_809, 10**30 ].each do |big|
      assert_equal :out_of_range, error_of { E.coerce_int64(big, :op) }.status
    end
  end

  test "coerce enforces int32 and uint64 widths" do
    assert_equal 2_147_483_647, E.coerce(2_147_483_647, :int32, :op)
    assert_equal :out_of_range, error_of { E.coerce(2_147_483_648, :int32, :op) }.status
    assert_equal :out_of_range, error_of { E.coerce(-2_147_483_649, :int32, :op) }.status
    assert_equal 18_446_744_073_709_551_615, E.coerce(18_446_744_073_709_551_615, :uint64, :op)
    assert_equal :out_of_range, error_of { E.coerce(-1, :uint64, :op) }.status
    assert_equal :out_of_range, error_of { E.coerce(18_446_744_073_709_551_616, :uint64, :op) }.status
    assert_equal :invalid_argument, error_of { E.coerce(1.5, :uint64, :op) }.status
  end

  test "scalar arguments reject Float, String, nil and out-of-range values" do
    # Float 1000.9 used to be truncated silently by ffi to 1000.
    assert_equal :invalid_argument, error_of { E.market_value(1000.9, 2500) }.status
    assert_equal :invalid_argument, error_of { E.market_value("1000", 2500) }.status
    assert_equal :invalid_argument, error_of { E.market_value(nil, 2500) }.status
    assert_equal :out_of_range, error_of { E.market_value(2**63, 2500) }.status
    assert_equal :invalid_argument, error_of { E.quote_buy(qty: 1, price: 1.5, spread_bps: 0, fee_bps: 0, cash_available: 1) }.status
    assert_equal :invalid_argument, error_of { E.apply_trade_quantity(0, 0.0, 1) }.status
    assert_equal :out_of_range, error_of { E.apply_trade_quantity(0, 2**32, 1) }.status
    assert_equal :invalid_argument, error_of { E.cost_basis(method: :fifo, trades: [], t_start: 0.5, t_end: 1) }.status
    assert_equal :invalid_argument, error_of { E.build_deposit(100.0) }.status
    assert_equal :invalid_argument, error_of { E.split_money("1") }.status
  end

  test "bps_from_random accepts exactly 0..2**64-1" do
    assert_kind_of Integer, E.bps_from_random(0, 100)
    assert_kind_of Integer, E.bps_from_random(18_446_744_073_709_551_615, 100)
    assert_equal :out_of_range, error_of { E.bps_from_random(-1, 100) }.status
    assert_equal :out_of_range, error_of { E.bps_from_random(18_446_744_073_709_551_616, 100) }.status
    assert_equal :invalid_argument, error_of { E.bps_from_random(1.5, 100) }.status
  end

  test "array elements are coerced too" do
    assert_equal :invalid_argument, error_of { E.sum([ 1, 2.5 ]) }.status
    assert_equal :invalid_argument, error_of { E.min_max([ 1, "2" ]) }.status
    assert_equal :invalid_argument, error_of { E.ohlc([ 1, nil ]) }.status
    assert_equal :out_of_range, error_of { E.sum([ 2**63 ]) }.status
    assert_equal :invalid_argument, error_of { E.revalue([ 1.0 ], 0) }.status
  end

  test "packed rows are coerced and must have exactly the right number of fields" do
    assert_equal :invalid_argument, error_of { E.cost_basis(method: :fifo, trades: [ [ 7, 0, 1.0, 100, 1 ] ], t_start: 0, t_end: 5) }.status
    assert_equal :out_of_range, error_of { E.cost_basis(method: :fifo, trades: [ [ 2**31, 0, 1, 100, 1 ] ], t_start: 0, t_end: 5) }.status
    assert_equal :bad_argument, error_of { E.cost_basis(method: :fifo, trades: [ [ 7, 0, 1, 100 ] ], t_start: 0, t_end: 5) }.status
    assert_equal :bad_argument, error_of { E.cost_basis(method: :fifo, trades: [ [ 7, 0, 1, 100, 1, 9 ] ], t_start: 0, t_end: 5) }.status
    assert_equal :bad_argument, error_of { E.balance_sheet([ [ 1, 2 ], [ 1 ], [ 1, 2 ], [ 1, 2 ], [ 1, 2 ] ]) }.status
    assert_equal :invalid_argument, error_of { E.validate_transaction([ [ 1, 0, 1.0 ], [ 3, 1, 1 ] ]) }.status
    assert_equal :bad_argument, error_of { E.validate_transaction([ [ 1, 0 ], [ 3, 1, 1 ] ]) }.status
    assert_equal :bad_argument, error_of { E.apply_transaction(:deposit, [ [ 1, 0, 1, 9 ], [ 3, 1, 1, 9 ] ], E::ZERO_TOTALS) }.status
  end

  test "totals arrays are coerced" do
    bad = Array.new(40, 0).tap { |totals| totals[3] = 1.5 }
    assert_equal :invalid_argument, error_of { E.diff_totals(bad, E::ZERO_TOTALS) }.status
  end

  # --- F3: sample_times allocation guard ---

  test "sample_times validates max_points before allocating" do
    allocations = 0
    counting = FFI::MemoryPointer.method(:new)
    with_singleton(FFI::MemoryPointer, :new, ->(*args) { allocations += 1; counting.call(*args) }) do
      assert_equal :out_of_range, error_of { E.sample_times(0, 10, 10**9) }.status
      assert_equal :out_of_range, error_of { E.sample_times(0, 10, 1_000_001) }.status
      assert_equal :bad_argument, error_of { E.sample_times(0, 10, 0) }.status
      assert_equal :bad_argument, error_of { E.sample_times(0, 10, -5) }.status
      assert_equal :invalid_argument, error_of { E.sample_times(0, 10, 2.5) }.status
    end
    assert_equal 0, allocations
    assert_kind_of E::Sampling, E.sample_times(0, 10, 1_000_000) # the upper bound itself is accepted
  end

  # --- F4: flatten(1) and size assertions ---

  test "audit_chain and ohlc_merge flatten one level and assert the cell count" do
    assert E.audit_chain([ E::ZERO_TOTALS, E::ZERO_TOTALS ])
    candle = E::Candle.new(open: 1, high: 3, low: 1, close: 2, ticks: 2, last_as_of: 5)
    assert_equal 1, E.ohlc_merge([ candle, candle ]).open
    assert_equal :bad_argument, error_of { E.sum([ [ 1, 2 ] ]) }.status
    assert_equal :bad_argument, error_of { E.min_max([ [ 1, 2 ] ]) }.status
    assert_equal :bad_argument, error_of { E.ohlc([ [ 1, 2 ] ]) }.status
    assert_equal :bad_argument, error_of { E.revalue([ [ 1, 2 ] ], 0) }.status
  end

  test "int64s asserts that the flattened size is count times width" do
    assert_equal :bad_argument, error_of { E.send(:int64s, [ [ 1, 2 ], [ 3 ] ], :op, width: 2) }.status
    assert_equal 4, E.send(:int64s, [ [ 1, 2 ], [ 3, 4 ] ], :op, width: 2).read_array_of_int64(4).size
  end
end
