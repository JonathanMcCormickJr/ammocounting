# Loaded automatically by `require "simplecov"`.
# Policy: every function is unit tested (see STANDARDS.md). Line and branch
# coverage must be 100% on full runs; set COVERAGE=1 to enforce.
SimpleCov.start "rails" do
  enable_coverage :branch
  if ENV["COVERAGE"] == "1"
    minimum_coverage line: 100, branch: 100
    refuse_coverage_drop :line, :branch
  end
end
