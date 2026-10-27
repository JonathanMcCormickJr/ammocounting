# Server-side inline SVG line chart. No arithmetic here: the engine finds the
# extent (min_max) and places every point (scale).
module ChartHelper
  CHART_WIDTH = 720
  CHART_HEIGHT = 240
  # Pixels of empty space above the high and below the low, so the line and its stroke
  # are never clipped at the edges. Points still scale into 0..CHART_HEIGHT; the viewBox
  # starts CHART_PADDING above that and ends as far below it (literals: no arithmetic here).
  CHART_PADDING = 8
  CHART_VIEWBOX = "0 -8 720 256".freeze # x y width height = 0, -CHART_PADDING, CHART_WIDTH, CHART_HEIGHT + 2 * CHART_PADDING

  # points: Array of PriceHistory::Point. Plots closes.
  def price_chart(points)
    return tag.p("No price data for this range yet.", class: "empty") if points.empty?

    extent = LedgerEngine.min_max(points.map(&:close))
    tag.figure(class: "chart") do
      safe_join([
        tag.svg(viewBox: CHART_VIEWBOX, role: "img",
                "aria-label": "Price #{format_centicents(extent.low)} to #{format_centicents(extent.high)}") do
          tag.polyline(points: chart_coordinates(points, extent.low, extent.high), fill: "none", stroke: "currentColor",
                       "stroke-width": 2, "vector-effect": "non-scaling-stroke")
        end,
        tag.figcaption("Low #{format_centicents(extent.low)} / High #{format_centicents(extent.high)}")
      ])
    end
  end

  # points: Array of NetWorthHistory::Point (cents).
  def net_worth_chart(points)
    extent = LedgerEngine.min_max(points.map(&:value))
    tag.figure(class: "chart") do
      safe_join([
        tag.svg(viewBox: CHART_VIEWBOX, role: "img",
                "aria-label": "Net worth #{format_cents(extent.low)} to #{format_cents(extent.high)}") do
          tag.polyline(points: chart_coordinates(points, extent.low, extent.high, :value), fill: "none", stroke: "currentColor",
                       "stroke-width": 2, "vector-effect": "non-scaling-stroke")
        end,
        tag.figcaption("Low #{format_cents(extent.low)} / High #{format_cents(extent.high)} / Latest #{format_cents(points.last.value)}")
      ])
    end
  end

  # "x,y x,y ..." scaled into the viewBox by the engine; flat or single-point
  # series draw mid-height / mid-width. field: the Point attribute plotted
  # (:close for prices, :value for net worth).
  def chart_coordinates(points, low, high, field = :close)
    first = points.first.at.to_i
    last = points.last.at.to_i
    points.map do |point|
      x = LedgerEngine.scale(point.at.to_i, first, last, CHART_WIDTH)
      y = LedgerEngine.scale(point.public_send(field), low, high, CHART_HEIGHT, invert: true)
      "#{x},#{y}"
    end.join(" ")
  end
end
