class PriceRollupJob < ApplicationJob
  queue_as :default

  def perform
    PriceRollup.call
  end
end
