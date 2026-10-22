# Records one tick of prices for every caliber in a single transaction, then
# runs the after_tick callables.
#
# EXTENSION SEAM: append a callable to TickRunner.after_tick to run work after
# each committed tick (e.g. per-user revaluation). Each is called with the Array
# of PriceTicks just stored (empty if the tick already existed).
class TickRunner
  @after_tick = []

  class << self
    attr_reader :after_tick

    def call(now: Time.current, index: PriceIndex.build)
      ticks = PriceTick.transaction do
        index.current_prices(now: now).filter_map do |quote|
          tick = PriceTick.find_or_initialize_by(caliber_id: quote[:caliber_id], as_of: quote[:as_of])
          next unless tick.new_record?

          tick.update!(price_centicents: quote[:price_centicents])
          tick
        end
      end
      after_tick.each { _1.call(ticks) }
      ticks
    end
  end
end
