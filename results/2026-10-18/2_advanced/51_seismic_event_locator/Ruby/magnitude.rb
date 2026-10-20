module Magnitude
  module_function

  def log10(value)
    Math.log(value.to_f) / 2.302585092994046
  end

  def median(values)
    ordered = values.sort
    middle = ordered.length / 2
    ordered.length.odd? ? ordered[middle] : (ordered[middle - 1] + ordered[middle]) / 2.0
  end

  def for_pick(pick, radius, params)
    al, bl, cl = params[:local_magnitude].map(&:to_f)
    ad, bd, cd = params[:duration_magnitude].map(&:to_f)
    ml = if !pick[:clipped]
           log10(pick[:amplitude]) + al * log10(radius / 100.0) + bl * (radius - 100.0) + cl
         end
    {r: radius, ml: ml, md: ad + bd * log10(pick[:duration] / 100.0) + cd * radius}
  end

  def class_number(hundredths)
    (hundredths + 5).div(10)
  end

  def class_notation(value)
    absolute = value.abs
    "#{value.negative? ? '-' : ''}#{absolute.div(10)}.#{absolute % 10}"
  end

  def frequency_statistics(classes)
    frequencies = Hash.new(0)
    classes.each { |value| frequencies[value] += 1 }
    completeness = frequencies.keys.min_by { |value| [-frequencies[value], value] }
    selected = classes.select { |value| value >= completeness }
    mc = completeness / 10.0
    mean = selected.sum.to_f / (10.0 * selected.length.to_f)
    b = 0.4342944819032518 / (mean - (mc - 0.05))
    {frequencies: frequencies, completeness: completeness, nb: selected.length,
     b: b, sigma: b / Math.sqrt(selected.length.to_f), a: log10(selected.length) + b * mc}
  end
end
