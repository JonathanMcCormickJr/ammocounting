require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Ammocounting
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Price tick cadence. config/recurring.yml must schedule PriceTickJob at the same interval.
    config.x.tick_interval_minutes = 5
    # Which PriceIndex implementation supplies prices (:mock is the only one so far).
    config.x.price_index = :mock
    # Seed for the deterministic mock random walk.
    config.x.price_index_seed = 1776

    # Trading costs, in basis points of trade value (100 bps = 1%). Spread is rounded up, fee half-up, by the engine.
    config.x.spread_bps = 50
    config.x.fee_bps = 100

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
