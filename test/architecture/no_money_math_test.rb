require "test_helper"
require_relative "money_math_scanner"

# Ratchet: the Rails app performs no arithmetic on money, prices, quantities or
# chart coordinates (the SPARK engine does it all). See money_math_scanner.rb for
# what is flagged and math_allowlist.yml for the justified exceptions.
class NoMoneyMathTest < ActiveSupport::TestCase
  ALLOWLIST = Rails.root.join("test/architecture/math_allowlist.yml").to_s

  def scanner
    MoneyMathScanner.new(root: Rails.root, allowlist_path: ALLOWLIST)
  end

  test "the app contains no money arithmetic outside the allowlist" do
    assert_empty scanner.violations.map(&:to_s), "Do the math in LedgerEngine, or justify the line in test/architecture/math_allowlist.yml"
  end

  test "every allowlist entry names a file, a match and a justification" do
    assert_empty scanner.malformed_entries
  end

  test "allowlisted files exist" do
    YAML.safe_load_file(ALLOWLIST).each { |entry| assert Rails.root.join(entry["file"]).exist?, entry["file"] }
  end

  test "the scanner fails on planted violations in Ruby and ERB" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("app/services"))
      FileUtils.mkdir_p(root.join("app/views"))
      planted = {
        "app/services/sum.rb" => "total = amounts.sum\n",
        "app/services/divmod.rb" => "dollars, cents = value.divmod(100)\n",
        "app/services/abs.rb" => "x = balance.abs\n",
        "app/services/round.rb" => "x = (a_value).round\n",
        "app/services/floor.rb" => "x = price.floor\n",
        "app/services/ceil.rb" => "x = price.ceil\n",
        "app/services/minmax.rb" => "low, high = prices.minmax\n",
        "app/services/inject.rb" => "x = prices.inject(0) { |a, b| a }\n",
        "app/services/reduce.rb" => "x = prices.reduce(:+)\n",
        "app/services/plus.rb" => "total = cash + holdings\n",
        "app/services/minus.rb" => "gain = market - basis\n",
        "app/services/times.rb" => "value = qty * price\n",
        "app/services/divide.rb" => "share = value / count\n",
        "app/services/modulo.rb" => "r = value % 100\n",
        "app/services/assign.rb" => "total += amount\n",
        "app/services/unary.rb" => "shown = -cost\n",
        "app/services/sql.rb" => "scope.where(\"x\").select(\"SUM(amount_cents)\")\n",
        "app/services/interpolated.rb" => "label = \"Total \#{cash + holdings}\"\n",
        "app/views/page.html.erb" => "<h1>Hi</h1>\n<p><%= format_cents(a - b) %></p>\n"
      }
      planted.each { |path, source| File.write(root.join(path), source) }
      empty_allowlist = root.join("allowlist.yml").tap { _1.write("[]\n") }

      found = MoneyMathScanner.new(root: root, allowlist_path: empty_allowlist).violations
      assert_equal planted.keys.sort, found.map(&:file).sort, found.map(&:to_s).join("\n")
      assert_equal [ "app/views/page.html.erb:2" ], found.select { _1.file.end_with?(".erb") }.map { "#{_1.file}:#{_1.line_number}" }
    end
  end

  test "the scanner ignores comments, strings, regexps, literal powers and plain code" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("app/services"))
      root.join("app/services/clean.rb").write(<<~RUBY)
        # total = cash + holdings (a comment)
        LIMIT = 10**12
        label = "a - b / c"
        pattern = /\\A\\d+ - \\d+\\z/
        callback = ->(x) { x }
        flags = %i[a b]
        x = engine.sum_of(values)
        y = LedgerEngine.sum(values)
      RUBY
      empty_allowlist = root.join("allowlist.yml").tap { _1.write("[]\n") }

      found = MoneyMathScanner.new(root: root, allowlist_path: empty_allowlist).violations
      assert_equal [ "app/services/clean.rb:8" ], found.map { "#{_1.file}:#{_1.line_number}" }, "only the .sum call should be flagged"
    end
  end

  test "allowlist entries cover matching lines, and stale or malformed entries are reported" do
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      FileUtils.mkdir_p(root.join("app/services"))
      root.join("app/services/clock.rb").write("later = now - 1.day\n")
      allowlist = root.join("allowlist.yml")
      allowlist.write(YAML.dump([
        { "file" => "app/services/clock.rb", "match" => "now - 1.", "reason" => "calendar offset" },
        { "file" => "app/services/clock.rb", "match" => "never present", "reason" => "stale" },
        { "file" => "app/services/clock.rb", "match" => "x", "reason" => " " }
      ]))

      scanner = MoneyMathScanner.new(root: root, allowlist_path: allowlist)
      found = scanner.violations
      assert_equal [ "stale allowlist entry", "stale allowlist entry" ], found.flat_map(&:rules)
      assert_equal [ "entry 3" ], scanner.malformed_entries
      assert_includes found.first.to_s, "stale allowlist entry"
    end
  end
end
