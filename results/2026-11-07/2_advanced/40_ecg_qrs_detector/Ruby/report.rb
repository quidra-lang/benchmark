module Report
  module_function

  def rdiv(numerator, denominator) = (2 * numerator + denominator) / (2 * denominator)

  def two(value)
    sign = value.negative? ? "-" : ""
    magnitude = value.abs
    format("%s%d.%02d", sign, magnitude / 100, magnitude % 100)
  end

  def four(value) = format("%d.%04d", value / 10_000, value % 10_000)

  def fraction(numerator, denominator)
    divisor = numerator.gcd(denominator)
    "#{numerator / divisor}/#{denominator / divisor}"
  end

  def ratio(numerator, denominator)
    return "#{numerator}/0 none" if denominator.zero?

    "#{numerator}/#{denominator} reduced=#{fraction(numerator, denominator)} " \
      "percent=#{two(rdiv(10_000 * numerator, denominator))}"
  end

  def missing(value) = value.nil? ? "-" : value.to_s
  def maybe_two(value) = value.nil? ? "none" : two(value)
end
