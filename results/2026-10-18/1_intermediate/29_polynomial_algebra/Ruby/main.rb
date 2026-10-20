class CommandError < StandardError
  def initialize(message) = super("ERROR #{message}")
end

Fraction = Data.define(:n, :d) do
  include Comparable

  def self.make(n, d = 1)
    n, d = -n, -d if d.negative?
    divisor = n.gcd(d)
    new(n / divisor, d / divisor)
  end

  def self.parse(text)
    parts = text.split('/')
    n = Integer(parts[0], 10)
    d = parts.length == 1 ? 1 : Integer(parts[1], 10)
    raise CommandError, 'ZERO DENOMINATOR' if d.zero?

    make(n, d)
  end

  def +(b) = Fraction.make(n * b.d + b.n * d, d * b.d)
  def -(b) = Fraction.make(n * b.d - b.n * d, d * b.d)
  def *(b) = Fraction.make(n * b.n, d * b.d)
  def /(b) = Fraction.make(n * b.d, d * b.n)
  def -@ = Fraction.new(-n, d)
  def abs = Fraction.new(n.abs, d)
  def sign = n <=> 0
  def <=>(b) = (n * b.d) <=> (b.n * d)
  def power(exponent)
    result = Fraction::ONE
    exponent.times { result *= self }
    result
  end
  def to_s = d == 1 ? n.to_s : "#{n}/#{d}"
end
Fraction::ZERO = Fraction.make(0)
Fraction::ONE = Fraction.make(1)
def whole(n) = Fraction.make(n)

class Polynomial
  attr_reader :coefficients

  def initialize(values = [])
    values = values.dup
    values.pop while !values.empty? && values.last.n.zero?
    @coefficients = values.freeze
    freeze
  end

  ZERO = new
  ONE = new([Fraction::ONE])
  def self.constant(value) = new([value])
  def self.linear(value, slope) = new([value, slope])
  def degree = coefficients.length - 1
  def zero? = coefficients.empty?
  def one? = degree.zero? && self[0] == Fraction::ONE
  def leading = coefficients.last
  def [](i) = coefficients[i] || Fraction::ZERO
  def +(b) = Polynomial.new(Array.new([coefficients.length, b.coefficients.length].max) { |i| self[i] + b[i] })
  def -(b) = Polynomial.new(Array.new([coefficients.length, b.coefficients.length].max) { |i| self[i] - b[i] })
  def -@ = Polynomial.new(coefficients.map { |c| -c })
  def scale(factor) = Polynomial.new(coefficients.map { |c| c * factor })
  def divide_scalar(divisor) = Polynomial.new(coefficients.map { |c| c / divisor })

  def *(b)
    return ZERO if zero? || b.zero?

    result = Array.new(degree + b.degree + 1, Fraction::ZERO)
    coefficients.each_with_index do |a, i|
      b.coefficients.each_with_index { |c, j| result[i + j] += a * c }
    end
    Polynomial.new(result)
  end

  def power(exponent)
    return ONE if exponent.zero?
    return ZERO if zero?
    if degree.zero? && self[0].d == 1 && self[0].n.abs == 1
      return self[0].n == 1 || exponent.even? ? ONE : self
    end

    result = ONE
    exponent.times { result *= self }
    result
  end

  def divide(b)
    quotient = Array.new([0, degree - b.degree + 1].max, Fraction::ZERO)
    remainder = coefficients.dup
    current = degree
    while current >= 0 && current >= b.degree
      factor = remainder[current] / b.leading
      shift = current - b.degree
      quotient[shift] = factor
      b.coefficients.each_with_index { |c, j| remainder[shift + j] -= factor * c }
      current -= 1 while current >= 0 && remainder[current].n.zero?
    end
    Division.new(Polynomial.new(quotient), Polynomial.new(remainder))
  end

  def quotient(b) = divide(b).quotient
  def remainder(b) = divide(b).remainder
  def monic = zero? ? ZERO : divide_scalar(leading)
  def derivative = Polynomial.new((1..degree).map { |i| whole(i) * self[i] })
  def differentiate(order)
    result = self
    order.times do
      break if result.zero?
      result = result.derivative
    end
    result
  end

  def integral = Polynomial.new([Fraction::ZERO] + coefficients.each_with_index.map { |c, i| c / whole(i + 1) })
  def evaluate(point)
    result = Fraction::ZERO
    coefficients.reverse_each { |c| result = result * point + c }
    result
  end

  def compose(inner)
    result = ZERO
    coefficients.reverse_each { |c| result = result * inner + Polynomial.constant(c) }
    result
  end

  def gcd(other)
    a, b = self, other
    a, b = b, a.remainder(b) until b.zero?
    a.monic
  end

  def extended_gcd(other)
    r0, r1, s0, s1, t0, t1 = self, other, ONE, ZERO, ZERO, ONE
    until r1.zero?
      division = r0.divide(r1)
      s = s0 - division.quotient * s1
      t = t0 - division.quotient * t1
      r0, r1 = r1, division.remainder
      s0, s1 = s1, s
      t0, t1 = t1, t
    end
    return Bezout.new(r0, s0, t0) if r0.zero?

    Bezout.new(r0.monic, s0.divide_scalar(r0.leading), t0.divide_scalar(r0.leading))
  end

  def content
    denominator, numerator = 1, 0
    coefficients.each do |c|
      denominator = denominator * c.d / denominator.gcd(c.d)
      numerator = numerator.gcd(c.n)
    end
    Fraction.make(leading.n.negative? ? -numerator : numerator, denominator)
  end

  def primitive = divide_scalar(content)
  def square_free_part = degree < 1 ? self : quotient(gcd(derivative))
  def without_constant = Polynomial.new(coefficients.drop(1))
  def check_product(b)
    raise CommandError, 'DEGREE LIMIT' if !zero? && !b.zero? && degree + b.degree > 30
  end

  def check_power(exponent)
    raise CommandError, 'DEGREE LIMIT' if !zero? && degree * exponent > 30
  end

  def check_composition(b)
    raise CommandError, 'DEGREE LIMIT' if degree >= 1 && b.degree >= 1 && degree * b.degree > 30
  end

  def require_nonzero = (raise CommandError, 'ZERO POLYNOMIAL' if zero?)
  def require_divisor = (raise CommandError, 'DIVISION BY ZERO' if zero?)
  def require_positive_degree = (raise CommandError, 'DEGREE TOO LOW' if degree.zero?)

  def format(variable = 'x')
    text = +''
    degree.downto(0) do |i|
      c = self[i]
      next if c.n.zero?
      if text.empty?
        text << '-' if c.n.negative?
      else
        text << (c.n.negative? ? ' - ' : ' + ')
      end
      text << c.abs.to_s if i.zero? || c.abs != Fraction::ONE
      text << variable if i.positive?
      text << "^#{i}" if i > 1
    end
    text.empty? ? '0' : text
  end
end
Division = Data.define(:quotient, :remainder)
Bezout = Data.define(:g, :s, :t)

Expression = Data.define(:kind, :value, :left, :right) do
  def self.make(kind, value: nil, left: nil, right: nil) = new(kind, value, left, right)
  def evaluate(storage)
    case kind
    when :literal then return Polynomial.constant(whole(value))
    when :variable then return Polynomial.linear(Fraction::ZERO, Fraction::ONE)
    when :reference
      name, order = value
      return storage.fetch(name) { raise CommandError, "UNKNOWN #{name}" }.differentiate(order)
    end
    a = left.evaluate(storage)
    return -a if kind == :negative
    if kind == :power
      a.check_power(value)
      return a.power(value)
    end
    b = right.evaluate(storage)
    if kind == :call
      a.check_composition(b)
      return a.compose(b)
    end
    case value
    when '+' then a + b
    when '-' then a - b
    when '*' then a.check_product(b); a * b
    else
      b.require_divisor
      raise CommandError, 'NONCONSTANT DIVISOR' if b.degree >= 1
      a.divide_scalar(b[0])
    end
  end
end
Token = Data.define(:kind, :text, :position)
class Parser
  def initialize(source)
    @tokens = []
    @position = 0
    i = 0
    while i < source.length
      if source[i] == ' '
        i += 1
        next
      end
      start = i
      i += 1
      kind = if digit?(source[start]) then :number elsif upper?(source[start]) then :name else :symbol end
      if kind == :number
        i += 1 while i < source.length && digit?(source[i])
      elsif kind == :name
        i += 1 while i < source.length && (upper?(source[i]) || digit?(source[i]))
      end
      @tokens << Token.new(kind, source[start...i], start + 1)
    end
    @tokens << Token.new(:end, '', source.length + 1)
  end

  def digit?(c) = c >= '0' && c <= '9'
  def upper?(c) = c >= 'A' && c <= 'Z'
  def current = @tokens[@position]
  def syntax = raise(CommandError, "SYNTAX AT #{current.kind == :end ? 'END' : current.position}")
  def accept(symbol)
    return false unless current.kind == :symbol && current.text == symbol
    @position += 1
    true
  end

  def expect(symbol) = (syntax unless accept(symbol))
  def parse
    result = expression
    syntax unless current.kind == :end
    result
  end

  def expression
    negative = accept('-')
    result = term
    result = Expression.make(:negative, left: result) if negative
    loop do
      operation = if accept('+') then '+' elsif accept('-') then '-' else break end
      result = Expression.make(:binary, value: operation, left: result, right: term)
    end
    result
  end

  def term
    result = factor
    loop do
      operation = if accept('*') then '*' elsif accept('/') then '/'
                  elsif current.kind == :name || current.text == 'x' || current.text == '(' then '*'
                  else break end
      result = Expression.make(:binary, value: operation, left: result, right: factor)
    end
    result
  end

  def factor
    result = primary
    if accept('^')
      syntax unless current.kind == :number
      exponent = Integer(current.text, 10)
      @position += 1
      result = Expression.make(:power, value: exponent, left: result)
    end
    result
  end

  def primary
    if current.kind == :number
      value = Integer(current.text, 10)
      @position += 1
      return Expression.make(:literal, value: value)
    end
    return Expression.make(:variable) if accept('x')
    if current.kind == :name
      name = current.text
      @position += 1
      order = 0
      order += 1 while accept("'")
      reference = Expression.make(:reference, value: [name, order].freeze)
      return reference unless accept('(')
      argument = expression
      expect(')')
      return Expression.make(:call, left: reference, right: argument)
    end
    if accept('(')
      result = expression
      expect(')')
      return result
    end
    syntax
  end
end

Root = Data.define(:value, :multiplicity)
Factor = Data.define(:value, :multiplicity)
RootResult = Data.define(:content, :remaining, :roots)
def rational_roots(a)
  content = a.content
  remaining = a.divide_scalar(content)
  zeros = 0
  while remaining[0].n.zero?
    remaining = remaining.without_constant
    zeros += 1
  end
  first, last = remaining[0].n.abs, remaining.leading.n
  numerators = (1..first).select { |n| (first % n).zero? }
  denominators = (1..last).select { |d| (last % d).zero? }
  candidates = []
  numerators.each do |n|
    denominators.each do |d|
      candidates.concat([Fraction.make(-n, d), Fraction.make(n, d)]) if n.gcd(d) == 1
    end
  end
  candidates.sort!
  roots = []
  candidates.each do |candidate|
    multiplicity = 0
    while remaining.degree >= 1 && remaining.evaluate(candidate).n.zero?
      remaining = remaining.quotient(Polynomial.linear(whole(-candidate.n), whole(candidate.d)))
      multiplicity += 1
    end
    roots << Root.new(candidate, multiplicity) if multiplicity.positive?
  end
  roots << Root.new(Fraction::ZERO, zeros) if zeros.positive?
  RootResult.new(content, remaining, roots.sort_by(&:value))
end

def square_free_factors(a)
  return [] if a.degree < 1

  monic = a.monic
  c = monic.gcd(monic.derivative)
  w = monic.quotient(c)
  factors = []
  multiplicity = 1
  while w.degree >= 1
    y = w.gcd(c)
    f = w.quotient(y)
    factors << Factor.new(f.primitive, multiplicity) if f.degree >= 1
    c, w = c.quotient(y), y
    multiplicity += 1
  end
  factors
end

def append_factor(text, value, multiplicity, simple_x)
  text << ' * ' << (simple_x ? 'x' : "(#{value.format})")
  text << "^#{multiplicity}" if multiplicity > 1
end

Bound = Data.define(:infinity, :value) do
  include Comparable
  def self.finite(value) = new(0, value)
  def self.parse(text)
    case text
    when '-inf' then new(-1, Fraction::ZERO)
    when 'inf' then new(1, Fraction::ZERO)
    else finite(Fraction.parse(text))
    end
  end
  def <=>(other)
    infinity.zero? && other.infinity.zero? ? value <=> other.value : infinity <=> other.infinity
  end
  def to_s = infinity.zero? ? value.to_s : infinity.negative? ? '-inf' : 'inf'
end
Interval = Data.define(:low, :high)
def sturm_sequence(a)
  p = a.square_free_part
  q = p.derivative
  sequence = [p]
  until q.zero?
    sequence << q
    p, q = q, -p.remainder(q)
  end
  sequence
end

def variations(sequence, point)
  previous = count = 0
  sequence.each do |p|
    sign = point.infinity.zero? ? p.evaluate(point.value).sign : p.leading.sign
    sign = -sign if point.infinity.negative? && p.degree.odd?
    next if sign.zero?
    count += 1 if !previous.zero? && previous != sign
    previous = sign
  end
  count
end

def root_count(sequence, low, high)
  left = variations(sequence, low)
  right = variations(sequence, high)
  left - right
end

def examine(sequence, low, high, width, result)
  count = root_count(sequence, Bound.finite(low), Bound.finite(high))
  if count >= 2
    middle = (low + high) / whole(2)
    examine(sequence, low, middle, width, result)
    examine(sequence, middle, high, width, result)
  elsif count == 1
    while high - low > width
      middle = (low + high) / whole(2)
      if root_count(sequence, Bound.finite(low), Bound.finite(middle)) >= 1
        high = middle
      else
        low = middle
      end
    end
    result << Interval.new(low, high)
  end
end

def isolate(a, precision)
  sequence = sturm_sequence(a)
  first = sequence.first
  maximum = Fraction::ZERO
  first.degree.times { |i| maximum = [maximum, (first[i] / first.leading).abs].max }
  beta = Fraction::ONE + maximum
  result = []
  examine(sequence, -beta, beta, Fraction.make(1, 1 << precision), result)
  result
end

def resultant(p, q)
  result = Fraction::ONE
  while q.degree >= 1
    remainder = p.remainder(q)
    return Fraction::ZERO if remainder.zero?
    result *= q.leading.power(p.degree - remainder.degree)
    result = -result if (p.degree * q.degree).odd?
    p, q = q, remainder
  end
  result * q[0].power(p.degree)
end

def descartes(a, negative)
  previous = count = 0
  a.degree.downto(0) do |i|
    sign = a[i].sign
    sign = -sign if negative && i.odd?
    next if sign.zero?
    count += 1 if !previous.zero? && previous != sign
    previous = sign
  end
  count
end

def interpolate(values)
  points = values.each_slice(2).map(&:first)
  differences = values.each_slice(2).map(&:last)
  count = points.length
  (1...count).each do |j|
    j.times { |i| raise CommandError, "DUPLICATE X #{points[j]}" if points[j] == points[i] }
  end
  (1...count).each do |j|
    (count - 1).downto(j) { |i| differences[i] = (differences[i] - differences[i - 1]) / (points[i] - points[i - j]) }
  end
  result = Polynomial::ZERO
  (count - 1).downto(0) { |i| result = result * Polynomial.linear(-points[i], Fraction::ONE) + Polynomial.constant(differences[i]) }
  result
end

def special(kind, n)
  raise CommandError, "UNKNOWN KIND #{kind}" unless %w[chebyshev chebyshev2 legendre hermite laguerre].include?(kind)
  raise CommandError, 'DEGREE LIMIT' if n > 30

  previous = Polynomial::ONE
  return previous if n.zero?
  current = case kind
            when 'chebyshev2', 'hermite' then Polynomial.linear(Fraction::ZERO, whole(2))
            when 'laguerre' then Polynomial.linear(Fraction::ONE, whole(-1))
            else Polynomial.linear(Fraction::ZERO, Fraction::ONE)
            end
  (1...n).each do |j|
    factor = case kind
             when 'legendre' then Polynomial.linear(Fraction::ZERO, whole(2 * j + 1))
             when 'laguerre' then Polynomial.linear(whole(2 * j + 1), whole(-1))
             else Polynomial.linear(Fraction::ZERO, whole(2))
             end
    multiplier = case kind
                 when 'legendre', 'laguerre' then j
                 when 'hermite' then 2 * j
                 else 1
                 end
    following = factor * current - previous.scale(whole(multiplier))
    following = following.scale(Fraction.make(1, j + 1)) if kind == 'legendre' || kind == 'laguerre'
    previous, current = current, following
  end
  current
end

Named = Data.define(:name, :value)
class Response
  attr_reader :stores, :lines
  attr_accessor :deletion
  def initialize
    @stores = []
    @lines = []
    @deletion = nil
  end
  def save(name, value)
    stores << Named.new(name, value)
    lines << "#{name} = #{value.format}"
  end
end

class Calculator
  def initialize = (@storage = {})
  def lookup(name) = @storage.fetch(name) { raise CommandError, "UNKNOWN #{name}" }
  def source_positions(command)
    case command
    when 'ADD', 'SUB', 'MUL', 'GCD', 'LCM', 'INVMOD', 'COMPOSE' then [2, 3]
    when 'POW', 'DERIV', 'INTEG', 'TANGENT' then [2]
    when 'MODPOW' then [2, 4]
    when 'DIV' then [3, 4]
    when 'XGCD' then [4, 5]
    when 'CRT' then [2, 3, 4, 5]
    when 'RESULTANT' then [1, 2]
    when 'LIST', 'INTERP', 'SPECIAL' then []
    else [1]
    end
  end

  def execute(line)
    response = Response.new
    if line.start_with?('DEF ')
      separator = line.index(' ', 4)
      name = line[4...separator]
      text = line[(separator + 1)..]
      expression = Parser.new(text).parse
      response.save(name, expression.evaluate(@storage))
    else
      words = line.split(' ')
      command = words[0]
      if command == 'DIV' && words[1] == words[2] || command == 'XGCD' &&
         (words[1] == words[2] || words[1] == words[3] || words[2] == words[3])
        raise CommandError, 'SAME NAME'
      end
      operands = source_positions(command).map { |i| lookup(words[i]) }
      start = case command
              when 'AREA', 'TAYLOR', 'EVAL', 'INTERP' then 2
              when 'TANGENT' then 3
              else words.length
              end
      values = words.drop(start).map { |text| Fraction.parse(text) }
      bounds = [Bound.parse(words[2]), Bound.parse(words[3])] if command == 'STURM'
      a, b = operands.fetch(0, Polynomial::ZERO), operands.fetch(1, Polynomial::ZERO)
      case command
      when 'PRINT' then response.lines << "#{words[1]} = #{a.format}"
      when 'DELETE'
        response.deletion = words[1]
        response.lines << "deleted #{words[1]}"
      when 'LIST'
        @storage.keys.sort.each { |name| response.lines << "#{name} = #{@storage[name].format}" }
        response.lines << 'no polynomials' if @storage.empty?
      when 'DEGREE' then response.lines << "deg(#{words[1]}) = #{a.zero? ? '-inf' : a.degree}"
      when 'ADD' then response.save(words[1], a + b)
      when 'SUB' then response.save(words[1], a - b)
      when 'MUL' then a.check_product(b); response.save(words[1], a * b)
      when 'POW'
        exponent = Integer(words[3], 10)
        a.check_power(exponent)
        response.save(words[1], a.power(exponent))
      when 'DIV'
        b.require_divisor
        division = a.divide(b)
        response.save(words[1], division.quotient)
        response.save(words[2], division.remainder)
      when 'GCD' then response.save(words[1], a.gcd(b))
      when 'XGCD'
        result = a.extended_gcd(b)
        response.save(words[1], result.g); response.save(words[2], result.s); response.save(words[3], result.t)
      when 'LCM'
        value = Polynomial::ZERO
        unless a.zero? || b.zero?
          common = a.gcd(b)
          raise CommandError, 'DEGREE LIMIT' if a.degree + b.degree - common.degree > 30
          value = (a.quotient(common) * b).monic
        end
        response.save(words[1], value)
      when 'INVMOD'
        b.require_divisor
        b.require_positive_degree
        result = a.extended_gcd(b)
        raise CommandError, 'NOT COPRIME' unless result.g.one?
        response.save(words[1], result.s.remainder(b))
      when 'CRT'
        a2, m2 = operands[2], operands[3]
        b.require_divisor; m2.require_divisor
        raise CommandError, 'DEGREE LIMIT' if b.degree + m2.degree > 30
        result = b.extended_gcd(m2)
        raise CommandError, 'NOT COPRIME' unless result.g.one?
        r1, r2 = a.remainder(b), a2.remainder(m2)
        u = ((r2 - r1) * result.s).remainder(m2)
        response.save(words[1], r1 + b * u)
      when 'MODPOW'
        b.require_divisor
        raise CommandError, 'DEGREE LIMIT' if 2 * b.degree - 2 > 30
        x, y = Polynomial::ONE.remainder(b), a.remainder(b)
        exponent = Integer(words[3], 10)
        until exponent.zero?
          x = (x * y).remainder(b) if exponent.odd?
          exponent /= 2
          y = (y * y).remainder(b) unless exponent.zero?
        end
        response.save(words[1], x)
      when 'DERIV' then response.save(words[1], a.differentiate(Integer(words[3], 10)))
      when 'INTEG'
        raise CommandError, 'DEGREE LIMIT' if !a.zero? && a.degree + 1 > 30
        response.save(words[1], a.integral)
      when 'AREA'
        integral = a.integral
        value = integral.evaluate(values[1]) - integral.evaluate(values[0])
        response.lines << "integral(#{words[1]}, #{values[0]}, #{values[1]}) = #{value}"
      when 'TANGENT'
        point = values[0]
        height = a.evaluate(point)
        slope = a.derivative.evaluate(point)
        response.save(words[1], Polynomial.linear(height - slope * point, slope))
      when 'TAYLOR'
        point = values[0]
        shifted = a.compose(Polynomial.linear(point, Fraction::ONE))
        variable = point.n.zero? ? 'x' : point.n.positive? ? "(x - #{point})" : "(x + #{-point})"
        response.lines << "taylor(#{words[1]}, #{point}) = #{shifted.format(variable)}"
      when 'COMPOSE' then a.check_composition(b); response.save(words[1], a.compose(b))
      when 'EVAL'
        values.each { |point| response.lines << "#{words[1]}(#{point}) = #{a.evaluate(point)}" }
      when 'ROOTS', 'FACTOR'
        a.require_nonzero
        roots = rational_roots(a)
        if command == 'ROOTS'
          text = roots.roots.empty? ? 'none' : roots.roots.map { |root| "#{root.value} (#{root.multiplicity})" }.join(', ')
          response.lines << "roots(#{words[1]}) = #{text}"
        else
          text = +"factor(#{words[1]}) = #{roots.content}"
          roots.roots.each do |root|
            value = root.value
            append_factor(text, Polynomial.linear(whole(-value.n), whole(value.d)), root.multiplicity, value.n.zero?)
          end
          append_factor(text, roots.remaining, 1, false) if roots.remaining.degree >= 1
          response.lines << text
        end
      when 'SQFREE'
        a.require_nonzero
        text = +"sqfree(#{words[1]}) = #{a.content}"
        square_free_factors(a).each do |factor|
          p = factor.value
          append_factor(text, p, factor.multiplicity, p.degree == 1 && p[0].n.zero? && p[1] == Fraction::ONE)
        end
        response.lines << text
      when 'DESCARTES'
        a.require_nonzero
        response.lines << "descartes(#{words[1]}) = positive #{descartes(a, false)}, negative #{descartes(a, true)}"
      when 'STURM'
        a.require_nonzero
        low, high = bounds
        raise CommandError, 'BAD INTERVAL' unless low < high
        sequence = sturm_sequence(a)
        response.lines << "sturm(#{words[1]}, #{low}, #{high}) = #{root_count(sequence, low, high)}"
      when 'ISOLATE'
        a.require_nonzero
        precision = Integer(words[2], 10)
        intervals = isolate(a, precision)
        text = intervals.empty? ? 'none' : intervals.map { |interval| "(#{interval.low}, #{interval.high}]" }.join(', ')
        response.lines << "isolate(#{words[1]}, #{precision}) = #{text}"
      when 'RESULTANT'
        a.require_nonzero; b.require_nonzero
        response.lines << "res(#{words[1]}, #{words[2]}) = #{resultant(a, b)}"
      when 'DISCRIM', 'POWERSUM'
        a.require_nonzero; a.require_positive_degree
        degree = a.degree
        if command == 'DISCRIM'
          value = resultant(a, a.derivative) / a.leading
          value = -value if (degree * (degree - 1) / 2).odd?
          response.lines << "disc(#{words[1]}) = #{value}"
        else
          count = Integer(words[2], 10)
          monic = a.monic
          sums = Array.new(count + 1, Fraction::ZERO)
          (1..count).each do |j|
            value = j <= degree ? whole(j) * monic[degree - j] : Fraction::ZERO
            (1..[j - 1, degree].min).each { |i| value += monic[degree - i] * sums[j - i] }
            sums[j] = -value
          end
          response.lines << "powersum(#{words[1]}) = #{sums.drop(1).join(', ')}"
        end
      when 'INTERP' then response.save(words[1], interpolate(values))
      when 'SPECIAL' then response.save(words[1], special(words[2], Integer(words[3], 10)))
      end
    end
    @storage.delete(response.deletion) if response.deletion
    response.stores.each { |entry| @storage[entry.name] = entry.value }
    response.lines
  end
end

if (first = STDIN.gets)
  calculator = Calculator.new
  Integer(first, 10).times do
    line = STDIN.gets.chomp
    begin
      calculator.execute(line).each { |text| STDOUT.write(text, "\n") }
    rescue CommandError => error
      STDOUT.write(error.message, "\n")
    end
  end
end
