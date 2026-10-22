require "test_helper"

class PriceRollupJobTest < ActiveJob::TestCase
  test "rolls up old ticks" do
    PriceTick.delete_all
    travel_to Time.utc(2026, 3, 20, 12) do
      PriceTick.create!(caliber: calibers(:nine_mm), price_centicents: 10, as_of: Time.utc(2026, 3, 1))
      assert_difference "PriceBucket.count", 3 do
        PriceRollupJob.perform_now
      end
    end
  end
end
