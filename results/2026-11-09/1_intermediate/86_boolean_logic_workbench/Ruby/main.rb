require 'set'

class LogicError < StandardError
end

PRECEDENCE = { '<->' => 1, '->' => 2, '|' => 3, '^' => 4, '&' => 5 }.freeze

def variable(name) = [:variable, name]
def constant(value) = [:constant, value]
def negate(node) = [:not, node]
def binary(operation, left, right) = [operation, left, right]
def binary?(node) = PRECEDENCE.key?(node[0])

def notation(node)
  return node[1].to_s if %i[variable constant].include?(node[0])
  if node[0] == :not
    text = notation(node[1])
    return '~' + (binary?(node[1]) ? '(' + text + ')' : text)
  end
  operation, a, b = node
  left = notation(a)
  right = notation(b)
  left = '(' + left + ')' if binary?(a) && (PRECEDENCE[a[0]] < PRECEDENCE[operation] || a[0] == '->' && operation == '->')
  right = '(' + right + ')' if binary?(b) && (PRECEDENCE[b[0]] < PRECEDENCE[operation] || b[0] == operation && operation != '->')
  left + ' ' + operation + ' ' + right
end

def variables(node)
  return [node[1]] if node[0] == :variable
  return [] if node[0] == :constant
  return variables(node[1]) if node[0] == :not
  (variables(node[1]) + variables(node[2])).uniq.sort
end

def measures(node)
  return [1, 1] if %i[variable constant].include?(node[0])
  a = measures(node[1])
  return [a[0] + 1, a[1] + 1] if node[0] == :not
  b = measures(node[2])
  [a[0] + b[0] + 1, [a[1], b[1]].max + 1]
end

class FormulaParser
  def initialize(text, start, definitions)
    @definitions = definitions
    @tokens = []
    i = 0
    while i < text.length
      c = text[i]
      if c == ' '
        i += 1
        next
      end
      from = i
      if text[i, 3] == '<->'
        i += 3
      elsif text[i, 2] == '->'
        i += 2
      elsif c.match?(/[a-z]/)
        i += 1
        i += 1 while i < text.length && text[i].match?(/[a-z0-9]/)
      elsif 'ABCDEFGHIJKLMNOPQRSTUVWXYZ01~&^|()'.include?(c)
        i += 1
      else
        raise LogicError, "invalid character '#{c}' at #{start + i}"
      end
      @tokens << [text[from...i], start + from]
    end
    @tokens << ['', start + text.length]
    @position = 0
  end

  def peek = @tokens[@position][0]
  def advance
    text = peek
    @position += 1
    text
  end

  def unexpected
    text, position = @tokens[@position]
    raise LogicError, text.empty? ? "unexpected end of formula at #{position}" : "unexpected '#{text}' at #{position}"
  end

  def unary
    if peek == '~'
      advance
      return negate(unary)
    end
    if peek == '('
      advance
      result = expression(0)
      unexpected unless peek == ')'
      advance
      return result
    end
    if peek.match?(/\A[A-Z]\z/)
      return variable(advance)
    end
    return constant(advance.to_i) if %w[0 1].include?(peek)
    if peek.match?(/\A[a-z][a-z0-9]*\z/)
      text, position = @tokens[@position]
      raise LogicError, "undefined name '#{text}' at #{position}" unless @definitions.key?(text)
      advance
      return @definitions[text]
    end
    unexpected
  end

  def expression(level)
    return unary if level == 5
    operation = %w[<-> -> | ^ &][level]
    result = expression(level + 1)
    while peek == operation
      advance
      result = binary(operation, result, expression(operation == '->' ? level : level + 1))
    end
    result
  end

  def parse
    result = expression(0)
    unexpected unless peek.empty?
    result
  end
end

def nnf(node, positive = true, memo = {})
  key = [node.object_id, positive]
  return memo[key] if memo.key?(key)
  result = case node[0]
           when :variable
             positive ? node : negate(node)
           when :constant
             constant(positive ? node[1] : 1 - node[1])
           when :not
             nnf(node[1], !positive, memo)
           when '&', '|'
             operation = positive ? node[0] : node[0] == '&' ? '|' : '&'
             binary(operation, nnf(node[1], positive, memo), nnf(node[2], positive, memo))
           when '->'
             binary(positive ? '|' : '&', nnf(node[1], !positive, memo), nnf(node[2], positive, memo))
           when '<->', '^'
             same = node[0] == '<->' ? positive : !positive
             binary('|', binary('&', nnf(node[1], true, memo), nnf(node[2], same, memo)),
                    binary('&', nnf(node[1], false, memo), nnf(node[2], !same, memo)))
           end
  memo[key] = result
end

def dual(node)
  case node[0]
  when :variable then node
  when :constant then constant(1 - node[1])
  when :not then negate(dual(node[1]))
  when '->' then binary('&', negate(dual(node[1])), dual(node[2]))
  else
    operation = { '&' => '|', '|' => '&', '^' => '<->', '<->' => '^' }[node[0]]
    binary(operation, dual(node[1]), dual(node[2]))
  end
end

def reduce_negation(node)
  return constant(1 - node[1]) if node[0] == :constant
  node[0] == :not ? node[1] : negate(node)
end

def simplify_binary(operation, a, b)
  zero = constant(0)
  one = constant(1)
  equal = a == b
  complementary = a == negate(b) || b == negate(a)
  case operation
  when '&'
    return zero if a == zero || b == zero
    return b if a == one
    return a if b == one || equal
    return zero if complementary
  when '|'
    return one if a == one || b == one
    return b if a == zero
    return a if b == zero || equal
    return one if complementary
  when '^'
    return b if a == zero
    return a if b == zero
    return reduce_negation(b) if a == one
    return reduce_negation(a) if b == one
    return zero if equal
    return one if complementary
  when '->'
    return one if a == zero || b == one
    return b if a == one
    return reduce_negation(a) if b == zero
    return one if equal
    return b if complementary
  when '<->'
    return b if a == one
    return a if b == one
    return reduce_negation(b) if a == zero
    return reduce_negation(a) if b == zero
    return one if equal
    return zero if complementary
  end
  binary(operation, a, b)
end

def simplify(node, assignments = {})
  return assignments.key?(node[1]) ? constant(assignments[node[1]]) : node if node[0] == :variable
  return node if node[0] == :constant
  return reduce_negation(simplify(node[1], assignments)) if node[0] == :not
  simplify_binary(node[0], simplify(node[1], assignments), simplify(node[2], assignments))
end

def evaluate(node, assignments)
  return assignments[node[1]] if node[0] == :variable
  return node[1] if node[0] == :constant
  return 1 - evaluate(node[1], assignments) if node[0] == :not
  a = evaluate(node[1], assignments)
  b = evaluate(node[2], assignments)
  case node[0]
  when '&' then a & b
  when '|' then a | b
  when '^' then a ^ b
  when '->' then a == 1 && b == 0 ? 0 : 1
  when '<->' then a == b ? 1 : 0
  end
end

def pattern(row, size)
  size == 0 ? '' : row.to_s(2).rjust(size, '0')
end

def pattern_key(text) = text.tr('10-', '012')
def literal_count(text) = text.count('10')
def complement_pattern(text) = text.tr('01', '10')
def contains?(text, row) = text.each_char.with_index.all? { |c, i| c == '-' || c == row[i] }

def pattern_part(text, names, product = true)
  literals = text.each_char.with_index.filter_map { |c, i| c == '-' ? nil : (c == '1' ? names[i] : '~' + names[i]) }
  literals.empty? ? (product ? '1' : '0') : literals.join(product ? ' & ' : ' | ')
end

def cover_text(patterns, names, product = true)
  return product ? '0' : '1' if patterns.empty?
  patterns.map do |text|
    part = pattern_part(text, names, product)
    !product && patterns.length >= 2 && literal_count(text) >= 2 ? '(' + part + ')' : part
  end.join(product ? ' | ' : ' & ')
end

def coefficients(values, size)
  result = values.dup
  size.times do |i|
    bit = 1 << i
    result.each_index { |row| result[row] ^= result[row ^ bit] if (row & bit) != 0 }
  end
  result
end

def minimize(on, dc, names, pos = false)
  rows = on.to_h { |row| [row, pattern(row, names.length)] }
  stage = (on + dc).uniq.map { |row| pattern(row, names.length) }.to_set
  primes = Set.new
  lines = []
  number = 0
  loop do
    used = Set.new
    next_stage = Set.new
    stage.each do |text|
      text.length.times do |i|
        next unless text[i] == '0'
        partner = text.dup
        partner[i] = '1'
        next unless stage.include?(partner)
        combined = text.dup
        combined[i] = '-'
        used << text << partner
        next_stage << combined
      end
    end
    fresh_primes = stage - used
    primes.merge(fresh_primes)
    lines << "stage #{number}: implicants #{stage.length} primes #{fresh_primes.length}" unless pos
    break if next_stage.empty?
    stage = next_stage
    number += 1
  end
  targets = primes.select { |text| rows.values.any? { |row| contains?(text, row) } }.sort_by { |text| pattern_key(text) }
  coverage = targets.map { |text| on.select { |row| contains?(text, rows[row]) }.to_set }
  essential = Set.new
  on.each do |row|
    candidates = coverage.each_index.select { |i| coverage[i].include?(row) }
    essential << candidates[0] if candidates.length == 1
  end
  optional = targets.each_index.reject { |i| essential.include?(i) }
  best = nil
  best_key = nil
  (1 << optional.length).times do |mask|
    chosen = essential.to_a + optional.each_with_index.filter_map { |index, i| index if mask[i] == 1 }
    covered = chosen.reduce(Set.new) { |set, index| set | coverage[index] }
    next unless on.all? { |row| covered.include?(row) }
    texts = chosen.map { |i| pos ? complement_pattern(targets[i]) : targets[i] }.sort_by { |text| pattern_key(text) }
    key = [texts.length, texts.sum { |text| literal_count(text) }, texts.map { |text| pattern_key(text) }]
    if best_key.nil? || (key <=> best_key) < 0
      best_key = key
      best = texts
    end
  end
  if pos
    ["minimal: #{cover_text(best, names, false)}", "clauses #{best.length} literals #{best_key[1]}"]
  else
    terms = targets.map { |text| pattern_part(text, names) }
    essentials = essential.to_a.sort.map { |i| pattern_part(targets[i], names) }
    lines + ["primes: #{terms.empty? ? 'none' : terms.join(', ')}",
             "essential: #{essentials.empty? ? 'none' : essentials.join(', ')}",
             "minimal: #{cover_text(best, names)}", "terms #{best.length} literals #{best_key[1]}"]
  end
end

def merge_clause(a, b)
  result = ''
  a.length.times do |i|
    return nil if a[i] != '-' && b[i] != '-' && a[i] != b[i]
    result << (a[i] == '-' ? b[i] : a[i])
  end
  result
end

def tidy(clauses)
  unique = clauses.uniq
  unique.reject do |clause|
    unique.any? { |other| clause != other && other.each_char.with_index.all? { |c, i| c == '-' || c == clause[i] } }
  end.sort_by { |text| pattern_key(text) }
end

def clauses(node, names, memo = {})
  key = node.object_id
  return memo[key] if memo.key?(key)
  result = case node[0]
           when :variable, :not
             name = node[0] == :variable ? node[1] : node[1][1]
             text = '-' * names.length
             text[names.index(name)] = node[0] == :variable ? '1' : '0'
             [text]
           when :constant
             node[1] == 1 ? [] : ['-' * names.length]
           when '&'
             tidy(clauses(node[1], names, memo) + clauses(node[2], names, memo))
           when '|'
             left = clauses(node[1], names, memo)
             right = clauses(node[2], names, memo)
             tidy(left.flat_map { |a| right.filter_map { |b| merge_clause(a, b) } })
           end
  memo[key] = result
end

def assignment_text(names, row)
  values = pattern(row, names.length)
  '{' + names.each_index.map { |i| names[i] + '=' + values[i] }.join(' ') + '}'
end

class Workbench
  COMMANDS = %w[DEF DEFSUM DEL LIST PRINT TABLE MINTERMS MAXTERMS DNF CNF NNF DUAL ANF SIMPLIFY RESTRICT COFACTOR MINIMIZE MINDC MINPOS KMAP SAT TAUT COUNT EQUIV IMPLIES PROPS BDD CLAUSES DP].freeze
  SPLIT = %w[RESTRICT COFACTOR MINDC EQUIV IMPLIES].freeze
  TABLE = %w[TABLE MINTERMS MAXTERMS DNF CNF ANF SAT TAUT COUNT EQUIV IMPLIES PROPS KMAP BDD MINIMIZE MINDC MINPOS].freeze

  def initialize
    @definitions = {}
  end

  def valid_name?(name) = name.match?(/\A[a-z][a-z0-9]{0,7}\z/)
  def parse(text, start) = FormulaParser.new(text, start, @definitions).parse

  def define(name, formula)
    line = "#{@definitions.key?(name) ? 'redefined' : 'defined'} #{name} = #{notation(formula)}"
    @definitions[name] = formula
    [line]
  end

  def bdd(values, names)
    nodes = []
    unique = {}
    build = lambda do |i, table|
      return table[0] if i == names.length
      half = table.length / 2
      low = build.call(i + 1, table.take(half))
      high = build.call(i + 1, table.drop(half))
      return low if low == high
      key = [i, low, high]
      unless unique.key?(key)
        unique[key] = nodes.length + 2
        nodes << key
      end
      unique[key]
    end
    root = build.call(0, values)
    counts = { 0 => 0, 1 => 1 }
    paths = lambda do |id|
      counts[id] ||= paths.call(nodes[id - 2][1]) + paths.call(nodes[id - 2][2])
    end
    ["nodes: #{nodes.length}"] + nodes.each_with_index.map { |(i, low, high), j| "#{j + 2} = ite(#{names[i]}, #{high}, #{low})" } + ["root: #{root}", "paths: #{paths.call(root)}"]
  end

  def command(line)
    separator = line.index(' ')
    command = separator ? line[0...separator] : line
    argument = separator ? line[(separator + 1)..] : ''
    raise LogicError, "unknown command #{command}" unless COMMANDS.include?(command)
    raise LogicError, 'unexpected argument' if command == 'LIST' && separator
    raise LogicError, 'missing argument' if command != 'LIST' && separator.nil?
    if command == 'LIST'
      return ["names: #{@definitions.length}"] + @definitions.keys.sort.map { |name| name + ' = ' + notation(@definitions[name]) }
    end
    if command == 'DEF'
      split = argument.index(' ')
      raise LogicError, 'missing argument' unless split
      name = argument[0...split]
      raise LogicError, "invalid name '#{name}'" unless valid_name?(name)
      return define(name, parse(argument[(split + 1)..], name.length + 6))
    end
    if command == 'DEL'
      raise LogicError, "invalid name '#{argument}'" unless valid_name?(argument)
      raise LogicError, "undefined name '#{argument}'" unless @definitions.key?(argument)
      @definitions.delete(argument)
      return ["deleted #{argument}"]
    end
    if command == 'DEFSUM'
      split = argument.index(';')
      raise LogicError, "missing ';'" unless split
      words = argument[0...split].split(' ')
      raise LogicError, 'missing argument' if words.empty?
      name, *names = words
      raise LogicError, "invalid name '#{name}'" unless valid_name?(name)
      raise LogicError, 'bad variable list' if names.empty? || names.any? { |item| !item.match?(/\A[A-Z]\z/) } || names.each_cons(2).any? { |a, b| a >= b }
      raise LogicError, "too many variables: #{names.length}" if names.length >= 9
      previous = -1
      rows = argument[(split + 1)..].split(' ').map do |word|
        unless word.match?(/\A(?:0|[1-9][0-9]*)\z/) && word.to_i < (1 << names.length) && word.to_i > previous
          raise LogicError, "bad minterm '#{word}'"
        end
        previous = word.to_i
      end
      terms = rows.map do |row|
        pattern(row, names.length).each_char.with_index.map { |c, i| c == '1' ? variable(names[i]) : negate(variable(names[i])) }.reduce { |a, b| binary('&', a, b) }
      end
      return define(name, terms.empty? ? constant(0) : terms.reduce { |a, b| binary('|', a, b) })
    end
    second = nil
    second_start = nil
    front = argument
    if SPLIT.include?(command)
      split = argument.index(';')
      raise LogicError, "missing ';'" unless split
      front = argument[0...split]
      second = argument[(split + 1)..]
      second_start = command.length + split + 3
    end
    formula = parse(front, command.length + 2)
    if command == 'RESTRICT'
      words = second.split(' ')
      raise LogicError, 'missing assignment' if words.empty?
      assignments = {}
      words.each do |word|
        raise LogicError, "bad assignment '#{word}'" unless word.match?(/\A[A-Z]=[01]\z/)
        raise LogicError, "duplicate variable #{word[0]}" if assignments.key?(word[0])
        assignments[word[0]] = word[2].to_i
      end
      return ['restricted: ' + notation(simplify(formula, assignments))]
    end
    if command == 'COFACTOR'
      words = second.split(' ')
      raise LogicError, 'bad variable' unless words.length == 1 && words[0].match?(/\A[A-Z]\z/)
      name = words[0]
      high = simplify(formula, name => 1)
      low = simplify(formula, name => 0)
      return ["cofactor #{name}=1: #{notation(high)}", "cofactor #{name}=0: #{notation(low)}", 'difference: ' + notation(simplify_binary('^', high, low))]
    end
    other = second ? parse(second, second_start) : nil
    names = (variables(formula) + (other ? variables(other) : [])).uniq.sort
    raise LogicError, "too many variables: #{names.length}" if TABLE.include?(command) && names.length >= 9
    case command
    when 'PRINT'
      size, depth = measures(formula)
      return ['formula: ' + notation(formula), 'variables: ' + (names.empty? ? 'none' : names.join(' ')), "size #{size} depth #{depth}"]
    when 'NNF' then return ['nnf: ' + notation(nnf(formula))]
    when 'DUAL' then return ['dual: ' + notation(dual(formula))]
    when 'SIMPLIFY' then return ['simplified: ' + notation(simplify(formula))]
    when 'CLAUSES', 'DP'
      set = clauses(nnf(formula), names)
      return ['clauses: ' + cover_text(set, names, false)] if command == 'CLAUSES'
      lines = ["start: clauses #{set.length}"]
      empty = '-' * names.length
      names.each_with_index do |name, i|
        break if set.empty? || set.include?(empty)
        positive = set.select { |text| text[i] == '1' }
        negative = set.select { |text| text[i] == '0' }
        resolvents = positive.flat_map do |a|
          negative.filter_map do |b|
            x, y = a.dup, b.dup
            x[i] = y[i] = '-'
            merge_clause(x, y)
          end
        end.uniq
        set = tidy(set.select { |text| text[i] == '-' } + resolvents)
        lines << "eliminate #{name}: resolvents #{resolvents.length} clauses #{set.length}"
      end
      return lines + [set.include?(empty) ? 'result: unsatisfiable' : 'result: satisfiable']
    end
    values = Array.new(1 << names.length) do |row|
      assignments = names.each_with_index.to_h { |name, i| [name, row[names.length - 1 - i]] }
      evaluate(formula, assignments)
    end
    other_values = other ? Array.new(values.length) { |row| evaluate(other, names.each_with_index.to_h { |name, i| [name, row[names.length - 1 - i]] }) } : nil
    on = values.each_index.select { |row| values[row] == 1 }
    off = values.each_index.select { |row| values[row] == 0 }
    case command
    when 'TABLE'
      [([*names, '|', 'F']).join(' ')] + values.each_index.map { |row| ([*pattern(row, names.length).chars, '|', values[row]]).join(' ') }
    when 'MINTERMS', 'MAXTERMS'
      rows = command == 'MINTERMS' ? on : off
      [command.downcase + ': ' + (rows.empty? ? 'none' : rows.join(' '))]
    when 'DNF', 'CNF'
      texts = (command == 'DNF' ? on : off).map { |row| pattern(row, names.length) }
      texts.map! { |text| complement_pattern(text) } if command == 'CNF'
      [command.downcase + ': ' + cover_text(texts, names, command == 'DNF')]
    when 'ANF'
      coeff = coefficients(values, names.length)
      texts = coeff.each_index.select { |row| coeff[row] == 1 }.map { |row| pattern(row, names.length).tr('0', '-') }.sort_by { |text| [literal_count(text), pattern_key(text)] }
      ['anf: ' + (texts.empty? ? '0' : texts.map { |text| pattern_part(text, names) }.join(' ^ '))]
    when 'SAT'
      [on.empty? ? 'unsatisfiable' : 'satisfiable: ' + assignment_text(names, on[0])]
    when 'TAUT'
      [off.empty? ? 'tautology' : 'not a tautology: ' + assignment_text(names, off[0])]
    when 'COUNT'
      ["models: #{on.length} of #{values.length}"]
    when 'EQUIV'
      row = values.each_index.find { |i| values[i] != other_values[i] }
      [row ? "not equivalent: #{assignment_text(names, row)} f=#{values[row]} g=#{other_values[row]}" : 'equivalent']
    when 'IMPLIES'
      row = values.each_index.find { |i| values[i] == 1 && other_values[i] == 0 }
      [row ? 'does not imply: ' + assignment_text(names, row) : 'implies']
    when 'PROPS'
      depends = names.each_index.select do |i|
        bit = 1 << (names.length - 1 - i)
        values.each_index.any? { |row| values[row] != values[row ^ bit] }
      end.map { |i| names[i] }
      monotone = values.each_index.all? do |row|
        names.each_index.all? do |i|
          bit = 1 << i
          (row & bit) != 0 || values[row] <= values[row | bit]
        end
      end
      linear = coefficients(values, names.length).each_with_index.all? { |value, row| value == 0 || row.to_s(2).count('1') <= 1 }
      weights = {}
      symmetric = values.each_index.all? do |row|
        weight = row.to_s(2).count('1')
        previous = weights[weight]
        weights[weight] = values[row]
        previous.nil? || previous == values[row]
      end
      properties = [['zero-preserving', values[0] == 0], ['one-preserving', values[-1] == 1], ['self-dual', values.each_index.all? { |row| values[row] != values[-1 - row] }], ['monotone', monotone], ['linear', linear], ['symmetric', symmetric]]
      ['depends: ' + (depends.empty? ? 'none' : depends.join(' '))] + properties.map { |label, value| label + ': ' + (value ? 'yes' : 'no') }
    when 'KMAP'
      raise LogicError, 'kmap needs 2 to 4 variables' unless (2..4).cover?(names.length)
      p = names.length / 2
      q = names.length - p
      rows = Array.new(1 << p) { |i| pattern(i ^ (i / 2), p) }
      columns = Array.new(1 << q) { |i| pattern(i ^ (i / 2), q) }
      [names.take(p).join + '\\' + names.drop(p).join + ' ' + columns.join(' ')] + rows.map { |row| row.ljust(names.length + 1) + columns.map { |column| ' ' * q + values[(row + column).to_i(2)].to_s }.join }
    when 'BDD' then bdd(values, names)
    when 'MINIMIZE' then minimize(on, [], names)
    when 'MINDC'
      dc = other_values.each_index.select { |row| other_values[row] == 1 }
      minimize(on - dc, dc, names)
    when 'MINPOS' then minimize(off, [], names, true)
    end
  end

  def run
    count = STDIN.gets.to_i
    count.times do
      line = STDIN.gets.delete_suffix("\n")
      begin
        command(line).each { |text| puts text }
      rescue LogicError => error
        puts 'error: ' + error.message
      end
    end
  end
end

Workbench.new.run
