INVALID = 1
DIVBYZERO = 2
OVERFLOW = 4
UNDERFLOW = 8
INEXACT = 16
MODES = %i[RNE RNA RTZ RUP RDN].freeze
FLAG_NAMES = %w[invalid divbyzero overflow underflow inexact].freeze
INTEGER_RANGES = {
  'I8' => (-128..127), 'U8' => (0..255), 'I16' => (-32768..32767),
  'U16' => (0..65535), 'I32' => (-2147483648..2147483647), 'U32' => (0..4294967295)
}.freeze

class CommandError < StandardError; end

Term = Data.define(:negative, :magnitude, :exponent) do
  def product(other)
    Term.new(negative != other.negative, magnitude * other.magnitude, exponent + other.exponent)
  end

  def negated = with(negative: !negative)
  def exact = Exact.make(negative, magnitude, exponent)

  def decimal
    return '0' if magnitude.zero?

    numerator, denominator = exact.scaled(0)
    whole, remainder = numerator.divmod(denominator)
    text = "#{negative ? '-' : ''}#{whole}"
    text << '.' unless remainder.zero?
    until remainder.zero?
      digit, remainder = (remainder * 10).divmod(denominator)
      text << (48 + digit).chr
    end
    text
  end
end

def sum_terms(terms, mode)
  exponent = terms.reject { |term| term.magnitude.zero? }.map(&:exponent).min || 0
  sum = terms.sum do |term|
    next 0 if term.magnitude.zero?

    aligned = term.magnitude << (term.exponent - exponent)
    term.negative ? -aligned : aligned
  end
  if sum.zero?
    same_zero = terms.all? { |term| term.magnitude.zero? && term.negative == terms.first.negative }
    return Term.new(same_zero ? terms.first.negative : mode == :RDN, 0, 0)
  end
  Term.new(sum.negative?, sum.abs, exponent)
end

Exact = Data.define(:negative, :numerator, :exponent, :denominator) do
  def self.make(negative, numerator, exponent = 0, denominator = 1)
    return new(negative, 0, 0, 1) if numerator.zero?

    common = numerator.gcd(denominator)
    numerator /= common
    denominator /= common
    while numerator.even?
      numerator >>= 1
      exponent += 1
    end
    while denominator.even?
      denominator >>= 1
      exponent -= 1
    end
    new(negative, numerator, exponent, denominator)
  end

  def scaled(quantum)
    shift = exponent - quantum
    shift >= 0 ? [numerator << shift, denominator] : [numerator, denominator << -shift]
  end

  def floor_log
    power = numerator.bit_length - denominator.bit_length
    below = power >= 0 ? numerator < (denominator << power) : (numerator << -power) < denominator
    exponent + power - (below ? 1 : 0)
  end

  def fraction
    return '0' if numerator.zero?

    n, d = scaled(0)
    "#{negative ? '-' : ''}#{n}#{d == 1 ? '' : "/#{d}"}"
  end
end

Quantized = Data.define(:whole, :inexact, :half) do
  def self.from(value, quantum, square_root)
    numerator, denominator = value.scaled(square_root ? 2 * quantum : quantum)
    unless square_root
      whole, remainder = numerator.divmod(denominator)
      return new(whole, !remainder.zero?, remainder <=> denominator - remainder)
    end
    whole = Integer.sqrt(numerator / denominator)
    midpoint = 2 * whole + 1
    new(whole, whole * whole * denominator != numerator, 4 * numerator <=> midpoint * midpoint * denominator)
  end

  def rounded(mode, negative)
    increment = case mode
                when :RNE then half.positive? || half.zero? && whole.odd?
                when :RNA then half >= 0
                when :RTZ then false
                when :RUP then inexact && !negative
                when :RDN then inexact && negative
                end
    whole + (increment ? 1 : 0)
  end
end

Rounded = Data.define(:pattern, :flags)
Operand = Data.define(:pattern, :number)

class MiniFormat
  attr_reader :name, :e, :m, :w, :bias, :emin, :emax, :sign, :base, :infinity, :nan

  def initialize(name, e, m)
    @name, @e, @m = name.freeze, e, m
    @w = 1 + e + m
    @bias = (1 << (e - 1)) - 1
    @emin = 1 - bias
    @emax = bias
    @sign = 1 << (e + m)
    @base = 1 << m
    @infinity = ((1 << e) - 1) << m
    @nan = infinity | (base / 2)
    freeze
  end

  def negative?(pattern) = (pattern & sign) != 0
  def zero?(pattern) = (pattern & (sign - 1)).zero?
  def signed(pattern, negative) = pattern | (negative ? sign : 0)

  def kind(pattern)
    magnitude = pattern & (sign - 1)
    fraction = pattern & (base - 1)
    if magnitude >= infinity
      return :infinity if fraction.zero?

      return fraction >= base / 2 ? :qnan : :snan
    end
    return :zero if magnitude.zero?

    magnitude < base ? :subnormal : :normal
  end

  def finite?(pattern) = %i[zero subnormal normal].include?(kind(pattern))
  def nan?(pattern) = %i[qnan snan].include?(kind(pattern))

  def term(pattern)
    field = (pattern & (sign - 1)) >> m
    fraction = pattern & (base - 1)
    Term.new(negative?(pattern), field.zero? ? fraction : base + fraction,
             field.zero? ? emin - m : field - bias - m)
  end

  def overflow(mode, negative)
    to_infinity = %i[RNE RNA].include?(mode) || mode == :RUP && !negative || mode == :RDN && negative
    Rounded.new(signed(to_infinity ? infinity : infinity - 1, negative), OVERFLOW | INEXACT)
  end

  def round(value, mode, square_root = false)
    return Rounded.new(signed(0, value.negative), 0) if value.numerator.zero?

    t = value.floor_log
    t = t.div(2) if square_root
    return overflow(mode, value.negative) if t > emax

    quantum = [t, emin].max - m
    divided = Quantized.from(value, quantum, square_root)
    significand = divided.rounded(mode, value.negative)
    if significand == 2 * base
      significand = base
      quantum += 1
    end
    return overflow(mode, value.negative) if quantum > emax - m

    flags = divided.inexact ? INEXACT : 0
    if divided.inexact && t < emin
      tiny = t < emin - 1 || Quantized.from(value, t - m, square_root).rounded(mode, value.negative) < 2 * base
      flags |= UNDERFLOW if tiny
    end
    magnitude = if significand < base
                  significand
                else
                  ((quantum + m + bias) << m) | (significand - base)
                end
    Rounded.new(signed(magnitude, value.negative), flags)
  end

  def round_term(term, mode) = round(term.exact, mode)
  def round_sum(terms, mode) = round_term(sum_terms(terms, mode), mode)

  def arithmetic(operation, a, b, c, mode)
    if operation == :SUB
      b ^= sign
      operation = :ADD
    end
    inputs = operation == :SQRT ? [a] : operation == :FMA ? [a, b, c] : [a, b]
    if inputs.any? { |p| nan?(p) }
      return Rounded.new(nan, inputs.any? { |p| kind(p) == :snan } ? INVALID : 0)
    end
    ai, bi = kind(a) == :infinity, kind(b) == :infinity
    sigma = negative?(a) != negative?(b)
    invalid = Rounded.new(nan, INVALID)
    case operation
    when :ADD
      return invalid if ai && bi && sigma
      return Rounded.new(ai ? a : b, 0) if ai || bi

      round_sum([term(a), term(b)], mode)
    when :MUL
      return zero?(a) || zero?(b) ? invalid : Rounded.new(signed(infinity, sigma), 0) if ai || bi

      round_term(term(a).product(term(b)), mode)
    when :DIV
      return bi ? invalid : Rounded.new(signed(infinity, sigma), 0) if ai
      return Rounded.new(signed(0, sigma), 0) if bi
      return zero?(a) ? invalid : Rounded.new(signed(infinity, sigma), DIVBYZERO) if zero?(b)
      return Rounded.new(signed(0, sigma), 0) if zero?(a)

      x, y = term(a), term(b)
      round(Exact.make(sigma, x.magnitude, x.exponent - y.exponent, y.magnitude), mode)
    when :SQRT
      return Rounded.new(a, 0) if zero?(a)
      return invalid if negative?(a)
      return Rounded.new(a, 0) if ai

      round(term(a).exact, mode, true)
    when :FMA
      if ai || bi
        return invalid if zero?(a) || zero?(b) || kind(c) == :infinity && negative?(c) != sigma

        return Rounded.new(signed(infinity, sigma), 0)
      end
      return Rounded.new(c, 0) if kind(c) == :infinity

      round_sum([term(a).product(term(b)), term(c)], mode)
    end
  end

  def raw_operand(word, encoding)
    if word.start_with?('0b', '0x')
      binary = word.start_with?('0b')
      width = binary ? w : (w + 3) / 4
      raise CommandError, "ERROR BAD OPERAND #{word}" if encoding || word.length - 2 != width

      pattern = word[2..].to_i(binary ? 2 : 16)
      raise CommandError, "ERROR BAD OPERAND #{word}" if pattern >= 2 * sign

      return Operand.new(pattern, nil)
    end
    case word
    when 'nan' then return Operand.new(nan, nil)
    when 'inf' then return Operand.new(infinity, nil)
    when '-inf' then return Operand.new(infinity | sign, nil)
    end
    negative = word.start_with?('-')
    digits = word.delete_prefix('-')
    if digits.include?('/')
      numerator, denominator = digits.split('/').map { |part| part.to_i(10) }
      raise CommandError, "ERROR BAD OPERAND #{word}" if denominator.zero?
    elsif digits.include?('.')
      integer, fraction = digits.split('.')
      numerator = (integer + fraction).to_i(10)
      denominator = 10**fraction.length
    else
      numerator, denominator = digits.to_i(10), 1
    end
    Operand.new(0, Exact.make(negative, numerator, 0, denominator))
  end

  def operand(word)
    value = raw_operand(word, false)
    value.number ? round(value.number, :RNE).pattern : value.pattern
  end

  def bits(pattern)
    "#{negative?(pattern) ? 1 : 0}|#{binary((pattern & (sign - 1)) >> m, e)}|#{binary(pattern & (base - 1), m)}"
  end
  def hex(pattern) = format('0x%0*X', (w + 3) / 4, pattern)

  def value(pattern)
    case kind(pattern)
    when :qnan, :snan then 'nan'
    when :infinity then negative?(pattern) ? '-inf' : 'inf'
    when :zero then negative?(pattern) ? '-0' : '0'
    else term(pattern).decimal
    end
  end

  def pattern_text(pattern) = "#{bits(pattern)} #{hex(pattern)} #{value(pattern)}"
  def result_text(result) = "#{pattern_text(result.pattern)} #{flag_text(result.flags)}"
  def difference(pattern, exact_sum)
    finite?(pattern) ? sum_terms([term(pattern), exact_sum.negated], :RNE).exact.fraction : value(pattern)
  end
  def order_key(pattern) = negative?(pattern) ? -(pattern - sign) - 1 : pattern

  def next_up(pattern)
    return pattern if pattern == infinity
    return 1 if zero?(pattern)

    negative?(pattern) ? pattern - 1 : pattern + 1
  end
end

def binary(value, width) = value.to_s(2).rjust(width, '0')

def flag_text(flags)
  names = FLAG_NAMES.each_with_index.filter_map { |name, i| name unless (flags & (1 << i)).zero? }
  "flags=#{names.empty? ? 'none' : names.join(',')}"
end

def parse_mode(word)
  mode = word.to_sym
  raise CommandError, "ERROR BAD MODE #{word}" unless MODES.include?(mode)

  mode
end

def mode_at(words, index) = words[index] ? parse_mode(words[index]) : :RNE
def integer_range(word) = INTEGER_RANGES.fetch(word) { raise CommandError, "ERROR BAD TYPE #{word}" }
def relation(a, b) = a < b ? 'LT' : a == b ? 'EQ' : 'GT'

def summation(f, words)
  command = words[0]
  mode = parse_mode(words[2])
  values = []
  left_count = 0
  words.drop(3).each do |word|
    if word == '|'
      left_count = values.length
    else
      values << f.operand(word)
    end
  end
  if command == 'DOT' && left_count != values.length - left_count
    raise CommandError, 'ERROR LENGTH MISMATCH'
  end
  raise CommandError, 'ERROR NOT FINITE' unless values.all? { |p| f.finite?(p) }

  if command == 'DOT'
    terms = Array.new(left_count) { |i| f.term(values[i]).product(f.term(values[left_count + i])) }
    exact_sum = sum_terms(terms, mode)
    first = f.arithmetic(:MUL, values.first, values[left_count], 0, mode)
    naive = chained = first
    (1...left_count).each do |i|
      multiplied = f.arithmetic(:MUL, values[i], values[left_count + i], 0, mode)
      added = f.arithmetic(:ADD, naive.pattern, multiplied.pattern, 0, mode)
      naive = Rounded.new(added.pattern, naive.flags | multiplied.flags | added.flags)
    end
    (1...left_count).each do |i|
      fused = f.arithmetic(:FMA, values[i], values[left_count + i], chained.pattern, mode)
      chained = Rounded.new(fused.pattern, chained.flags | fused.flags)
    end
    return [
      "DOT #{f.name} #{mode} n=#{left_count}",
      "NAIVE #{f.result_text(naive)}",
      "CHAINED #{f.result_text(chained)}",
      "EXACT #{exact_sum.decimal}",
      "FUSED #{f.result_text(f.round_term(exact_sum, mode))}",
      "DIFF naive=#{f.difference(naive.pattern, exact_sum)} chained=#{f.difference(chained.pattern, exact_sum)}"
    ]
  end
  exact_sum = sum_terms(values.map { |p| f.term(p) }, mode)
  result = Rounded.new(values.first, 0)
  compensation = 0
  out = ["#{command} #{f.name} #{mode} count=#{values.length}"]
  values.each_with_index do |value, i|
    next if i.zero?

    if command == 'SUM'
      added = f.arithmetic(:ADD, result.pattern, value, 0, mode)
      result = Rounded.new(added.pattern, result.flags | added.flags)
      out << "PARTIAL #{i + 1} #{f.result_text(added)}"
    else
      y = f.arithmetic(:SUB, value, compensation, 0, mode)
      t = f.arithmetic(:ADD, result.pattern, y.pattern, 0, mode)
      d = f.arithmetic(:SUB, t.pattern, result.pattern, 0, mode)
      c = f.arithmetic(:SUB, d.pattern, y.pattern, 0, mode)
      flags = y.flags | t.flags | d.flags | c.flags
      result = Rounded.new(t.pattern, result.flags | flags)
      compensation = c.pattern
      out << "KSTEP #{i + 1} sum=#{f.value(result.pattern)} comp=#{f.value(compensation)} #{flag_text(flags)}"
    end
  end
  out << "RESULT #{f.result_text(result)}"
  out << "EXACT #{exact_sum.decimal}"
  out << "ROUNDED #{f.result_text(f.round_term(exact_sum, mode))}"
  out << "DIFF #{f.difference(result.pattern, exact_sum)}"
  out
end

def table(f)
  raise CommandError, 'ERROR TABLE TOO LARGE' if f.w > 8

  out = ["TABLE #{f.name} count=#{f.infinity}"]
  f.infinity.times do |p|
    gap = p + 1 == f.infinity ? '-' : sum_terms([f.term(p + 1), f.term(p).negated], :RNE).decimal
    out << "ENTRY #{p} #{f.pattern_text(p)} gap=#{gap}"
  end
  out << "MAX #{f.pattern_text(f.infinity - 1)}"
  out << "MINNORMAL #{f.pattern_text(f.base)}"
  out << "MINSUBNORMAL #{f.pattern_text(1)}"
  out << "EPSILON #{Term.new(false, 1, -f.m).decimal}"
  out << "PATTERNS finite=#{2 * f.infinity} infinite=2 nan=#{2 * (f.base - 1)} total=#{2 * f.sign}"
  out
end

class Laboratory
  def initialize
    @formats = {
      'HALF' => MiniFormat.new('HALF', 5, 10), 'E5M2' => MiniFormat.new('E5M2', 5, 2),
      'E4M3' => MiniFormat.new('E4M3', 4, 3)
    }
  end

  def find_format(name)
    @formats.fetch(name) { raise CommandError, "ERROR UNKNOWN FORMAT #{name}" }
  end

  def execute(words)
    command = words[0]
    if command == 'FORMAT'
      name = words[1]
      raise CommandError, "ERROR FORMAT EXISTS #{name}" if @formats.key?(name)

      e, m = words[2].to_i(10), words[3].to_i(10)
      raise CommandError, 'ERROR BAD FORMAT' unless (2..5).cover?(e) && (1..10).cover?(m)

      f = MiniFormat.new(name, e, m)
      @formats[name] = f
      return ["FORMAT #{name} e=#{e} m=#{m} bits=#{f.w} bias=#{f.bias} emin=#{f.emin} emax=#{f.emax}"]
    end
    f = find_format(words[1])
    return table(f) if command == 'TABLE'
    return summation(f, words) if %w[SUM KAHAN DOT].include?(command)

    if command == 'CONVERT'
      g = find_format(words[2])
      a = f.operand(words[3])
      mode = mode_at(words, 4)
      result = case f.kind(a)
               when :qnan then Rounded.new(g.nan, 0)
               when :snan then Rounded.new(g.nan, INVALID)
               when :infinity then Rounded.new(g.signed(g.infinity, f.negative?(a)), 0)
               when :zero then Rounded.new(g.signed(0, f.negative?(a)), 0)
               else g.round_term(f.term(a), mode)
               end
      return ["CONVERT #{f.name} #{g.name} #{mode} #{g.result_text(result)}"]
    end
    if command == 'ENCODE'
      value = f.raw_operand(words[2], true)
      mode = mode_at(words, 3)
      result = value.number ? f.round(value.number, mode) : Rounded.new(value.pattern, 0)
      source = value.number ? value.number.fraction : f.value(value.pattern)
      return ["ENCODE #{f.name} #{mode} #{source} #{f.result_text(result)}"]
    end
    a = f.operand(words[2])
    case command
    when 'DECODE'
      kind = f.kind(a)
      exponent = (a & (f.sign - 1)) >> f.m
      fraction = a & (f.base - 1)
      out = ["DECODE #{f.name} #{f.bits(a)} #{f.hex(a)} #{kind} sign=#{f.negative?(a) ? 1 : 0}"]
      if f.finite?(a)
        term = f.term(a)
        out << "FIELDS exponent=#{exponent} fraction=#{fraction} unbiased=#{term.exponent + f.m} significand=#{kind == :normal ? 1 : 0}.#{binary(fraction, f.m)}"
        out << "VALUE #{term.exact.fraction} #{f.value(a)}"
      elsif kind == :infinity
        out << "FIELDS exponent=#{exponent} fraction=#{fraction}"
      else
        out << "FIELDS exponent=#{exponent} fraction=#{fraction} payload=#{fraction % (f.base / 2)}"
      end
      out
    when 'COMPARE'
      b = f.operand(words[3])
      ak, bk = f.order_key(a), f.order_key(b)
      numeric = if f.nan?(a) || f.nan?(b)
                  'UN'
                elsif f.zero?(a) && f.zero?(b)
                  'EQ'
                else
                  relation(ak, bk)
                end
      flags = f.kind(a) == :snan || f.kind(b) == :snan ? INVALID : 0
      ["COMPARE #{f.name} #{f.hex(a)} #{f.hex(b)} #{numeric} total=#{relation(ak, bk)} #{flag_text(flags)}"]
    when 'TOINT'
      range = integer_range(words[3])
      mode = mode_at(words, 4)
      prefix = "TOINT #{f.name} #{words[3]} #{mode}"
      return ["#{prefix} invalid flags=invalid"] unless f.finite?(a)

      value = f.term(a).exact
      divided = Quantized.from(value, 0, false)
      magnitude = divided.rounded(mode, value.negative)
      result = value.negative ? -magnitude : magnitude
      return ["#{prefix} invalid flags=invalid"] unless range.cover?(result)

      ["#{prefix} #{result} #{flag_text(divided.inexact ? INEXACT : 0)}"]
    when 'NEXTUP', 'NEXTDOWN', 'ULP'
      if f.nan?(a)
        result = Rounded.new(f.nan, f.kind(a) == :snan ? INVALID : 0)
      else
        pattern = case command
                  when 'NEXTUP' then f.next_up(a)
                  when 'NEXTDOWN' then f.next_up(a ^ f.sign) ^ f.sign
                  else
                    f.kind(a) == :infinity ? f.infinity : f.round_term(Term.new(false, 1, f.term(a).exponent), :RNE).pattern
                  end
        result = Rounded.new(pattern, 0)
      end
      ["#{command} #{f.name} #{f.result_text(result)}"]
    else
      operation = command.to_sym
      arity = operation == :SQRT ? 1 : operation == :FMA ? 3 : 2
      b = arity >= 2 ? f.operand(words[3]) : 0
      c = arity == 3 ? f.operand(words[4]) : 0
      mode = mode_at(words, arity + 2)
      ["#{command} #{f.name} #{mode} #{f.result_text(f.arithmetic(operation, a, b, c, mode))}"]
    end
  end
end

count = $stdin.gets.to_i(10)
laboratory = Laboratory.new
count.times do
  begin
    puts laboratory.execute($stdin.gets.split)
  rescue CommandError => error
    puts error.message
  end
end
