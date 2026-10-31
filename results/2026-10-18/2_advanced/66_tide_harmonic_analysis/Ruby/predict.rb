require_relative 'harmonic_fit'

module Predict
  module_function

  def level(model, time)
    value = model[:mean]
    model[:constituents].each do |item|
      theta = HarmonicFit.angle(item[:speed], time)
      value += item[:a] * Math.cos(theta) + item[:b] * Math.sin(theta)
    end
    value
  end

  def grid_extrema(model, start, hours, spacing)
    count = hours * 60 / spacing
    values = (0..count).map { |index| level(model, (60 * start + index * spacing) / 60.0) }
    extrema = []
    (1...count).each do |index|
      previous, current, following = values[index - 1, 3]
      kind = if previous < current && current > following
               'high'
             elsif previous > current && current < following
               'low'
             end
      next unless kind
      delta = (previous - following) / (2 * (previous - 2 * current + following))
      extrema << {kind: kind, refined_minute: 60 * start + index * spacing + delta * spacing,
                  height: current - (previous - following) * delta / 4}
    end
    extrema
  end
end
