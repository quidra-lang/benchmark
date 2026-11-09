module Report
  module_function

  def write(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def table(label, values, width)
    label.ljust(10) + values.map { |value| value.to_s.rjust(width) }.join
  end

  def money(cents)
    "#{cents.div(100)}.#{format('%02d', cents % 100)}"
  end

  def percentage(numerator, denominator)
    (200 * numerator + denominator).div(2 * denominator)
  end
end
