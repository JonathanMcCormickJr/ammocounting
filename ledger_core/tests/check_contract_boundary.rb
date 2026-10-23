#!/usr/bin/env ruby
# frozen_string_literal: true

# Proof-boundary rule (audit E9). The shipped library is compiled with
# `pragma Assertion_Policy (Ignore)` (ledger_core.adc), so a `Pre` contract is
# proved for SPARK callers but never checked when the C shim (ledger_core-c_api)
# calls a subprogram with arbitrary C data. Therefore:
#
#   no subprogram the shim calls may have a `Pre` aspect: every such subprogram
#   must validate its own arguments at run time and report a status instead.
#
# Also enforced here: no `pragma Assume`, `Annotate` or `Suppress` anywhere in
# the engine sources (STANDARDS.md).
#
#   ruby ledger_core/tests/check_contract_boundary.rb [path/to/ledger_core/src]
#
# diff_test.rb runs this too, so `script/test` and CI enforce it. Exit status 1
# and a message per violation when the rule is broken.

module ContractBoundary
  module_function

  PACKAGES = %w[Running Builders Quotes Holdings Cost_Basis Reports Display Prices Transactions].freeze

  # Source with Ada comments removed (comments may contain parentheses and `;`).
  def code(text) = text.lines.map { _1.sub(/--.*$/, "") }.join

  # The text of the declaration of `name` in a package spec: from the keyword
  # to the first `;` outside parentheses (aspects included).
  def declaration(spec, name)
    start = spec.index(/^\s*(?:procedure|function)\s+#{Regexp.escape(name)}\b/i)
    return nil unless start

    depth = 0
    spec[start..].each_char.with_index do |ch, i|
      depth += 1 if ch == "("
      depth -= 1 if ch == ")"
      return spec[start, i] if ch == ";" && depth.zero?
    end
    nil
  end

  def called_subprograms(shim)
    shim.scan(/\b(?:Ledger_Core\.)?(#{PACKAGES.join('|')})\.(\w+)\s*\(/).uniq
  end

  def violations(src_dir)
    problems = []
    shim = code(File.read(File.join(src_dir, "ledger_core-c_api.adb")))
    called = called_subprograms(shim)
    problems << "no engine subprogram call found in the C shim (is the pattern stale?)" if called.empty?

    called.each do |package, name|
      path = File.join(src_dir, "ledger_core-#{package.downcase}.ads")
      spec = code(File.read(path))
      text = declaration(spec, name)
      if text.nil?
        problems << "#{package}.#{name}: declaration not found in #{File.basename(path)}"
      elsif text.match?(/\bPre\b/i)
        problems << "#{package}.#{name} is called by the C shim but has a Pre aspect " \
                    "(contracts are compiled out; validate at run time instead)"
      end
    end

    Dir[File.join(src_dir, "*.ad[sb]")].each do |file|
      code(File.read(file)).scan(/pragma\s+(Assume|Annotate|Suppress)\b/i) do |(pragma)|
        problems << "#{File.basename(file)}: pragma #{pragma} is not allowed"
      end
    end
    problems
  end
end

if $PROGRAM_NAME == __FILE__
  src = ARGV[0] || File.expand_path("../src", __dir__)
  problems = ContractBoundary.violations(src)
  problems.each { warn "CONTRACT BOUNDARY: #{_1}" }
  puts "contract boundary: #{problems.empty? ? 'ok' : "#{problems.size} violation(s)"}"
  exit(problems.empty? ? 0 : 1)
end
