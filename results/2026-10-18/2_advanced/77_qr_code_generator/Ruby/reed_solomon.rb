module ReedSolomon
  EXP = Array.new(255, 1)
  LOG = Array.new(256, 0)
  (1...255).each do |exponent|
    doubled = EXP[exponent - 1] * 2
    EXP[exponent] = doubled >= 256 ? doubled ^ 0x11d : doubled
  end
  EXP.each_with_index { |element, exponent| LOG[element] = exponent }
  EXP.freeze
  LOG.freeze
  @generators = {}

  def self.multiply(a, b)
    a.zero? || b.zero? ? 0 : EXP[(LOG[a] + LOG[b]) % 255]
  end

  def self.divide(a, b)
    a.zero? ? 0 : EXP[(LOG[a] - LOG[b]) % 255]
  end

  def self.generator(degree)
    @generators[degree] ||= begin
      coefficients = [1]
      degree.times do |exponent|
        product = Array.new(coefficients.length + 1, 0)
        coefficients.each_with_index do |coefficient, index|
          product[index] ^= coefficient
          product[index + 1] ^= multiply(coefficient, EXP[exponent])
        end
        coefficients = product
      end
      coefficients
    end
  end

  def self.parity(data, degree)
    polynomial = generator(degree)
    remainder = data + Array.new(degree, 0)
    data.length.times do |index|
      leading = remainder[index]
      next if leading.zero?
      polynomial.each_with_index { |coefficient, offset| remainder[index + offset] ^= multiply(leading, coefficient) }
    end
    remainder.last(degree)
  end

  def self.syndromes(words, degree)
    Array.new(degree) do |exponent|
      words.reduce(0) { |value, word| multiply(value, EXP[exponent]) ^ word }
    end
  end

  # Coefficients for the locator and evaluator are in increasing degree order.
  def self.evaluate(coefficients, argument)
    coefficients.reverse_each.reduce(0) { |value, coefficient| multiply(value, argument) ^ coefficient }
  end

  def self.correct(received, degree)
    original = syndromes(received, degree)
    return [original, received.dup, []] if original.all?(&:zero?)
    locator = [1] + Array.new(degree, 0)
    previous = locator.dup
    length, shift, beta = 0, 1, 1
    degree.times do |step|
      discrepancy = original[step]
      (1..length).each { |index| discrepancy ^= multiply(locator[index], original[step - index]) }
      if discrepancy.zero?
        shift += 1
        next
      end
      saved = locator.dup
      multiplier = divide(discrepancy, beta)
      (degree + 1 - shift).times { |index| locator[index + shift] ^= multiply(multiplier, previous[index]) }
      if 2 * length <= step
        length, previous, beta, shift = step + 1 - length, saved, discrepancy, 1
      else
        shift += 1
      end
    end
    return [original, nil, []] if length > degree / 2
    locator = locator.first(length + 1)
    count = received.length
    positions = (0...count).select do |index|
      inverse = EXP[(255 - (count - 1 - index)) % 255]
      evaluate(locator, inverse).zero?
    end
    return [original, nil, []] unless positions.length == length
    omega = Array.new(degree, 0)
    original.each_with_index do |syndrome, index|
      (0..[length, degree - 1 - index].min).each do |offset|
        omega[index + offset] ^= multiply(syndrome, locator[offset])
      end
    end
    derivative = Array.new(length, 0)
    (1..length).step(2) { |exponent| derivative[exponent - 1] = locator[exponent] }
    corrected = received.dup
    positions.each do |index|
      location = EXP[(count - 1 - index) % 255]
      inverse = EXP[(255 - (count - 1 - index)) % 255]
      denominator = evaluate(derivative, inverse)
      return [original, nil, []] if denominator.zero?
      magnitude = multiply(location, divide(evaluate(omega, inverse), denominator))
      corrected[index] ^= magnitude
    end
    return [original, nil, []] unless syndromes(corrected, degree).all?(&:zero?)
    [original, corrected, positions.select { |index| corrected[index] != received[index] }]
  end
end
