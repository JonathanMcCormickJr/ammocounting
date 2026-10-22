class PriceTickJob < ApplicationJob
  queue_as :default

  def perform
    TickRunner.call
  end
end
