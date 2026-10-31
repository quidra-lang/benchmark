module Q
  ZERO = Rational(0)
  ONE = Rational(1)

  def self.read(text, signed = false)
    return nil unless text
    pattern = signed ? /\A-?[0-9]+(?:\.[0-9]+|\/[0-9]+)?\z/ : /\A[0-9]+(?:\.[0-9]+|\/[0-9]+)?\z/
    return nil unless pattern.match?(text)
    return nil if text.include?('/') && text.split('/')[1].to_i.zero?
    Rational(text)
  end

  def self.f(value)
    return '-' if value.nil?
    value.denominator == 1 ? value.numerator.to_s : "#{value.numerator}/#{value.denominator}"
  end

  def self.endpoint(value, lower) = value.nil? ? (lower ? '-inf' : 'inf') : f(value)

  def self.approx(value)
    scaled = (value.abs * 1_000_000 + Rational(1, 2)).floor
    sign = value < 0 && scaled > 0 ? '-' : ''
    "#{sign}#{scaled / 1_000_000}.#{(scaled % 1_000_000).to_s.rjust(6, '0')}"
  end
end
