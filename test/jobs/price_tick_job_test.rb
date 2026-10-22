require "test_helper"

class PriceTickJobTest < ActiveJob::TestCase
  test "records ticks for all calibers" do
    assert_difference "PriceTick.count", 2 do
      PriceTickJob.perform_now
    end
  end

  test "can be enqueued" do
    assert_enqueued_with(job: PriceTickJob) { PriceTickJob.perform_later }
  end

  test "is scheduled every five minutes in recurring.yml" do
    config = YAML.load_file(Rails.root.join("config/recurring.yml"), aliases: true)
    %w[development production].each do |env|
      assert_equal "PriceTickJob", config.dig(env, "price_tick", "class")
      assert_equal "every 5 minutes", config.dig(env, "price_tick", "schedule")
    end
    assert_equal 5, Rails.configuration.x.tick_interval_minutes
  end
end
