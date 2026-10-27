require "yaml"
require "prism"

# An AST-based ratchet that keeps arithmetic on money, prices and quantities
# out of the Rails app (the proven SPARK engine does all of it; see
# ledger_core/ABI.md). Ruby is parsed with Prism (the ERB code of views is
# extracted and parsed the same way), so layout cannot hide anything: unspaced
# operators, expressions spread over several lines, `a.+(b)` and `x.send(:+, y)`
# are all just nodes. A file that does not parse is itself a violation.
#
# Flagged Ruby nodes:
#
#   * calls of arithmetic operators + - * / % ** << >> and unary - / +
#     (unless both sides are numeric literals, e.g. 10**9 or 60 * 60)
#   * operator assignment: +=  -=  *=  /=  %=  **=  <<=  >>= (every target kind)
#   * calls of computing methods: sum average minimum maximum min max minmax
#     divmod abs round floor ceil truncate clamp increment(!) decrement(!)
#     inject reduce quo fdiv pow to_f to_d to_r ... (see CALLS)
#   * send / public_send / __send__ naming an operator or computing method, or
#     with a dynamic first argument; operator symbols (:+, &:*, %i[+ -])
#   * Math, Float(), BigDecimal() and Arel arithmetic / NamedFunction
#   * SQL strings: aggregates (SUM( AVG( MIN( MAX( TOTAL( strftime( ) in any
#     string, and SQL arithmetic (a + b, price * 2 ...) in strings passed to
#     update_all, where, select, Arel.sql ... or that look like SQL statements
#
# JavaScript (app/javascript, other *.js, <script> blocks of views) has no
# parser here, so it is scanned line by line after blanking comments and string
# literals for operators, ++ / --, shifts, Math.* and number formatting. The
# app draws no charts in the browser (charts are server-rendered SVG from
# engine output), so JS needs no arithmetic and gets no blanket exemption.
#
# Anything legitimate (calendar/time arithmetic, array building, engine
# bindings ...) is listed in test/architecture/math_allowlist.yml. An entry
# names the file and the exact source text of the flagged expression (a whole
# AST node, whitespace collapsed; for JS the whole trimmed line) and says how
# many times it occurs (default 1); it needs a written reason. Entries that match
# nothing, or whose count is wrong, are themselves reported, so the list cannot rot.
class MoneyMathScanner
  Violation = Data.define(:file, :line_number, :line, :rules) do
    def to_s
      "#{file}:#{line_number}: #{rules.join(', ')}: #{line.strip}"
    end
  end

  OPERATORS = %i[+ - * / % ** << >> -@ +@].freeze
  OPERATOR_NAMES = OPERATORS.map(&:to_s).freeze
  CALLS = %i[sum average avg divmod abs round floor ceil truncate clamp minmax inject reduce min max
             minimum maximum min_by max_by quo fdiv div modulo remainder pow succ pred
             increment increment! decrement decrement! to_f to_d to_r rationalize
             cumulative_sum].freeze
  SENDS = %i[send public_send __send__].freeze
  # Calls whose string arguments are SQL.
  SQL_CALLS = %i[update_all update_counters where not select reselect order reorder group having joins
                 pluck calculate from find_by_sql count_by_sql execute exec_query select_value select_values
                 select_one select_all sanitize_sql sanitize_sql_array sanitize_sql_for_order lock
                 sql literal].freeze
  KERNEL_CALLS = %i[Float BigDecimal Rational Complex].freeze
  ARITHMETIC_CONSTANTS = %w[Math Arel::Nodes::Addition Arel::Nodes::Subtraction Arel::Nodes::Multiplication
                            Arel::Nodes::Division Arel::Nodes::NamedFunction Arel::Nodes::Sum
                            Arel::Nodes::Avg Arel::Nodes::Max Arel::Nodes::Min].freeze
  SQL_AGGREGATES = /\b(?:SUM|AVG|MIN|MAX|TOTAL)\s*\(|(?<!\.)strftime\s*\(/
  SQL_STATEMENT = /\b(?:SELECT|UPDATE|WHERE|CASE|WHEN|SET)\b/
  SQL_QUOTED = /'(?:[^']|'')*'|"[^"]*"/
  SQL_ARITHMETIC = %r{[\w)?]\s*(?:[+*/%]|-(?!-))\s*[\w(:?]}
  SQL_HARMLESS = /\bSELECT\s+\*|\w\.\*|\(\s*\*\s*\)|\bDISTINCT\s+\*/i

  PATTERNS = %w[app/**/*.rb app/**/*.erb app/**/*.jbuilder app/**/*.rake lib/**/*.rb lib/**/*.rake
                config/**/*.rb db/migrate/**/*.rb db/seeds.rb config.ru Rakefile].freeze
  JS_PATTERNS = %w[app/**/*.js].freeze
  ERB_TAG = /<%(?<kind>[-=#%]*)(?<code>.*?)[-]?%>/m
  SCRIPT_BLOCK = %r{<script\b[^>]*>(.*?)</script>}m

  JS_RULES = {
    "binary operator" => %r~[\w)\]}]\s*(?:\*\*|[-+*/%])\s*[\w(\[@:-]~,
    "increment" => /\+\+|--/,
    "assignment operator" => %r{(?:\*\*|[-+*/%]|<<|>>)=},
    "shift" => /<<|>>/,
    "Math" => /\bMath\./,
    "number method" => /\.(?:toFixed|reduce|toPrecision)\b|\b(?:parseFloat|parseInt)\(/
  }.freeze

  def initialize(root:, allowlist_path:)
    @root = Pathname(root)
    @allowlist = YAML.safe_load_file(allowlist_path, permitted_classes: [])
  end

  # Violations in the given files (default: the whole app), allowlisted ones removed.
  def violations(files = default_files)
    found = files.flat_map { |file| scan(file) }
    found = apply_allowlist(found)
    found + stale_entries(files)
  end

  def default_files
    (PATTERNS + JS_PATTERNS + script_files).flat_map { |pattern| Dir[@root.join(pattern)] }.uniq.sort
  end

  # Allowlist entries missing a file, an expression or a justification.
  def malformed_entries
    @allowlist.each_with_index.filter_map do |entry, index|
      "entry #{index + 1}" unless %w[file expression reason].all? { |key| entry[key].to_s.strip != "" }
    end
  end

  # The scanner's view of source text: whitespace runs collapsed to one space.
  def self.normalize(text)
    text.gsub(/\s+/, " ").strip
  end

  private

  # Ruby scripts in scripts/ (by extension or shebang); the others are shell.
  def script_files
    Dir[@root.join("scripts/**/*")].select { |path| File.file?(path) && ruby_script?(path) }
  end

  def ruby_script?(path)
    path.end_with?(".rb", ".rake") || File.open(path, &:readline).match?(/\A#!.*\bruby\b/)
  rescue EOFError
    false
  end

  def scan(file)
    relative = Pathname(file).relative_path_from(@root).to_s
    text = File.read(file)
    findings =
      case File.extname(file)
      when ".js" then scan_js(text)
      when ".erb" then scan_erb(text)
      else scan_ruby(text)
      end
    findings.map { |line_number, expression, rules| Violation.new(file: relative, line_number:, line: expression, rules:) }
  end

  def scan_ruby(source)
    result = Prism.parse(source)
    return [ [ result.errors.first.location.start_line, "unparseable Ruby: #{result.errors.first.message}", [ "parse error" ] ] ] if result.failure?

    RubyWalk.new(source).run(result.value)
  end

  # Ruby code of the tags, in place (so line numbers hold); text between tags
  # becomes newlines or a ';'. <script> blocks of the markup are scanned as JS.
  def scan_erb(text)
    ruby = +""
    position = 0
    text.scan(ERB_TAG) do
      match = Regexp.last_match
      ruby << filler(text[position...match.begin(0)])
      ruby << (match[:kind].include?("#") || match[:kind].include?("%") ? filler(match[0]) : match[:code])
      position = match.end(0)
    end
    ruby << filler(text[position..])
    ruby = "def erb_template;#{ruby}\nend" # so a top-level `yield` parses; line numbers hold
    scan_ruby(ruby) + script_findings(text)
  end

  def script_findings(text)
    text.to_enum(:scan, SCRIPT_BLOCK).flat_map do
      match = Regexp.last_match
      offset = text[0...match.begin(1)].count("\n")
      scan_js(match[1]).map { |line, expression, rules| [ line + offset, expression, rules ] }
    end
  end

  def filler(text)
    text.count("\n").zero? ? ";" : "\n" * text.count("\n")
  end

  def scan_js(text)
    in_comment = false
    text.lines.each_with_index.filter_map do |raw, index|
      code, in_comment = blank_js(raw, in_comment)
      rules = JS_RULES.select { |_name, pattern| code.match?(pattern) }.keys
      [ index + 1, self.class.normalize(raw), rules ] if rules.any?
    end
  end

  # Replaces JS string / template literals and comments by a bare word.
  def blank_js(raw, in_comment)
    line = raw.dup
    if in_comment
      return [ "", true ] unless line.include?("*/")

      line = line.sub(/\A.*?\*\//, "")
    end
    line = line.gsub(%r{/\*.*?\*/}, "").gsub(/"(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*'|`(?:[^`\\]|\\.)*`/, "S")
    in_comment = line.include?("/*")
    [ line.sub(%r{//.*$}, "").sub(%r{/\*.*$}, ""), in_comment ]
  end

  # Entries cover every node of `file` whose source text equals `expression`,
  # provided their number equals `occurrences` (default 1).
  def apply_allowlist(found)
    @matched = Set.new
    found.group_by { |violation| [ violation.file, self.class.normalize(violation.line) ] }.flat_map do |key, group|
      entry = @allowlist.find { |candidate| [ candidate["file"], self.class.normalize(candidate["expression"].to_s) ] == key }
      if entry && group.size == entry.fetch("occurrences", 1)
        @matched << entry
        []
      else
        group
      end
    end.sort_by { |violation| [ violation.file, violation.line_number ] }
  end

  def stale_entries(files)
    return [] unless files == default_files

    @allowlist.reject { |entry| @matched.include?(entry) }.map do |entry|
      Violation.new(file: entry["file"], line_number: 0, line: entry["expression"].to_s,
                    rules: [ "stale allowlist entry (missing, or wrong occurrences)" ])
    end
  end

  # Walks one Prism tree and collects [line, expression, rules] per flagged node.
  class RubyWalk
    def initialize(source)
      @source = source
      @found = {}
      @parts = Set.new
    end

    def run(root)
      walk(root, sql: false)
      @found.values.sort_by(&:first)
    end

    private

    def walk(node, sql:)
      check(node, sql:)
      sql ||= sql_call?(node)
      node.compact_child_nodes.each { |child| walk(child, sql:) }
    end

    def flag(node, rule, expression = source_of(node))
      entry = (@found[[ node.location.start_offset, expression ]] ||= [ node.location.start_line, expression, [] ])
      entry.last << rule unless entry.last.include?(rule)
    end

    def check(node, sql:)
      case node
      when Prism::CallNode then check_call(node)
      when Prism::StringNode, Prism::InterpolatedStringNode, Prism::XStringNode, Prism::InterpolatedXStringNode
        check_string(node, sql:)
      when Prism::SymbolNode then flag(node, "operator symbol") if OPERATOR_NAMES.include?(node.unescaped)
      when Prism::ConstantPathNode, Prism::ConstantReadNode
        flag(node, "arithmetic constant") if ARITHMETIC_CONSTANTS.include?(constant_name(node))
      else
        flag(node, "assignment operator") if node.class.name.end_with?("OperatorWriteNode") && OPERATORS.include?(node.binary_operator)
      end
    end

    def check_call(node)
      name = node.name
      flag(node, "operator") if OPERATORS.include?(name) && !literal_only?(node)
      flag(node, "computing method") if CALLS.include?(name)
      flag(node, "Kernel conversion") if KERNEL_CALLS.include?(name) && node.receiver.nil?
      check_send(node) if SENDS.include?(name)
    end

    def check_send(node)
      first = node.arguments&.arguments&.first
      literal = first.is_a?(Prism::SymbolNode) || first.is_a?(Prism::StringNode)
      return flag(node, "dynamic send") unless literal

      flag(node, "send of arithmetic") if (OPERATOR_NAMES + CALLS.map(&:to_s)).include?(first.unescaped)
    end

    def sql_call?(node)
      node.is_a?(Prism::CallNode) && SQL_CALLS.include?(node.name)
    end

    def check_string(node, sql:)
      return if @parts.include?(node.location.start_offset) # a part of a string already checked as a whole

      @parts.merge(node.parts.map { _1.location.start_offset }) if node.respond_to?(:parts)
      text = string_text(node)
      flag(node, "SQL aggregate", normalized_text(node, text)) if text.match?(SQL_AGGREGATES)
      return unless sql || text.match?(SQL_STATEMENT)

      flag(node, "SQL arithmetic", normalized_text(node, text)) if text.gsub(SQL_QUOTED, "Q").gsub(SQL_HARMLESS, "").match?(SQL_ARITHMETIC)
    end

    # Literal text of a string node (code of #{} parts is visited as nodes).
    def string_text(node)
      return node.unescaped if node.respond_to?(:unescaped)

      node.parts.map { |part| part.respond_to?(:unescaped) ? part.unescaped : "x" }.join
    end

    def normalized_text(node, text)
      heredoc = node.respond_to?(:opening_loc) && node.opening_loc&.slice&.start_with?("<<")
      MoneyMathScanner.normalize(heredoc ? text : source_of(node))
    end

    def constant_name(node)
      node.full_name
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      nil
    end

    # Both operands numeric literals (possibly nested): constant folding, no data.
    def literal_only?(node)
      operands = [ node.receiver, *node.arguments&.arguments ]
      operands.all? { |operand| numeric?(operand) }
    end

    def numeric?(node)
      case node
      when Prism::IntegerNode, Prism::FloatNode, Prism::RationalNode then true
      when Prism::ParenthesesNode then node.body.is_a?(Prism::StatementsNode) && node.body.body.size == 1 && numeric?(node.body.body.first)
      when Prism::CallNode then OPERATORS.include?(node.name) && literal_only?(node)
      else false
      end
    end

    # Source of the node, without the block of a call (a block is code of its own).
    def source_of(node)
      location = node.location
      stop = node.is_a?(Prism::CallNode) && node.block.is_a?(Prism::BlockNode) ? node.block.location.start_offset : location.end_offset
      MoneyMathScanner.normalize(@source.byteslice(location.start_offset, stop - location.start_offset))
    end
  end
end
