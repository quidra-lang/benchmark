# frozen_string_literal: true

module Report
  module_function

  def decimal(value, places)
    numerator, denominator = value.numerator, value.denominator
    scale = 10**places
    rounded = (2 * scale * numerator.abs + denominator).div(2 * denominator)
    sign = numerator < 0 && rounded > 0 ? '-' : ''
    "#{sign}#{rounded.div(scale)}.#{(rounded % scale).to_s.rjust(places, '0')}"
  end

  def hull_area(doubled)
    "#{doubled.div(2)}.#{doubled.even? ? '0' : '5'}"
  end

  def write(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
  end
end
