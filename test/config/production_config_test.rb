require "test_helper"
require "open3"
require "json"

# Boots a real production environment in a subprocess (the test env cannot see
# production.rb) and drives the Rack stack with plain requests.
class ProductionConfigTest < ActiveSupport::TestCase
  SCRIPT = <<~'RUBY'.freeze
    require "rack/mock"
    app = Rails.application
    get = lambda do |path, opts = {}|
      res = Rack::MockRequest.new(app).get(path, opts)
      [ res.status, res["location"], res["strict-transport-security"], res["content-security-policy"], res["set-cookie"] ]
    end
    https = { "HTTPS" => "on", "HTTP_X_FORWARDED_PROTO" => "https" }
    puts JSON.generate(
      health_http: get.call("/up", "HTTP_HOST" => "app.test"),
      health_any_host: get.call("/up", "HTTP_HOST" => "evil.test"),
      root_http: get.call("/", "HTTP_HOST" => "app.test"),
      bad_host: get.call("/session/new", { "HTTP_HOST" => "evil.test" }.merge(https)),
      login_https: get.call("/session/new", { "HTTP_HOST" => "app.test" }.merge(https)),
      login_proxied: get.call("/session/new", "HTTP_HOST" => "app.test", "HTTP_X_FORWARDED_PROTO" => "https")
    )
  RUBY

  def self.result
    @result ||= begin
      env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1", "APP_HOST" => "app.test" }
      out, err, status = Open3.capture3(env, "bin/rails", "runner", SCRIPT, chdir: Rails.root.to_s)
      raise "production boot failed: #{err}" unless status.success?
      JSON.parse(out.lines.last)
    end
  end

  def result = self.class.result

  test "health check stays reachable over plain http on any host" do
    assert_equal 200, result["health_http"][0]
    assert_equal 200, result["health_any_host"][0]
  end

  test "assume_ssl treats proxy-forwarded http as https: no redirect loop, links stay https" do
    status, location = result["root_http"]
    assert_equal 302, status
    assert_equal "https://app.test/session/new", location # the login redirect, not an ssl redirect
  end

  test "unknown hosts are refused" do
    assert_equal 403, result["bad_host"][0]
  end

  test "https requests send HSTS" do
    assert_equal 200, result["login_https"][0]
    assert_match(/max-age=\d+/, result["login_https"][2])
  end

  test "requests terminated at the proxy are treated as ssl" do
    assert_equal 200, result["login_proxied"][0]
  end

  test "kamal deploy terminates ssl at the proxy and sets the allowed host" do
    deploy = YAML.load_file(Rails.root.join("config/deploy.yml"))
    assert_equal true, deploy.dig("proxy", "ssl")
    assert_equal "/up", deploy.dig("proxy", "healthcheck", "path")
    assert_equal deploy.dig("proxy", "host"), deploy.dig("env", "clear", "APP_HOST")
  end

  test "every response carries a content security policy without unsafe-inline scripts" do
    csp = result["login_https"][3]
    assert_match(/script-src 'self' 'nonce-/, csp)
    assert_match(/object-src 'none'/, csp)
    assert_no_match(/unsafe-inline/, csp[/script-src[^;]*/])
  end
end
