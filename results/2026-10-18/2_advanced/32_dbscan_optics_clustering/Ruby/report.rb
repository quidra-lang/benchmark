module Density
  module Report
    module_function

    def fraction(numerator, denominator)
      divisor = numerator.abs.gcd(denominator)
      "#{numerator / divisor}/#{denominator / divisor}"
    end

    def root(value)
      value.nil? ? '-' : format('%.3f', Math.sqrt(value))
    end

    def ari(numerator, denominator)
      text = format('%.4f', numerator.to_f / denominator)
      text == '-0.0000' ? '0.0000' : text
    end

    def frame(rows)
      border = '+' + '-' * rows.first.length + '+'
      [border] + rows.map { |row| "|#{row}|" } + [border]
    end

    def write(name, lines)
      File.binwrite(File.join('output', name), lines.join("\n") + "\n")
    end
  end
end
