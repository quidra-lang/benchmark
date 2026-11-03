# frozen_string_literal: true

require 'fileutils'

module Report
  def self.real(value, digits = 4)
    if value.is_a?(Rational) || value.is_a?(Integer)
      scale = 10**digits
      rounded, remainder = (value.numerator.abs * scale).divmod(value.denominator)
      rounded += 1 if 2 * remainder >= value.denominator
      integer, fraction = rounded.divmod(scale)
      sign = value.negative? && rounded.positive? ? '-' : ''
      return "#{sign}#{integer}.#{fraction.to_s.rjust(digits, '0')}"
    end
    text = format("%.#{digits}f", value)
    text.match?(/\A-0\.0+\z/) ? text[1..] : text
  end

  def self.decimal_value(value, digits)
    real(value, digits).delete('.').to_i
  end

  def self.fraction(value)
    "#{value.numerator}/#{value.denominator}"
  end

  def self.write(name, lines)
    FileUtils.mkdir_p('output')
    File.binwrite("output/#{name}", lines.join("\n") + "\n")
  end
end
