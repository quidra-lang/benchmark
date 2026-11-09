# frozen_string_literal: true

module AttributeCharts
  Fit = Struct.new(:center, :proportion, keyword_init: true)
  Point = Struct.new(:number, :size, :value, :lcl, :ucl, :z, :status, keyword_init: true)

  module_function

  def fit(chart, lots)
    defectives = lots.sum(&:defectives)
    defects = lots.sum(&:defects)
    inspected = lots.sum(&:inspected)
    center = case chart
             when 'p' then defectives.to_f / inspected.to_f
             when 'np' then defectives.to_f / lots.length.to_f
             when 'c' then defects.to_f / lots.length.to_f
             when 'u' then defects.to_f / inspected.to_f
             end
    Fit.new(center: center, proportion: defectives.to_f / inspected.to_f)
  end

  def point(chart, fit, lot)
    center = fit.center
    case chart
    when 'p'
      value = lot.defectives.to_f / lot.inspected.to_f
      sigma = Math.sqrt(center * (1 - center) / lot.inspected)
    when 'np'
      value = lot.defectives
      sigma = Math.sqrt(center * (1 - fit.proportion))
    when 'c'
      value = lot.defects
      sigma = Math.sqrt(center)
    when 'u'
      value = lot.defects.to_f / lot.inspected.to_f
      sigma = Math.sqrt(center / lot.inspected)
    end
    lower = [0.0, center - 3 * sigma].max
    upper = center + 3 * sigma
    status = value > upper ? 'high' : value < lower ? 'low' : 'ok'
    Point.new(number: lot.number, size: lot.inspected, value: value, lcl: lower, ucl: upper,
              z: (value - center) / sigma, status: status)
  end
end
