# frozen_string_literal: true

module Report
  module_function

  def real(value, places = 6)
    text = format("%.#{places}f", value)
    text.start_with?('-') && text.to_f.zero? ? text[1..] : text
  end

  def scaled(value, places = 6)
    real(value, places).delete('.').to_i
  end

  def fraction(numerator, denominator)
    divisor = numerator.abs.gcd(denominator)
    numerator = numerator.div(divisor)
    denominator = denominator.div(divisor)
    "#{numerator}/#{denominator} #{real(numerator.to_f / denominator, 4)}"
  end

  def write(name, lines)
    Dir.mkdir('output') unless Dir.exist?('output')
    File.binwrite(File.join('output', name), lines.empty? ? '' : lines.join("\n") + "\n")
  end
end
