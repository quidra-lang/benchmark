module Spectrum
  extend self
  PI = 3.141592653589793

  def pow2(value)
    result = 1
    result *= 2 while result < value
    result
  end

  def rot(angle)
    Complex(Math.cos(angle), -Math.sin(angle))
  end

  def radix2(data, inverse = false)
    n = data.length
    raise ArgumentError, 'power-of-two length required' unless n > 0 && (n & (n - 1)).zero?
    values = data.map { |v| Complex(v) }
    bits = n.bit_length - 1
    (1...n).each do |i|
      reversed, t = 0, i
      bits.times { reversed = reversed * 2 + t % 2; t /= 2 }
      values[i], values[reversed] = values[reversed], values[i] if i < reversed
    end
    twiddle = Array.new(n / 2) { |k| rot(2 * PI * k / n) }
    twiddle.map!(&:conj) if inverse
    size = 2
    while size <= n
      stride, half = n / size, size / 2
      (0...n).step(size) do |start|
        half.times do |j|
          t = twiddle[j * stride] * values[start + j + half]
          u = values[start + j]
          values[start + j], values[start + j + half] = u + t, u - t
        end
      end
      size *= 2
    end
    inverse ? values.map { |v| v / n } : values
  end

  def bluestein(values)
    m = values.length
    q = pow2(2 * m - 1)
    chirp = Array.new(m) { |n| rot(PI * (n * n % (2 * m)) / m) }
    a, b = Array.new(q, Complex(0.0, 0.0)), Array.new(q, Complex(0.0, 0.0))
    m.times do |n|
      a[n] = values[n] * chirp[n]
      b[n] = chirp[n].conj
      b[q - n] = b[n] unless n.zero?
    end
    af, bf = radix2(a), radix2(b)
    g = radix2(Array.new(q) { |k| af[k] * bf[k] }, true)
    Array.new(m) { |k| chirp[k] * g[k] }
  end

  def dft(values)
    raise ArgumentError, 'empty transform' if values.empty?
    (values.length & (values.length - 1)).zero? ? radix2(values) : bluestein(values)
  end

  def idft(values)
    raise ArgumentError, 'empty transform' if values.empty?
    return radix2(values, true) if (values.length & (values.length - 1)).zero?
    bluestein(values.map { |v| v.conj }).map { |v| v.conj / values.length }
  end

  def packed_real(values)
    n = values.length
    half = n / 2
    transformed = radix2(Array.new(half) { |j| Complex(values[2 * j], values[2 * j + 1]) })
    Array.new(half + 1) do |k|
      za, zb = transformed[k % half], transformed[(half - k) % half].conj
      even, odd = (za + zb) / 2, (za - zb) / Complex(0, 2)
      even + rot(2 * PI * k / n) * odd
    end
  end

  def convolution(a, b)
    n = a.length + b.length - 1
    q = pow2(n)
    af = radix2(a + Array.new(q - a.length, 0.0))
    bf = radix2(b + Array.new(q - b.length, 0.0))
    radix2(Array.new(q) { |k| af[k] * bf[k] }, true).first(n).map(&:real)
  end

  def chirp_z(weighted, fs, low, high, points)
    m = weighted.length
    step = (high - low).to_f / (points - 1)
    q = pow2(m + points - 1)
    a, b = Array.new(q, Complex(0.0, 0.0)), Array.new(q, Complex(0.0, 0.0))
    m.times { |n| a[n] = weighted[n] * rot(2 * PI * low * n / fs) * rot(PI * step * n * n / fs) }
    (-(m - 1)...points).each { |offset| b[offset % q] = rot(PI * step * offset * offset / fs).conj }
    af, bf = radix2(a), radix2(b)
    g = radix2(Array.new(q) { |k| af[k] * bf[k] }, true)
    Array.new(points) { |j| rot(PI * step * j * j / fs) * g[j] }
  end
end
