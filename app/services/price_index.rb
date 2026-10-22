# Interface for price sources. An implementation responds to
#   #current_prices(now: Time.current)
# and returns an Array of Hashes:
#   { caliber_id:, slug:, price_centicents:, as_of: }
# Prices are Integer centicents (1/100 cent) per round, never Floats.
module PriceIndex
  # Builds the implementation chosen by config.x.price_index.
  def self.build(name = Rails.configuration.x.price_index)
    case name.to_sym
    when :mock then Mock.new
    else raise ArgumentError, "unknown price index: #{name}"
    end
  end
end
