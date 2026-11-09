require 'fileutils'

module Report
  module_function

  def fraction(value, denominator = 1)
    ratio = Rational(value, denominator)
    numerator, divisor = ratio.numerator, ratio.denominator
    truncated = 10000 * numerator.abs / divisor
    decimal = "#{truncated / 10000}.#{(truncated % 10000).to_s.rjust(4, '0')}"
    decimal = '-' + decimal if numerator.negative? && truncated.positive?
    "#{numerator}/#{divisor}=#{decimal}"
  end

  def percentage(numerator, denominator)
    truncated = 10000 * numerator / denominator
    "#{truncated / 100}.#{(truncated % 100).to_s.rjust(2, '0')}%"
  end

  def list(values)
    values.empty? ? '-' : values.join(',')
  end

  def write_outputs(files)
    FileUtils.mkdir_p('output')
    files.each { |name, lines| File.write("output/#{name}", lines.join("\n") + "\n", encoding: Encoding::US_ASCII) }
  end
end
