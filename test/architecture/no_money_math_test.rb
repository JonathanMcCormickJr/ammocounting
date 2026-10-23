require "test_helper"
require_relative "money_math_scanner"

# Ratchet: the Rails app performs no arithmetic on money, prices, quantities or
# chart coordinates (the SPARK engine does it all). See money_math_scanner.rb for
# what is flagged and math_allowlist.yml for the justified exceptions.
class NoMoneyMathTest < ActiveSupport::TestCase
  ALLOWLIST = Rails.root.join("test/architecture/math_allowlist.yml").to_s

  # Source planted into a scratch project, one file each: each must be flagged.
  PLANTED = {
    "app/services/sum.rb" => "total = amounts.sum\n",
    "app/services/average.rb" => "x = Entry.average(:amount_cents)\n",
    "app/services/clamp.rb" => "x = price.clamp(1, 1000)\n",
    "app/services/increment.rb" => "entry.increment!(:amount_cents)\n",
    "app/services/decrement.rb" => "entry.decrement!(:amount_cents, 5)\n",
    "app/services/divmod.rb" => "dollars, cents = value.divmod(100)\n",
    "app/services/abs.rb" => "x = balance.abs\n",
    "app/services/round.rb" => "x = (a_value).round\n",
    "app/services/floor.rb" => "x = price.floor\n",
    "app/services/ceil.rb" => "x = price.ceil\n",
    "app/services/minmax.rb" => "low, high = prices.minmax\n",
    "app/services/inject.rb" => "x = prices.inject(0) { |a, b| a }\n",
    "app/services/reduce.rb" => "x = prices.reduce(:+)\n",
    "app/services/to_f.rb" => "x = price.to_f\n",
    "app/services/plus.rb" => "total = cash + holdings\n",
    "app/services/minus.rb" => "gain = market - basis\n",
    "app/services/times.rb" => "value = qty * price\n",
    "app/services/divide.rb" => "share = value / count\n",
    "app/services/modulo.rb" => "r = value % 100\n",
    "app/services/power.rb" => "r = base ** exponent\n",
    "app/services/unary.rb" => "shown = -cost\n",
    "app/services/unspaced_plus.rb" => "total = cash+holdings\n",
    "app/services/unspaced_times.rb" => "value = qty*price\n",
    "app/services/unspaced_minus.rb" => "gain = market-basis\n",
    "app/services/multiline.rb" => "total = cash +\n  holdings\n",
    "app/services/multiline_dot.rb" => "total = cash\n  .+(holdings)\n",
    "app/services/dot_operator.rb" => "total = cash.+(holdings)\n",
    "app/services/safe_dot_operator.rb" => "total = cash&.+(holdings)\n",
    "app/services/send_operator.rb" => "total = cash.send(:+, holdings)\n",
    "app/services/send_string.rb" => "total = cash.public_send(\"*\", holdings)\n",
    "app/services/send_method.rb" => "total = values.__send__(:sum)\n",
    "app/services/send_dynamic.rb" => "total = cash.send(operation, holdings)\n",
    "app/services/symbol_proc.rb" => "totals = pairs.map(&:+)\n",
    "app/services/symbol_list.rb" => "operators = %i[+ -]\n",
    "app/services/left_shift.rb" => "x = value << 2\n",
    "app/services/right_shift.rb" => "x = value >> 2\n",
    "app/services/assign.rb" => "total += amount\n",
    "app/services/assign_ivar.rb" => "@total -= amount\n",
    "app/services/assign_index.rb" => "totals[:cash] *= 2\n",
    "app/services/assign_call.rb" => "entry.amount /= 2\n",
    "app/services/assign_shift.rb" => "mask <<= 1\n",
    "app/services/interpolated.rb" => "label = \"Total \#{cash + holdings}\"\n",
    "app/services/math.rb" => "x = Math.sqrt(count)\n",
    "app/services/float.rb" => "x = Float(text)\n",
    "app/services/bigdecimal.rb" => "x = BigDecimal(text)\n",
    "app/services/arel_math.rb" => "x = Arel::Nodes::Addition.new(a, b)\n",
    "app/services/sql_aggregate.rb" => "scope.where(\"x\").select(\"SUM(amount_cents)\")\n",
    "app/services/sql_aggregate_var.rb" => "QUERY = \"SELECT AVG(price_cents) FROM ticks\"\n",
    "app/services/sql_update_all.rb" => "Entry.update_all(\"balance = balance + 5\")\n",
    "app/services/sql_update_hash.rb" => "Entry.update_all(balance: Arel.sql(\"balance*2\"))\n",
    "app/services/sql_arel_sql.rb" => "Entry.order(Arel.sql(\"price_cents - fee_cents\"))\n",
    "app/services/sql_where.rb" => "Entry.where(\"amount_cents - fee_cents > ?\", 5)\n",
    "app/services/sql_select.rb" => "Entry.select(\"price_cents * qty AS value\")\n",
    "app/services/sql_interpolated.rb" => "Entry.where(\"a + \#{column} > 1\")\n",
    "app/services/sql_heredoc.rb" => "Entry.find_by_sql(<<~SQL)\n  SELECT\n    price + fee\n  FROM entries\n  SQL\n",
    "app/services/sql_statement_var.rb" => "SQL = \"UPDATE entries SET balance = balance - 1\"\n",
    "app/services/unparseable.rb" => "def broken(\n",
    "app/views/page.html.erb" => "<h1>Hi</h1>\n<p><%= format_cents(a - b) %></p>\n",
    "app/views/block.html.erb" => "<%= form_with url: x do |f| %>\n<%= f.label a * b %>\n<% end %>\n",
    "app/views/broken.html.erb" => "<%= format_cents(a - %>\n",
    "app/views/script.html.erb" => "<p>Hi</p>\n<script>\n  const total = a + b\n</script>\n",
    "app/javascript/controllers/chart_controller.js" => "connect() {\n  this.x = this.a * this.b\n}\n",
    "app/javascript/counter.js" => "count++\n",
    "app/javascript/rounding.js" => "const label = value.toFixed(2)\n",
    "app/javascript/maths.js" => "const root = Math.sqrt(n)\n",
    "app/javascript/shift.js" => "const mask = 1 << n\n",
    "app/javascript/assign.js" => "total += amount\n",
    "app/javascript/after_comment.js" => "/* start\n  still comment */ total = a - b\n",
    "lib/tasks/report.rake" => "task report: :environment do\n  puts a + b\nend\n",
    "lib/helper.rb" => "x = a * b\n",
    "config/initializers/fees.rb" => "FEE = base * 2\n",
    "config/environments/staging.rb" => "x = a - b\n",
    "db/migrate/20260101000000_backfill.rb" => "class Backfill\n  def up = execute(\"UPDATE t SET a = a + 1\")\nend\n",
    "db/seeds.rb" => "grant = base * 2\n",
    "script/tool.rb" => "x = a + b\n",
    "script/tool" => "#!/usr/bin/env ruby\nx = a + b\n",
    "config.ru" => "x = a + b\n"
  }.freeze

  def scanner
    MoneyMathScanner.new(root: Rails.root, allowlist_path: ALLOWLIST)
  end

  # Scans `sources` ({ path => text }) in a scratch project with the given allowlist entries.
  def scan_sources(sources, allowlist = [])
    Dir.mktmpdir do |dir|
      root = Pathname(dir)
      sources.each do |path, text|
        root.join(path).dirname.mkpath
        root.join(path).write(text)
      end
      list = root.join("allowlist.yml").tap { _1.write(YAML.dump(allowlist)) }
      yield MoneyMathScanner.new(root: root, allowlist_path: list)
    end
  end

  def locations(violations)
    violations.map { "#{_1.file}:#{_1.line_number}" }
  end

  test "the app contains no money arithmetic outside the allowlist" do
    assert_empty scanner.violations.map(&:to_s), "Do the math in LedgerEngine, or justify the expression in test/architecture/math_allowlist.yml"
  end

  test "every allowlist entry names a file, an expression and a justification" do
    assert_empty scanner.malformed_entries
  end

  test "allowlisted files exist" do
    YAML.safe_load_file(ALLOWLIST).each { |entry| assert Rails.root.join(entry["file"]).exist?, entry["file"] }
  end

  test "the scanner covers app, lib, config, db, script and the Ruby files of views" do
    files = scanner.default_files.map { Pathname(_1).relative_path_from(Rails.root).to_s }
    %w[app/models/user.rb app/views/dashboard/show.html.erb app/javascript/application.js
       config/initializers/ledger.rb config/environments/production.rb db/migrate/20261023000100_create_ledger.rb].each do |path|
      assert_includes files, path
    end
    assert(files.none? { _1.start_with?("test/", "ledger_core/", "vendor/") })
  end

  test "the scanner fails on every planted violation" do
    scan_sources(PLANTED) do |scanner|
      found = scanner.violations
      assert_equal PLANTED.keys.sort, found.map(&:file).uniq.sort, found.map(&:to_s).join("\n")
    end
  end

  test "each planted violation is named by the right rule and line" do
    scan_sources(PLANTED) do |scanner|
      found = scanner.violations.group_by(&:file)
      assert_equal [ 2 ], found.fetch("app/views/page.html.erb").map(&:line_number)
      assert_equal [ 2 ], found.fetch("app/views/block.html.erb").map(&:line_number)
      assert_equal [ 3 ], found.fetch("app/views/script.html.erb").map(&:line_number)
      assert_equal [ 1 ], found.fetch("app/services/multiline.rb").map(&:line_number)
      assert_equal [ 2 ], found.fetch("app/javascript/controllers/chart_controller.js").map(&:line_number)
      assert_equal [ 2 ], found.fetch("app/javascript/after_comment.js").map(&:line_number)
      assert_equal [ 1 ], found.fetch("app/services/sql_heredoc.rb").map(&:line_number)
      assert_equal [ "parse error" ], found.fetch("app/services/unparseable.rb").flat_map(&:rules)
      assert_equal [ "parse error" ], found.fetch("app/views/broken.html.erb").flat_map(&:rules)
      assert_equal [ "dynamic send" ], found.fetch("app/services/send_dynamic.rb").flat_map(&:rules)
      assert_includes found.fetch("app/services/send_operator.rb").flat_map(&:rules), "send of arithmetic"
      assert_equal [ "SQL arithmetic" ], found.fetch("app/services/sql_update_all.rb").flat_map(&:rules)
      assert_equal [ "SQL aggregate" ], found.fetch("app/services/sql_aggregate_var.rb").flat_map(&:rules)
      assert_includes found.fetch("app/services/multiline.rb").first.line, "cash + holdings"
    end
  end

  test "the scanner ignores comments, strings, regexps, constant arithmetic and plain code" do
    clean = {
      "app/services/clean.rb" => <<~RUBY,
        # total = cash + holdings (a comment)
        LIMIT = 10**12
        SECONDS = 60 * 60 * 24
        NEGATIVE = -5
        label = "a - b / c"
        pattern = /\\A\\d+ - \\d+\\z/
        callback = ->(x) { x }
        flags = %i[a b]
        x = engine.sum_of(values)
        scope = Entry.where("created_at > ?", time).where("name LIKE '%x%'").where("day = '2026-01-01'")
        all = Entry.select("*").select("entries.*").select("COUNT(*)")
        ordered = Entry.order("occurred_at DESC, id DESC").where(kind: "-")
        total = LedgerEngine.balance(values)
      RUBY
      "app/views/page.html.erb" => "<%# a - b %>\n<%% a - b %>\n<h1><%= name -%></h1>\n<% if a == b %>x - y<% end %>\n<%= yield %>\n",
      "app/javascript/clean.js" => <<~JS
        // total = a + b (a comment)
        /* a * b
           c / d */
        import { Controller } from "@hotwired/stimulus"
        const label = 'a - b' + `${x}`.length
        const url = "https://example.test/a/b" // a / b
        connect() { this.element.textContent = "x" }
      JS
    }
    scan_sources(clean) do |scanner|
      assert_equal [ "app/javascript/clean.js:5" ], locations(scanner.violations), "only the string + length concatenation"
    end
  end

  test "constant arithmetic is the only exemption: a literal beside data is flagged" do
    scan_sources("app/services/mix.rb" => "a = 10**9\nb = 10**9 * rate\nc = (60 * 60) * 24\nd = (-1) + x\n") do |scanner|
      assert_equal [ "app/services/mix.rb:2", "app/services/mix.rb:4" ], locations(scanner.violations)
    end
  end

  test "an allowlist entry covers only the exact expression, not a substring of it" do
    sources = { "app/services/clock.rb" => "later = now - 1.day\nearlier = other - 1.day - gap\n" }
    entries = [ { "file" => "app/services/clock.rb", "expression" => "now - 1.day", "reason" => "calendar offset" } ]
    scan_sources(sources, entries) do |scanner|
      assert_equal [ "app/services/clock.rb:2" ] * 2, locations(scanner.violations).first(2), "other - 1.day - gap is another expression"
    end
  end

  test "an allowlist entry matches whitespace-insensitively across lines and only in its file" do
    sources = { "app/services/clock.rb" => "later = now -\n  1.day\n", "app/services/other.rb" => "later = now - 1.day\n" }
    entries = [ { "file" => "app/services/clock.rb", "expression" => "now - 1.day", "reason" => "calendar offset" } ]
    scan_sources(sources, entries) do |scanner|
      assert_equal [ "app/services/other.rb:1" ], locations(scanner.violations)
    end
  end

  test "an allowlist entry covers exactly its occurrence count" do
    sources = { "app/services/clock.rb" => "a = now - 1.day\nb = now - 1.day\n" }
    one = [ { "file" => "app/services/clock.rb", "expression" => "now - 1.day", "reason" => "calendar" } ]
    two = [ one.first.merge("occurrences" => 2) ]
    scan_sources(sources, one) do |scanner|
      assert_equal [ "app/services/clock.rb:1", "app/services/clock.rb:2", "app/services/clock.rb:0" ], locations(scanner.violations)
    end
    scan_sources(sources, two) { |scanner| assert_empty scanner.violations }
  end

  test "allowlisted nodes inside an allowlisted node are still reported" do
    sources = { "app/services/clock.rb" => "x = [ a, b ].min.floor\n" }
    entries = [ { "file" => "app/services/clock.rb", "expression" => "[ a, b ].min.floor", "reason" => "times" } ]
    scan_sources(sources, entries) do |scanner|
      assert_equal [ "[ a, b ].min" ], scanner.violations.map(&:line)
    end
  end

  test "JS allowlist entries match the whole trimmed line" do
    sources = { "app/javascript/count.js" => "  count++  \nother++\n" }
    entries = [ { "file" => "app/javascript/count.js", "expression" => "count++", "reason" => "loop counter" } ]
    scan_sources(sources, entries) do |scanner|
      assert_equal [ "app/javascript/count.js:2" ], locations(scanner.violations)
    end
  end

  test "stale and malformed allowlist entries are reported" do
    sources = { "app/services/clock.rb" => "later = now - 1.day\n" }
    entries = [
      { "file" => "app/services/clock.rb", "expression" => "now - 1.day", "reason" => "calendar offset" },
      { "file" => "app/services/clock.rb", "expression" => "never present", "reason" => "stale" },
      { "file" => "app/services/clock.rb", "expression" => "x", "reason" => " " }
    ]
    scan_sources(sources, entries) do |scanner|
      found = scanner.violations
      assert_equal 2, found.size
      assert(found.all? { _1.rules.first.start_with?("stale allowlist entry") })
      assert_equal [ "entry 3" ], scanner.malformed_entries
      assert_includes found.first.to_s, "stale allowlist entry"
    end
  end

  test "a script without a shebang or a ruby extension is not scanned, and empty files are fine" do
    scan_sources("script/run" => "#!/usr/bin/env bash\nx=$((a + b))\n", "script/empty" => "", "script/.keep" => "\n") do |scanner|
      assert_empty scanner.violations
    end
  end
end
