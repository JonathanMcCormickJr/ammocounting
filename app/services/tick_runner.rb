# Records one tick of prices for every caliber in a single transaction, then
# runs the after_tick callables. The index reads the latest stored ticks inside
# that (BEGIN IMMEDIATE) transaction, so two concurrent runs serialise and the
# second sees the first's ticks; rows are inserted with ON CONFLICT DO NOTHING on
# (caliber_id, as_of) as a second line of defence, so a duplicate tick is skipped,
# never an error and never an overwrite.
#
# EXTENSION SEAM: append a callable to TickRunner.after_tick to run work after
# each committed tick (e.g. per-user revaluation). Each is called with the Array
# of PriceTicks just stored (empty if the tick already existed).
class TickRunner
  @after_tick = []

  class << self
    attr_reader :after_tick

    def call(now: Time.current, index: PriceIndex.build)
      ticks = PriceTick.transaction { store(index.current_prices(now: now)) }
      after_tick.each { _1.call(ticks) }
      ticks
    end

    private

    # Validates every quote (all or nothing), inserts the new ones, returns the PriceTicks stored.
    def store(quotes)
      rows = quotes.map do |quote|
        PriceTick.new(caliber_id: quote[:caliber_id], as_of: quote[:as_of], price_centicents: quote[:price_centicents])
          .tap(&:validate!).attributes.except("id")
      end
      ids = PriceTick.insert_all(rows, unique_by: %i[caliber_id as_of], returning: %w[id]).rows.flatten
      PriceTick.where(id: ids).order(:id).to_a
    end
  end
end
