# frozen_string_literal: true

class CommandError < StandardError; end
Format = Data.define(:types, :minimum, :maximum)
Division = Data.define(:quotient, :remainder)
Echelon = Data.define(:rows, :columns)
Decoded = Data.define(:word, :message, :error)

FORMATS = {
  'GEN' => ['NV', 2, 25], 'PCHECK' => ['NV', 2, 25],
  'HAMMING' => ['NI', 2, 2], 'SIMPLEX' => ['NI', 2, 2],
  'REPETITION' => ['NI', 2, 2], 'PARITY' => ['NI', 2, 2],
  'RM' => ['NII', 3, 3], 'CYCLIC' => ['NIV', 3, 3],
  'DUAL' => ['NA', 2, 2], 'EXTEND' => ['NA', 2, 2],
  'PUNCTURE' => ['NAI', 3, 3], 'SHORTEN' => ['NAI', 3, 3],
  'AUGMENT' => ['NA', 2, 2], 'EXPURGATE' => ['NA', 2, 2],
  'PERMUTE' => ['NAI', 3, 26], 'DIRECTSUM' => ['NAB', 3, 3],
  'UUV' => ['NAB', 3, 3], 'PRODUCT' => ['NAB', 3, 3],
  'LIST' => ['', 0, 0], 'DELETE' => ['A', 1, 1], 'SHOW' => ['A', 1, 1],
  'INFO' => ['A', 1, 1], 'SYSTEMATIC' => ['A', 1, 1], 'WEIGHTS' => ['A', 1, 1],
  'COVERING' => ['A', 1, 1], 'BURST' => ['A', 1, 1], 'TRELLIS' => ['A', 1, 1],
  'STDARRAY' => ['A', 1, 1], 'EQUAL' => ['AB', 2, 2], 'ENCODE' => ['AV', 2, 2],
  'SYNDROME' => ['AV', 2, 2], 'DECODE' => ['AV', 2, 2], 'BOUNDED' => ['AIV', 3, 3],
  'COSET' => ['AV', 2, 2], 'ERASURE' => ['AX', 2, 2], 'INTERLEAVE' => ['AIIV', 4, 11],
  'CRC' => ['VV', 2, 2], 'CRCCHECK' => ['VV', 2, 2], 'FACTOR' => ['I', 1, 1],
  'MACWILLIAMS' => ['II', 2, 26], 'BOUNDS' => ['II', 2, 2]
}.transform_values { |fields| Format.new(*fields) }.freeze
DEFINITIONS = FORMATS.keys.first(18).freeze
INDEPENDENT = %w[CRC CRCCHECK FACTOR MACWILLIAMS BOUNDS].freeze

def check(condition, message)
  raise CommandError, message unless condition
end

def valid_word?(text, kind)
  case kind
  when 'N', 'A', 'B' then text.match?(/\A[A-Za-z][A-Za-z0-9]{0,7}\z/)
  when 'I' then text.match?(/\A(?:0|[1-9][0-9]{0,3})\z/)
  when 'X' then text.match?(/\A[01?]{1,30}\z/)
  else text.match?(/\A[01]{1,30}\z/)
  end
end

def mask(n) = (1 << n) - 1
def bit(n, column) = 1 << (n - column - 1)
def weight(value) = value.to_s(2).count('1')
def bits(value, n) = value.to_s(2).rjust(n, '0')
def yes(value) = value ? 'yes' : 'no'

def divide(value, divisor)
  quotient = 0
  while value != 0 && value.bit_length >= divisor.bit_length
    shift = value.bit_length - divisor.bit_length
    quotient ^= 1 << shift
    value ^= divisor << shift
  end
  Division.new(quotient, value)
end

def basis(rows, n)
  pivots = Array.new(n, 0)
  result = []
  rows.each do |original|
    row = original
    (n - 1).downto(0) do |column|
      next if (row & (1 << column)).zero?
      if pivots[column] != 0
        row ^= pivots[column]
      else
        pivots[column] = row
        result << original
        break
      end
    end
  end
  result
end

def rref(source, n)
  rows = source.dup
  columns = []
  n.times do |column|
    rank = columns.size
    found = (rank...rows.size).find { |i| (rows[i] & bit(n, column)) != 0 }
    next unless found
    rows[rank], rows[found] = rows[found], rows[rank]
    rows.each_index do |i|
      rows[i] ^= rows[rank] if i != rank && (rows[i] & bit(n, column)) != 0
    end
    columns << column
  end
  Echelon.new(rows.take(columns.size).freeze, columns.freeze)
end

def null_space(source, n)
  reduced = rref(source, n)
  (0...n).reject { |column| reduced.columns.include?(column) }.map do |column|
    row = bit(n, column)
    reduced.rows.each_with_index do |value, i|
      row |= bit(n, reduced.columns[i]) if (value & bit(n, column)) != 0
    end
    row
  end
end

def span(rows)
  words = [0]
  rows.each { |row| words.concat(words.map { |word| word ^ row }) }
  words
end

def reed_muller(r, m)
  return [mask(1 << m)] if r.zero?
  half = 1 << (m - 1)
  reed_muller([r, m - 1].min, m - 1).map { |row| (row << half) | row } + reed_muller(r - 1, m - 1)
end

def check_dimension(n, k)
  check((1..12).cover?(k) && (1..12).cover?(n - k), "bad dimension #{n} #{k}")
end

class Code
  attr_reader :n, :g, :h, :polynomial

  def initialize(n, generator, checks = nil, polynomial = nil)
    check_dimension(n, generator.size)
    @n = n
    @g = generator.dup.freeze
    @h = (checks || null_space(@g, n)).dup.freeze
    @polynomial = polynomial
  end

  def k = g.size
  def encoder = polynomial ? 'polynomial' : 'matrix'
  def words = @words ||= span(g).freeze

  def encode(message)
    if polynomial
      shifted = message << h.size
      return shifted | divide(shifted, polynomial).remainder
    end
    g.each_with_index.reduce(0) do |word, (row, i)|
      (message & bit(k, i)).zero? ? word : word ^ row
    end
  end

  def syndrome(word)
    h.reduce(0) { |result, row| (result << 1) | (weight(row & word) & 1) }
  end

  def message_for(word)
    @messages ||= (0...(1 << k)).to_h { |message| [encode(message), message] }.freeze
    @messages.fetch(word)
  end

  def leaders
    return @leaders if @leaders
    result = Array.new(1 << h.size)
    result[0] = 0
    found = 1
    (1..n).each do |w|
      word = mask(w)
      while word < (1 << n)
        syndrome = syndrome(word)
        if result[syndrome].nil?
          result[syndrome] = word
          found += 1
          return @leaders = result.freeze if found == result.size
        end
        lowest = word & -word
        following = word + lowest
        word = following | (((following ^ word) >> 2) / lowest)
      end
    end
    @leaders = result.freeze
  end

  def decode(received)
    error = leaders[syndrome(received)]
    word = received ^ error
    Decoded.new(word, message_for(word), error)
  end

  def decoded_text(decoded)
    "codeword #{bits(decoded.word, n)} message #{bits(decoded.message, k)} " \
      "error #{bits(decoded.error, n)} weight #{weight(decoded.error)}"
  end

  def burst_correction
    seen = Array.new(1 << h.size, false)
    seen[0] = true
    (1..n).each do |size|
      variants = size == 1 ? 1 : 1 << (size - 2)
      (0..n - size).each do |offset|
        variants.times do |middle|
          word = size == 1 ? 1 : (1 << (size - 1)) | (middle << 1) | 1
          syndrome = syndrome(word << offset)
          return size - 1 if seen[syndrome]
          seen[syndrome] = true
        end
      end
    end
    raise 'No colliding burst'
  end
end

def construct(command, args, a, b)
  case command
  when 'GEN', 'PCHECK'
    n = args[1].size
    check(args.drop(1).all? { |row| row.size == n }, 'bad length')
    rows = basis(args.drop(1).map { |row| row.to_i(2) }, n)
    command == 'GEN' ? Code.new(n, rows) : Code.new(n, null_space(rows, n), rows)
  when 'HAMMING', 'SIMPLEX'
    r = args[1].to_i
    check((2..4).cover?(r), 'bad parameter')
    n = (1 << r) - 1
    rows = r.times.map do |i|
      (1..n).reduce(0) { |row, j| (row << 1) | ((j >> (r - i - 1)) & 1) }
    end
    command == 'SIMPLEX' ? Code.new(n, rows) : Code.new(n, null_space(rows, n), rows)
  when 'REPETITION', 'PARITY'
    n = args[1].to_i
    check((2..24).cover?(n), 'bad parameter')
    Code.new(n, command == 'REPETITION' ? [mask(n)] : (0...n - 1).map { |i| bit(n, i) | 1 })
  when 'RM'
    r, m = args.drop(1).map(&:to_i)
    check((1..4).cover?(m) && r <= m, 'bad parameter')
    Code.new(1 << m, reed_muller(r, m))
  when 'CYCLIC'
    n = args[1].to_i
    d = args[2].size - 1
    check((2..24).cover?(n) && args[2][0] == '1' && (1...n).cover?(d), 'bad parameter')
    divisor = args[2].to_i(2)
    check(divide((1 << n) | 1, divisor).remainder.zero?, 'not a divisor')
    k = n - d
    rows = k.times.map { |i| divisor << (k - i - 1) }
    checks = Array.new(d, 0)
    n.times do |j|
      remainder = divide(bit(n, j), divisor).remainder
      d.times { |i| checks[i] = (checks[i] << 1) | ((remainder >> (d - i - 1)) & 1) }
    end
    Code.new(n, rows, checks, divisor)
  when 'DUAL'
    Code.new(a.n, a.h, a.g)
  when 'EXTEND'
    Code.new(a.n + 1, a.g.map { |row| (row << 1) | (weight(row) & 1) })
  when 'PUNCTURE', 'SHORTEN', 'EXPURGATE'
    expurgating = command == 'EXPURGATE'
    position = expurgating ? 0 : args[2].to_i
    check((1..a.n).cover?(position), 'bad position') unless expurgating
    n = a.n - (expurgating ? 0 : 1)
    selected = ->(row) { expurgating ? weight(row).odd? : (row & bit(a.n, position - 1)) != 0 }
    removed = command == 'PUNCTURE' ? nil : a.g.index(&selected)
    rows = []
    a.g.each_with_index do |original, i|
      next if i == removed
      row = original
      row ^= a.g[removed] if removed && selected.call(row)
      unless expurgating
        low = a.n - position
        row = ((row >> (low + 1)) << low) | (row & mask(low))
      end
      rows << row
    end
    Code.new(n, command == 'PUNCTURE' ? basis(rows, n) : rows)
  when 'AUGMENT'
    Code.new(a.n, basis(a.g + [mask(a.n)], a.n))
  when 'PERMUTE'
    positions = args.drop(2).map(&:to_i)
    check(positions.size == a.n && positions.sort == (1..a.n).to_a, 'bad permutation')
    rows = a.g.map do |original|
      positions.reduce(0) { |row, position| (row << 1) | ((original & bit(a.n, position - 1)).zero? ? 0 : 1) }
    end
    Code.new(a.n, rows)
  when 'DIRECTSUM', 'UUV', 'PRODUCT'
    check(a.n == b.n, 'bad length') if command == 'UUV'
    product = command == 'PRODUCT'
    n = product ? a.n * b.n : a.n + b.n
    check_dimension(n, product ? a.k * b.k : a.k + b.k)
    rows = if product
             a.g.flat_map do |x|
               b.g.map do |y|
                 a.n.times.reduce(0) { |row, i| (row << b.n) | ((x & bit(a.n, i)).zero? ? 0 : y) }
               end
             end
           else
             a.g.map { |row| (row << b.n) | (command == 'UUV' ? row : 0) } + b.g
           end
    Code.new(n, rows)
  else
    raise 'Not a defining command'
  end
end

def distribution(words, offset, n)
  counts = Array.new(n + 1, 0)
  words.each { |word| counts[weight(word ^ offset)] += 1 }
  counts
end

def weight_list(counts)
  counts.each_index.filter_map { |i| "#{i}:#{counts[i]}" unless counts[i].zero? }.join(' ')
end

COMBINATIONS = Array.new(25) { Array.new(25, 0) }
(0..24).each do |n|
  COMBINATIONS[n][0] = COMBINATIONS[n][n] = 1
  (1...n).each { |k| COMBINATIONS[n][k] = COMBINATIONS[n - 1][k - 1] + COMBINATIONS[n - 1][k] }
  COMBINATIONS[n].freeze
end
COMBINATIONS.freeze

def choose(n, k) = k < 0 || k > n ? 0 : COMBINATIONS[n][k]
def volume(n, radius) = (0..radius).sum { |i| choose(n, i) }
def krawtchouk(n, j, x)
  (0..j).sum do |y|
    term = choose(x, y) * choose(n - x, j - y)
    y.even? ? term : -term
  end
end

def matrix_text(label, rows, n) = rows.map { |row| "#{label} #{bits(row, n)}" }

def systematic(name, code)
  rows = code.g.dup
  permutation = (1..code.n).to_a
  code.k.times do |r|
    column = r
    found = nil
    loop do
      found = (r...rows.size).find { |i| (rows[i] & bit(code.n, column)) != 0 }
      break if found
      column += 1
    end
    if column != r
      left = bit(code.n, r)
      right = bit(code.n, column)
      rows.map! { |row| ((row & left) != 0) != ((row & right) != 0) ? row ^ left ^ right : row }
      permutation[r], permutation[column] = permutation[column], permutation[r]
    end
    rows[r], rows[found] = rows[found], rows[r]
    rows.each_index { |i| rows[i] ^= rows[r] if i != r && (rows[i] & bit(code.n, r)) != 0 }
  end
  out = ["systematic #{name} perm #{permutation.join(' ')}"] + matrix_text('G', rows, code.n)
  code.h.size.times do |j|
    row = rows.reduce(0) { |value, x| (value << 1) | ((x & bit(code.n, code.k + j)).zero? ? 0 : 1) }
    out << "H #{bits((row << code.h.size) | bit(code.h.size, j), code.n)}"
  end
  out
end

def independent(command, args)
  if command == 'CRC' || command == 'CRCCHECK'
    d = args[0].size - 1
    check(args[0][0] == '1' && (1..16).cover?(d), 'bad parameter')
    check(args[1].size + d <= 30, 'bad length') if command == 'CRC'
    value = args[1].to_i(2) << (command == 'CRC' ? d : 0)
    remainder = divide(value, args[0].to_i(2)).remainder
    suffix = bits(remainder, d)
    return [command == 'CRC' ? "crc remainder #{suffix} frame #{args[1]}#{suffix}" :
      "crccheck #{remainder.zero? ? 'ok' : 'error'} remainder #{suffix}"]
  end
  n = args[0].to_i
  if command == 'BOUNDS'
    d = args[1].to_i
    check(d >= 1 && d <= n && n <= 24, 'bad parameter')
    ball = volume(n, (d - 1) / 2)
    hamming = (0..n).select { |k| (1 << k) * ball <= (1 << n) }.last
    sum = 0
    griesmer = 0
    (1..n).each do |k|
      denominator = 1 << (k - 1)
      sum += (d + denominator - 1) / denominator
      griesmer = k if sum <= n
    end
    return ["bounds n #{n} d #{d} singleton #{n - d + 1} hamming #{hamming} griesmer #{griesmer}"]
  end
  check((1..24).cover?(n), 'bad parameter')
  if command == 'FACTOR'
    remaining = (1 << n) | 1
    divisors = 1
    factor = 3
    terms = []
    while 2 * (factor.bit_length - 1) <= remaining.bit_length - 1
      exponent = 0
      loop do
        result = divide(remaining, factor)
        break unless result.remainder.zero?
        remaining = result.quotient
        exponent += 1
      end
      if exponent != 0
        terms << "#{factor.to_s(2)}^#{exponent}"
        divisors *= exponent + 1
      end
      factor += 2
    end
    if remaining != 1
      terms << "#{remaining.to_s(2)}^1"
      divisors *= 2
    end
    return ["factor #{n} #{terms.join(' ')} divisors #{divisors}"]
  end
  check(args.size == n + 2, 'bad length')
  check(args[1].to_i == 1, 'bad parameter')
  coefficients = args.drop(1).map(&:to_i)
  size = coefficients.sum
  feasible = (size & (size - 1)).zero?
  dual = (0..n).map do |j|
    numerator = (0..n).sum { |x| coefficients[x] * krawtchouk(n, j, x) }
    feasible = false if numerator.negative? || numerator % size != 0
    divisor = numerator.gcd(size)
    denominator = size / divisor
    denominator == 1 ? (numerator / divisor).to_s : "#{numerator / divisor}/#{denominator}"
  end
  ["macwilliams n #{n} size #{size}", "dual #{dual.join(' ')}", "feasible #{yes(feasible)}"]
end

class Laboratory
  def initialize
    @codes = {}
  end

  def process(input)
    words = input.split(' ')
    command = words[0]
    format = FORMATS[command]
    raise CommandError, "unknown command #{command}" unless format
    args = words.drop(1)
    check((format.minimum..format.maximum).cover?(args.size), 'bad arguments')
    args.each_with_index do |word, i|
      check(valid_word?(word, format.types[[i, format.types.size - 1].min]), 'bad arguments')
    end
    a = b = nil
    format.types.each_char.with_index do |kind, i|
      next unless kind == 'A' || kind == 'B'
      code = @codes[args[i]]
      raise CommandError, "no code #{args[i]}" unless code
      kind == 'A' ? a = code : b = code
    end
    if DEFINITIONS.include?(command)
      code = construct(command, args, a, b)
      status = @codes.key?(args[0]) ? 'redefined' : 'defined'
      @codes[args[0]] = code
      return "#{status} #{args[0]} n #{code.n} k #{code.k}\n"
    end
    return independent(command, args).join("\n") + "\n" if INDEPENDENT.include?(command)
    if command == 'LIST'
      out = ["codes #{@codes.size}"]
      @codes.keys.sort.each do |name|
        code = @codes[name]
        out << "#{name} n #{code.n} k #{code.k} encoder #{code.encoder}"
      end
      return out.join("\n") + "\n"
    end
    name = args[0]
    if command == 'DELETE'
      @codes.delete(name)
      return "deleted #{name}\n"
    end
    n = a.n
    k = a.k
    out = []
    case command
    when 'SHOW'
      out << "code #{name} n #{n} k #{k} encoder #{a.encoder}"
      if a.polynomial
        quotient = divide((1 << n) | 1, a.polynomial).quotient
        out << "poly g #{bits(a.polynomial, n - k + 1)} h #{bits(quotient, k + 1)}"
      end
      out.concat(matrix_text('G', a.g, n)).concat(matrix_text('H', a.h, n))
    when 'INFO'
      nonzero = a.words.drop(1)
      distance = nonzero.map { |word| weight(word) }.min
      generator = nonzero.min
      t = (distance - 1) / 2
      divisor = k.gcd(n)
      cyclic = a.g.all? { |row| a.syndrome(((row << 1) & mask(n)) | (row >> (n - 1))).zero? }
      out << "info #{name} n #{n} k #{k} rate #{k / divisor}/#{n / divisor} d #{distance} t #{t} " \
        "perfect #{yes(volume(n, t) == (1 << (n - k)))} mds #{yes(distance == n - k + 1)} " \
        "cyclic #{cyclic ? generator.to_s(2) : 'no'}"
    when 'SYSTEMATIC'
      out = systematic(name, a)
    when 'WEIGHTS'
      primary = distribution(a.words, 0, n)
      dual = distribution(span(a.h), 0, n)
      orthogonal = a.g.all? { |x| a.g.all? { |y| weight(x & y).even? } }
      out << "weights #{name} #{weight_list(primary)}" << "dual #{name} #{weight_list(dual)}"
      out << "duality #{name} self-orthogonal #{yes(orthogonal)} self-dual #{yes(orthogonal && n == 2 * k)} " \
        "formally-self-dual #{yes(primary == dual)}"
    when 'COVERING'
      counts = distribution(a.leaders, 0, n)
      radius = counts.rindex { |count| count != 0 }
      out << "covering #{name} radius #{radius} leaders #{(0..radius).map { |i| "#{i}:#{counts[i]}" }.join(' ')}"
    when 'BURST'
      detect = a.words.drop(1).map { |word| word.bit_length - (word & -word).bit_length }.min
      out << "burst #{name} detect #{detect} correct #{a.burst_correction}"
    when 'TRELLIS'
      profile = (0..n).map do |cut|
        basis(a.g.map { |row| row >> (n - cut) }, cut).size +
          basis(a.g.map { |row| row & mask(n - cut) }, n - cut).size - k
      end
      out << "trellis #{name} profile #{profile.join(' ')} max #{profile.max}"
    when 'STDARRAY'
      check(n - k <= 6 && k <= 4, 'too large')
      leaders = a.leaders
      syndromes = leaders.each_index.sort_by { |s| [weight(leaders[s]), leaders[s]] }
      codewords = a.words.sort
      out << "stdarray #{name} rows #{leaders.size} columns #{codewords.size}"
      syndromes.each do |s|
        out << "#{bits(s, n - k)}: #{codewords.map { |word| bits(leaders[s] ^ word, n) }.join(' ')}"
      end
    when 'EQUAL'
      if n != b.n
        out << "equal #{name} #{args[1]} no lengths #{n} #{b.n}"
      else
        common = k + b.k - basis(a.g + b.g, n).size
        out << "equal #{name} #{args[1]} #{yes(k == common && b.k == common)} intersection #{common}"
      end
    when 'ENCODE'
      check(args[1].size == k, 'bad length')
      out << "encode #{name} message #{args[1]} codeword #{bits(a.encode(args[1].to_i(2)), n)}"
    when 'SYNDROME', 'DECODE', 'BOUNDED', 'COSET'
      text = args[command == 'BOUNDED' ? 2 : 1]
      check(text.size == n, 'bad length')
      word = text.to_i(2)
      syndrome = a.syndrome(word)
      if command == 'SYNDROME'
        out << "syndrome #{name} #{bits(syndrome, n - k)} codeword #{yes(syndrome.zero?)}"
      else
        decoded = a.decode(word)
        if command == 'COSET'
          out << "coset #{name} syndrome #{bits(syndrome, n - k)} leader #{bits(decoded.error, n)} " \
            "weights #{weight_list(distribution(a.words, word, n))}"
        elsif command == 'BOUNDED' && weight(decoded.error) > args[1].to_i
          out << "bounded #{name} fail weight #{weight(decoded.error)}"
        else
          out << "#{command == 'BOUNDED' ? 'bounded' : 'decode'} #{name} #{a.decoded_text(decoded)}"
        end
      end
    when 'ERASURE'
      check(args[1].size == n, 'bad length')
      known = value = erased = 0
      args[1].each_char.with_index do |c, i|
        if c == '?'
          erased += 1
        else
          known |= bit(n, i)
          value |= bit(n, i) if c == '1'
        end
      end
      candidates = a.words.select { |word| (word & known) == value }
      text = "erasure #{name} erased #{erased} candidates #{candidates.size}"
      if candidates.size == 1
        text += " codeword #{bits(candidates[0], n)} message #{bits(a.message_for(candidates[0]), k)}"
      end
      out << text
    when 'INTERLEAVE'
      depth = args.size - 3
      start = args[1].to_i
      size = args[2].to_i
      check(args.drop(3).all? { |message| message.size == k }, 'bad length')
      check(start >= 1 && size >= 1 && start + size - 1 <= depth * n, 'bad burst')
      sent_rows = args.drop(3).map { |message| a.encode(message.to_i(2)) }
      received_rows = Array.new(depth, 0)
      sent = +''
      received = +''
      n.times do |column|
        depth.times do |i|
          position = column * depth + i + 1
          value = (sent_rows[i] & bit(n, column)) != 0
          sent << (value ? '1' : '0')
          value = !value if position >= start && position < start + size
          received << (value ? '1' : '0')
          received_rows[i] = (received_rows[i] << 1) | (value ? 1 : 0)
        end
      end
      out << "interleave #{name} depth #{depth} burst #{start} #{size}" << "sent #{sent}" << "recv #{received}"
      correct = 0
      depth.times do |i|
        decoded = a.decode(received_rows[i])
        ok = decoded.message == args[i + 3].to_i(2)
        correct += 1 if ok
        out << "row #{i + 1} errors #{weight(received_rows[i] ^ sent_rows[i])} corrected #{weight(decoded.error)} " \
          "message #{bits(decoded.message, k)} #{ok ? 'ok' : 'wrong'}"
      end
      out << "result ok #{correct} wrong #{depth - correct}"
    end
    out.join("\n") + "\n"
  end
end

laboratory = Laboratory.new
STDIN.gets.to_i.times do
  begin
    STDOUT.write(laboratory.process(STDIN.gets.chomp))
  rescue CommandError => e
    STDOUT.write("error: #{e.message}\n")
  end
end
