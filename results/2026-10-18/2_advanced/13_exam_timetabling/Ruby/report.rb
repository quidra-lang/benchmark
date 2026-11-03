module Report
  module_function

  def write(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
  end

  def table(label, values, label_width, column_width)
    label.ljust(label_width) + values.map { |value| value.to_s.rjust(column_width) }.join
  end

  def percentage(numerator, denominator)
    (200 * numerator + denominator).div(2 * denominator)
  end
end
