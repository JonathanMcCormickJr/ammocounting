require "test_helper"

# The engine is stateless and reentrant (ABI.md); these run the REAL library from
# many threads and from a forked child (Puma cluster mode forks after boot).
class LedgerEngineConcurrencyTest < ActiveSupport::TestCase
  E = LedgerEngine

  def workload(seed)
    qty = 100 + seed
    [ E.market_value(qty, 2500),
      E.quote_buy(qty: qty, price: 2500, spread_bps: 50, fee_bps: 100, cash_available: 10**9).total_cash_out,
      E.sum([ qty, qty, qty ]),
      E.cost_basis(method: :fifo, trades: [ [ 7, 0, qty, 1000, 10 ], [ 7, 1, qty, 1500, 20 ] ], t_start: 0, t_end: 30).realized_gain,
      E.sample_times(0, 1000, 5).times ]
  end

  test "eight threads get the same answers as a single thread" do
    expected = (0...8).map { |seed| workload(seed) }
    results = Array.new(8)
    threads = (0...8).map do |seed|
      Thread.new do
        results[seed] = Array.new(200) { workload(seed) }.uniq
      end
    end
    threads.each(&:join)
    assert_equal expected.map { |one| [ one ] }, results
  end

  test "errors raised from threads are per-call and do not leak" do
    errors = (0...8).map do |_|
      Thread.new { assert_raises(E::Refusal) { E.quote_buy(qty: 10, price: 2500, spread_bps: 0, fee_bps: 0, cash_available: 1) }.status }
    end.map(&:value)
    assert_equal [ :insufficient_cash ] * 8, errors
  end

  test "the library works in a forked child" do
    expected = workload(3)
    reader, writer = IO.pipe
    reader.binmode
    writer.binmode
    pid = fork do
      reader.close
      writer.write(Marshal.dump(workload(3)))
      writer.close
      exit!(0)
    end
    writer.close
    child = Marshal.load(reader.read)
    _, status = Process.wait2(pid)
    assert status.success?
    assert_equal expected, child
  ensure
    reader&.close
  end
end
