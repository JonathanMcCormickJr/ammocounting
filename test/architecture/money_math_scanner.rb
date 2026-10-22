require "yaml"

# A deliberately simple, line-based scanner that keeps arithmetic on money,
# prices and quantities out of the Rails app (the proven SPARK engine does all
# of it; see ledger_core/ABI.md). It is a ratchet, not a parser: it looks at
# each line of Ruby (and the Ruby inside ERB tags) after blanking string
# literals, regexp literals and comments, and reports
#
#   * method calls that compute: .sum .divmod .abs .round .floor .ceil
#     .truncate .minmax .inject .reduce .min .max .minimum .maximum ...
#   * binary + - * / % (and ** and the assignment forms += -= ...) and unary
#     minus on anything that is not a bare numeric literal
#   * SQL aggregates in SQL strings: SUM( AVG( MIN( MAX( strftime(
#
# Anything legitimate (calendar/time arithmetic, array indexing, string
# building ...) is listed in test/architecture/math_allowlist.yml with a
# written justification. An allowlist entry names a file and a substring of the
# offending line; it covers every line of that file containing the substring.
# Entries that match nothing are themselves reported, so the list cannot rot.
class MoneyMathScanner
  Violation = Data.define(:file, :line_number, :line, :rules) do
    def to_s
      "#{file}:#{line_number}: #{rules.join(', ')}: #{line.strip}"
    end
  end

  CALLS = %w[sum divmod abs round floor ceil truncate minmax inject reduce min max minimum maximum
             min_by max_by quo fdiv div modulo remainder pow succ pred].freeze
  SQL_AGGREGATES = /\b(?:SUM|AVG|MIN|MAX|TOTAL)\s*\(|(?<!\.)strftime\s*\(/

  RULES = {
    "method call" => /\.(?:#{CALLS.join('|')})\b/,
    "binary operator" => %r~[\w)\]}]\s+(?:\*\*|[-+*/%])\s+[\w(\[@:-]~,
    "operator without spaces" => /[\w)\]]\*\*[\w(]/,
    "assignment operator" => /\s(?:\*\*|[-+*\/%])=\s/,
    "unary minus" => /(?:\A|[\s(,\[=])-[@a-z_(]/i
  }.freeze

  ERB_CODE = /<%[=-]?(.*?)-?%>/m
  PATTERNS = %w[app/**/*.rb app/**/*.erb config/initializers/**/*.rb lib/**/*.rb].freeze

  def initialize(root:, allowlist_path:)
    @root = Pathname(root)
    @allowlist = YAML.safe_load_file(allowlist_path, permitted_classes: [])
    @used = Set.new
  end

  # Violations in the given files (default: the whole app), allowlisted lines removed.
  def violations(files = default_files)
    found = files.flat_map { |file| scan(file) }.reject { |violation| allowed?(violation) }
    found + stale_entries(files)
  end

  def default_files
    PATTERNS.flat_map { |pattern| Dir[@root.join(pattern)] }.sort
  end

  # Allowlist entries missing a file, a match or a justification.
  def malformed_entries
    @allowlist.each_with_index.filter_map do |entry, index|
      "entry #{index + 1}" unless %w[file match reason].all? { |key| entry[key].to_s.strip != "" }
    end
  end

  private

  def scan(file)
    relative = Pathname(file).relative_path_from(@root).to_s
    code_lines(file).filter_map do |number, raw|
      rules = rules_for(raw)
      Violation.new(file: relative, line_number: number, line: raw, rules: rules) if rules.any?
    end
  end

  # [[line_number, raw_line], ...] of Ruby code (the Ruby parts of an ERB file).
  def code_lines(file)
    text = File.read(file)
    return text.lines.each_with_index.map { |line, index| [ index + 1, line ] } unless file.end_with?(".erb")

    text.to_enum(:scan, ERB_CODE).flat_map do
      match = Regexp.last_match
      first = text[0...match.begin(1)].count("\n") + 1
      match[1].lines.each_with_index.map { |line, index| [ first + index, line ] }
    end
  end

  def rules_for(raw)
    code = blank_literals(raw)
    found = RULES.select { |_name, pattern| code.match?(pattern) }.keys
    found << "SQL aggregate" if raw.match?(SQL_AGGREGATES)
    found
  end

  # Replaces string and regexp literals by a bare word (keeping any #{...} code
  # of interpolated strings), drops comments and literal-only powers (10**9).
  def blank_literals(raw)
    raw.gsub(/"((?:[^"\\]|\\.)*)"/) { "S #{Regexp.last_match(1).scan(/#\{(.*?)\}/).flatten.join(' ; ')} " }
       .gsub(/'(?:[^'\\]|\\.)*'/, "S")
       .gsub(%r{(?<=[(,=~\s])/(?=[^\s=])(?:[^/\\]|\\.)*/[imxounse]*}, "R")
       .sub(/#.*$/, "")
       .gsub(/\d+\*\*\d+/, "N")
  end

  def allowed?(violation)
    @allowlist.any? do |entry|
      next false unless entry["file"] == violation.file && violation.line.include?(entry["match"])

      @used << entry
    end
  end

  def stale_entries(files)
    return [] unless files == default_files

    @allowlist.reject { |entry| @used.include?(entry) }.map do |entry|
      Violation.new(file: entry["file"], line_number: 0, line: entry["match"], rules: [ "stale allowlist entry" ])
    end
  end
end
