require_relative 'tests'

module Report
  module_function

  def real(value)
    text = format('%.4f', value)
    text == '-0.0000' ? '0.0000' : text
  end

  def p_value(numerator, denominator)
    numerator, denominator = Tests.reduced_fraction(numerator, denominator)
    "#{numerator}/#{denominator} #{real(numerator.to_f / denominator)}"
  end

  def number_list(numbers)
    numbers.empty? ? 'none' : numbers.sort.join(' ')
  end

  def bin(value, low, high, count)
    [(count * (value - low) / (high - low)).floor, count - 1].min + 1
  end

  def bar(count, top)
    '#' * ((40 * count + top - 1) / top)
  end

  def write(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite("output/#{name}", lines.join("\n") + "\n")
  end
end
