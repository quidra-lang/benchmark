require 'set'

class DatalogError < StandardError
end

RESERVED = %w[not mod count sum min max retract dump why forget listing strata stats check predicates undo halt].freeze
Atom = Struct.new(:name, :terms)

def value_text(value)
  return value.to_s if value.is_a?(Integer)
  value.match?(/\A[a-z][A-Za-z0-9_]*\z/) && !RESERVED.include?(value) ? value : '"' + value + '"'
end

def value_key(value)
  [value.is_a?(Integer) ? 0 : 1, value]
end

def tuple_key(tuple)
  tuple.map { |value| value_key(value) }
end

def term_text(term, environment = nil)
  case term[0]
  when :constant then value_text(term[1])
  when :variable then environment ? value_text(environment.fetch(term[1])) : term[1]
  when :anonymous then '_'
  end
end

def atom_text(atom, environment = nil)
  atom.name + (atom.terms.empty? ? '' : '(' + atom.terms.map { |term| term_text(term, environment) }.join(', ') + ')')
end

def tuple_text(name, tuple)
  atom_text(Atom.new(name, tuple.map { |value| [:constant, value] }))
end

def expression_text(expression, environment = nil)
  case expression[0]
  when :term then term_text(expression[1], environment)
  when :group then '(' + expression_text(expression[1], environment) + ')'
  when :binary then expression_text(expression[2], environment) + ' ' + expression[1] + ' ' + expression_text(expression[3], environment)
  end
end

def literal_text(literal, environment = nil)
  case literal[0]
  when :positive then atom_text(literal[1], environment)
  when :negative then 'not ' + atom_text(literal[1], environment)
  when :comparison then expression_text(literal[2], environment) + ' ' + literal[1] + ' ' + expression_text(literal[3], environment)
  end
end

def expression_terms(expression)
  case expression[0]
  when :term then [expression[1]]
  when :group then expression_terms(expression[1])
  when :binary then expression_terms(expression[2]) + expression_terms(expression[3])
  end
end

def literal_terms(literal)
  literal[0] == :comparison ? expression_terms(literal[2]) + expression_terms(literal[3]) : literal[1].terms
end

def variable_occurrences(head, body)
  ((head ? head.terms : []) + body.flat_map { |literal| literal_terms(literal) }).select { |term| term[0] == :variable }.map { |term| term[1] }
end

class Parser
  COMPARISONS = %w[= != < <= > >=].freeze
  OPERATORS = %w[+ - * / mod].freeze

  def initialize(line)
    @tokens = []
    i = 0
    while i < line.length
      c = line[i]
      if c == ' '
        i += 1
      elsif c == '%'
        break
      elsif c == '"'
        finish = line.index('"', i + 1)
        raise DatalogError, 'unterminated string' unless finish
        @tokens << [:string, line[i..finish], line[(i + 1)...finish]]
        i = finish + 1
      elsif %w[:- ?- != <= >=].include?(line[i, 2])
        @tokens << [line[i, 2], line[i, 2]]
        i += 2
      elsif '(),.:=<>+-*/'.include?(c)
        @tokens << [c, c]
        i += 1
      elsif c.match?(/[A-Za-z0-9_]/)
        start = i
        i += 1
        i += 1 while i < line.length && line[i].match?(/[A-Za-z0-9_]/)
        text = line[start...i]
        if text[0].match?(/[a-z]/)
          @tokens << [RESERVED.include?(text) ? text : :name, text, text]
        elsif text[0].match?(/[A-Z]/)
          @tokens << [:variable, text, text]
        elsif text == '_'
          @tokens << [:anonymous, text]
        elsif text.match?(/\A[0-9]+\z/)
          raise DatalogError, "integer out of range '#{text}'" if text.to_i > 1_000_000_000
          @tokens << [:integer, text, text.to_i]
        else
          raise DatalogError, "bad token '#{text}'"
        end
      else
        raise DatalogError, "bad character '#{c}'"
      end
    end
    @tokens << [:end, '']
    @position = 0
  end

  def peek = @tokens[@position]
  def advance
    result = peek
    @position += 1
    result
  end

  def syntax_error
    raise DatalogError, peek[0] == :end ? 'syntax error at end of line' : "syntax error at '#{peek[1]}'"
  end

  def expect(kind)
    syntax_error unless peek[0] == kind
    advance
  end

  def term
    case peek[0]
    when :name, :string, :integer
      [:constant, advance[2]]
    when :variable
      [:variable, advance[1]]
    when :anonymous
      advance
      [:anonymous]
    when '-'
      advance
      [:constant, -expect(:integer)[2]]
    else
      syntax_error
    end
  end

  def atom
    name = expect(:name)[1]
    terms = []
    if peek[0] == '('
      advance
      terms << term
      while peek[0] == ','
        advance
        terms << term
      end
      expect(')')
    end
    Atom.new(name, terms)
  end

  def factor
    if peek[0] == '('
      advance
      result = [:group, expression]
      expect(')')
      result
    else
      [:term, term]
    end
  end

  def product
    result = factor
    while %w[* / mod].include?(peek[0])
      operation = advance[0]
      result = [:binary, operation, result, factor]
    end
    result
  end

  def expression
    result = product
    while %w[+ -].include?(peek[0])
      operation = advance[0]
      result = [:binary, operation, result, product]
    end
    result
  end

  def literal
    if peek[0] == 'not'
      advance
      [:negative, atom]
    elsif peek[0] == :name && !(COMPARISONS + OPERATORS).include?(@tokens[@position + 1][0])
      [:positive, atom]
    else
      left = expression
      syntax_error unless COMPARISONS.include?(peek[0])
      operation = advance[0]
      [:comparison, operation, left, expression]
    end
  end

  def body
    literals = [literal]
    while peek[0] == ','
      advance
      literals << literal
    end
    literals
  end

  def statement
    return nil if peek[0] == :end
    kind = peek[0]
    if kind == :name
      head = atom
      if peek[0] == ':-'
        advance
        result = { kind: :rule, head: head, body: body }
      else
        result = { kind: :fact, head: head, body: [] }
      end
    elsif kind == ':-'
      advance
      result = { kind: :constraint, head: nil, body: body }
    elsif kind == '?-'
      advance
      aggregate = nil
      variable = nil
      if %w[count sum min max].include?(peek[0])
        aggregate = advance[0]
        unless aggregate == 'count'
          variable = expect(:variable)[1]
          expect(':')
        end
      end
      result = { kind: :query, head: nil, body: body, aggregate: aggregate, variable: variable }
    elsif %w[retract why].include?(kind)
      advance
      result = { kind: kind.to_sym, atom: atom }
    elsif kind == 'dump'
      advance
      result = { kind: :dump, name: expect(:name)[1] }
    elsif kind == 'forget'
      advance
      result = { kind: :forget, number: expect(:integer)[2] }
    elsif kind == 'listing'
      advance
      result = { kind: :listing, name: peek[0] == :name ? advance[1] : nil }
    elsif %w[strata stats check predicates undo halt].include?(kind)
      advance
      result = { kind: kind.to_sym }
    else
      syntax_error
    end
    expect('.')
    expect(:end)
    result
  end
end

class Engine
  def initialize
    @arities = {}
    @facts = {}
    @rules = []
    @history = []
    @next_rule = 1
    @cache = nil
  end

  def atoms(statement)
    [statement[:head]].compact + (statement[:body] || []).filter_map { |literal| literal[1] unless literal[0] == :comparison }
  end

  def predicate_check(list, clause = false)
    prospective = @arities.dup
    list.each do |atom|
      if prospective.key?(atom.name)
        expected = prospective[atom.name]
        raise DatalogError, "arity mismatch for #{atom.name}: expected #{expected}, got #{atom.terms.length}" if expected != atom.terms.length
      elsif clause
        prospective[atom.name] = atom.terms.length
      else
        raise DatalogError, "unknown predicate #{atom.name}"
      end
    end
    prospective
  end

  def safety(statement)
    head = statement[:head]
    body = statement[:body]
    raise DatalogError, 'anonymous variable in head' if head && head.terms.any? { |term| term[0] == :anonymous }
    body.each do |literal|
      if literal[0] == :comparison && literal_terms(literal).any? { |term| term[0] == :anonymous }
        raise DatalogError, 'anonymous variable in comparison'
      end
    end
    bound = body.select { |literal| literal[0] == :positive }.flat_map { |literal| literal[1].terms }.select { |term| term[0] == :variable }.map { |term| term[1] }.to_set
    required = head ? head.terms : statement[:variable] ? [[:variable, statement[:variable]]] : []
    required += body.reject { |literal| literal[0] == :positive }.flat_map { |literal| literal_terms(literal) }
    required.each do |term|
      raise DatalogError, "unsafe variable #{term[1]}" if term[0] == :variable && !bound.include?(term[1])
    end
  end

  def rule_text(rule)
    prefix = rule[:head] ? atom_text(rule[:head]) + ' :- ' : ':- '
    prefix + rule[:body].map { |literal| literal_text(literal) }.join(', ') + '.'
  end

  def strata(arities = @arities, rules = @rules)
    levels = arities.transform_values { 0 }
    arities.length.times do
      changed = false
      rules.each do |rule|
        next unless rule[:head]
        rule[:body].each do |literal|
          next if literal[0] == :comparison
          level = levels[literal[1].name] + (literal[0] == :negative ? 1 : 0)
          if level > levels[rule[:head].name]
            levels[rule[:head].name] = level
            changed = true
          end
        end
      end
      return levels unless changed
    end
    arities.empty? ? levels : nil
  end

  def snapshot(line)
    @history << [@arities.dup, @facts.transform_values(&:dup), @rules.dup, line]
    @cache = nil
  end

  def match(atom, tuple, environment)
    result = environment.dup
    atom.terms.each_with_index do |term, i|
      if term[0] == :constant
        return nil unless term[1] == tuple[i]
      elsif term[0] == :variable
        return nil if result.key?(term[1]) && result[term[1]] != tuple[i]
        result[term[1]] = tuple[i]
      end
    end
    result
  end

  def evaluate(expression, environment)
    case expression[0]
    when :term
      term = expression[1]
      term[0] == :constant ? term[1] : environment.fetch(term[1])
    when :group
      evaluate(expression[1], environment)
    when :binary
      a = evaluate(expression[2], environment)
      b = evaluate(expression[3], environment)
      return nil unless a.is_a?(Integer) && b.is_a?(Integer)
      case expression[1]
      when '+' then a + b
      when '-' then a - b
      when '*' then a * b
      when '/' then b == 0 ? nil : a.div(b)
      when 'mod' then b == 0 ? nil : a.modulo(b)
      end
    end
  end

  def comparison(literal, environment)
    a = evaluate(literal[2], environment)
    b = evaluate(literal[3], environment)
    return false if a.nil? || b.nil?
    return a == b if literal[1] == '='
    return a != b if literal[1] == '!='
    return false unless a.is_a?(Integer) && b.is_a?(Integer)
    case literal[1]
    when '<' then a < b
    when '<=' then a <= b
    when '>' then a > b
    when '>=' then a >= b
    end
  end

  def solutions(body, data, metadata = nil, before = nil)
    positives = body.select { |literal| literal[0] == :positive }
    bound_at = {}
    positives.each_with_index do |literal, i|
      literal[1].terms.each { |term| bound_at[term[1]] ||= i + 1 if term[0] == :variable }
    end
    filters = Array.new(positives.length + 1) { [] }
    body.each do |literal|
      next if literal[0] == :positive
      variables = literal_terms(literal).select { |term| term[0] == :variable }.map { |term| term[1] }
      stage = variables.map { |name| bound_at.fetch(name) }.max || 0
      filters[stage] << literal
    end
    sources = positives.map do |literal|
      atom = literal[1]
      tuples = data.fetch(atom.name)
      tuples = tuples.select { |tuple| metadata[atom.name][tuple][0] < before } if before
      tuples
    end
    variables = variable_occurrences(nil, body).uniq
    results = {}
    visit = lambda do |stage, environment|
      valid = filters[stage].all? do |literal|
        literal[0] == :negative ? data.fetch(literal[1].name).none? { |tuple| match(literal[1], tuple, environment) } : comparison(literal, environment)
      end
      return unless valid
      if stage == positives.length
        results[variables.map { |name| environment.fetch(name) }] = environment
        return
      end
      atom = positives[stage][1]
      seen = Set.new
      sources[stage].each do |tuple|
        matched = match(atom, tuple, environment)
        next unless matched
        key = matched.keys.sort.map { |name| matched[name] }
        next if seen.include?(key)
        seen << key
        visit.call(stage + 1, matched)
      end
    end
    visit.call(0, {})
    results.values.sort_by { |environment| tuple_key(variables.map { |name| environment.fetch(name) }) }
  end

  def head_tuple(atom, environment)
    atom.terms.map { |term| term[0] == :constant ? term[1] : environment.fetch(term[1]) }
  end

  def model
    return @cache if @cache
    levels = strata
    data = @arities.to_h { |name, _| [name, @facts.fetch(name, Set.new).dup] }
    metadata = data.to_h { |name, tuples| [name, tuples.to_h { |tuple| [tuple, [0, nil]] }] }
    rounds = {}
    added = {}
    serial = 0
    (0..(levels.values.max || -1)).each do |level|
      rounds[level] = 0
      added[level] = 0
      loop do
        fresh = {}
        @rules.select { |rule| rule[:head] && levels[rule[:head].name] == level }.each do |rule|
          name = rule[:head].name
          solutions(rule[:body], data).each do |environment|
            tuple = head_tuple(rule[:head], environment)
            next if data[name].include?(tuple)
            fresh[[name, tuple]] ||= rule[:number]
          end
        end
        break if fresh.empty?
        serial += 1
        rounds[level] += 1
        added[level] += fresh.length
        fresh.each do |(name, tuple), rule|
          data[name] << tuple
          metadata[name][tuple] = [serial, rule]
        end
      end
    end
    @cache = [data, metadata, levels, rounds, added]
  end

  def answers(body, data)
    variables = variable_occurrences(nil, body).uniq
    tuples = solutions(body, data).map { |environment| variables.map { |name| environment.fetch(name) } }.uniq.sort_by { |tuple| tuple_key(tuple) }
    [variables, tuples]
  end

  def answer_text(variables, tuple)
    variables.zip(tuple).map { |name, value| name + ' = ' + value_text(value) }.join(', ')
  end

  def proof(name, tuple, data, metadata, depth = 0)
    indent = '  ' * depth
    serial = metadata[name][tuple][0]
    return [indent + tuple_text(name, tuple) + ' [fact]'] if serial == 0
    chosen_rule = nil
    chosen = nil
    @rules.each do |rule|
      next unless rule[:head] && rule[:head].name == name
      variables = variable_occurrences(rule[:head], rule[:body]).uniq
      candidates = solutions(rule[:body], data, metadata, serial).select { |environment| head_tuple(rule[:head], environment) == tuple }
      next if candidates.empty?
      chosen_rule = rule
      chosen = candidates.min_by { |environment| tuple_key(variables.map { |variable| environment.fetch(variable) }) }
      break
    end
    lines = [indent + tuple_text(name, tuple) + " [rule #{chosen_rule[:number]}]"]
    chosen_rule[:body].each do |literal|
      if literal[0] == :positive
        atom = literal[1]
        matched = data[atom.name].select { |item| metadata[atom.name][item][0] < serial && match(atom, item, chosen) }.min_by { |item| tuple_key(item) }
        lines.concat(proof(atom.name, matched, data, metadata, depth + 1))
      else
        lines << indent + '  ' + literal_text(literal, chosen)
      end
    end
    lines
  end

  def execute(statement, line)
    kind = statement[:kind]
    return :halt if kind == :halt
    if %i[fact rule constraint].include?(kind)
      prospective = predicate_check(atoms(statement), true)
      safety(statement)
      if kind == :fact
        atom = statement[:head]
        tuple = head_tuple(atom, {})
        return [] if @facts.fetch(atom.name, Set.new).include?(tuple)
        snapshot(line)
        @arities = prospective
        (@facts[atom.name] ||= Set.new) << tuple
        return []
      end
      notation = rule_text(statement)
      duplicate = @rules.find { |rule| rule[:notation] == notation }
      raise DatalogError, "duplicate of rule #{duplicate[:number]}" if duplicate
      raise DatalogError, "negative cycle through #{statement[:head].name}" if kind == :rule && strata(prospective, @rules + [statement]).nil?
      snapshot(line)
      rule = statement.merge(number: @next_rule, notation: notation)
      @next_rule += 1
      @rules << rule
      @arities = prospective
      occurrences = variable_occurrences(rule[:head], rule[:body])
      return occurrences.uniq.select { |name| occurrences.count(name) == 1 }.map { |name| "WARNING line #{line}: singleton variable #{name}" }
    end
    case kind
    when :query
      predicate_check(atoms(statement))
      safety(statement)
      variables, tuples = answers(statement[:body], model[0])
      aggregate = statement[:aggregate]
      return [tuples.length.to_s] if aggregate == 'count'
      if %w[sum min max].include?(aggregate)
        values = tuples.map { |tuple| tuple[variables.index(statement[:variable])] }
        if aggregate == 'sum'
          raise DatalogError, 'non-integer value in sum' unless values.all? { |value| value.is_a?(Integer) }
          return [values.sum.to_s]
        end
        return ['no answers'] if values.empty?
        selected = aggregate == 'min' ? values.min_by { |value| value_key(value) } : values.max_by { |value| value_key(value) }
        return [value_text(selected)]
      end
      return [tuples.empty? ? 'false.' : 'true.'] if variables.empty?
      tuples.map { |tuple| answer_text(variables, tuple) } + ["#{tuples.length} #{tuples.length == 1 ? 'answer' : 'answers'}"]
    when :retract, :why
      atom = statement[:atom]
      predicate_check([atom])
      if kind == :retract
        removed = @facts.fetch(atom.name, Set.new).select { |tuple| match(atom, tuple, {}) }
        raise DatalogError, 'no matching facts' if removed.empty?
        snapshot(line)
        @facts[atom.name].subtract(removed)
        ["#{removed.length} #{removed.length == 1 ? 'fact' : 'facts'} retracted"]
      else
        raise DatalogError, 'why needs a ground atom' unless atom.terms.all? { |term| term[0] == :constant }
        tuple = head_tuple(atom, {})
        data, metadata, = model
        data[atom.name].include?(tuple) ? proof(atom.name, tuple, data, metadata) : ['false.']
      end
    when :dump
      name = statement[:name]
      raise DatalogError, "unknown predicate #{name}" unless @arities.key?(name)
      tuples = model[0][name].sort_by { |tuple| tuple_key(tuple) }
      tuples.map { |tuple| tuple_text(name, tuple) + '.' } + ["#{tuples.length} #{tuples.length == 1 ? 'tuple' : 'tuples'}"]
    when :forget
      index = @rules.index { |rule| rule[:number] == statement[:number] }
      raise DatalogError, "no rule #{statement[:number]}" unless index
      snapshot(line)
      @rules.delete_at(index)
      []
    when :undo
      raise DatalogError, 'nothing to undo' if @history.empty?
      @arities, @facts, @rules, original = @history.pop
      @cache = nil
      ["undid line #{original}"]
    when :listing
      name = statement[:name]
      raise DatalogError, "unknown predicate #{name}" if name && !@arities.key?(name)
      rules = @rules.select { |rule| !name || rule[:head]&.name == name }
      rules.empty? ? ['no rules'] : rules.map { |rule| "#{rule[:number]}: #{rule[:notation]}" }
    when :strata
      return ['no predicates'] if @arities.empty?
      levels = strata
      dependencies = @arities.to_h { |name, _| [name, []] }
      @rules.each do |rule|
        next unless rule[:head]
        dependencies[rule[:head].name].concat(atoms(rule).drop(1).map(&:name))
      end
      recursive = dependencies.keys.to_h do |name|
        seen = Set.new
        search = lambda do |current|
          dependencies[current].any? { |next_name| next_name == name || (seen.add?(next_name) && search.call(next_name)) }
        end
        [name, search.call(name)]
      end
      (0..levels.values.max).map { |level| "stratum #{level}: #{levels.keys.select { |name| levels[name] == level }.sort.map { |name| name + (recursive[name] ? '*' : '') }.join(', ')}" }
    when :stats
      data, metadata, levels, rounds, added = model
      rules = @rules.select { |rule| rule[:head] }
      lines = ["facts #{@facts.values.sum(&:length)}, rules #{rules.length}, constraints #{@rules.length - rules.length}, tuples #{data.values.sum(&:length)}"]
      (0..(levels.values.max || -1)).each { |level| lines << "stratum #{level}: rounds #{rounds[level]}, new #{added[level]}" }
      rules.each do |rule|
        count = metadata.values.sum { |entries| entries.values.count { |_, number| number == rule[:number] } }
        lines << "rule #{rule[:number]}: new #{count}"
      end
      lines
    when :predicates
      return ['no predicates'] if @arities.empty?
      data = model[0]
      @arities.keys.sort.map do |name|
        count = @rules.count { |rule| rule[:head]&.name == name }
        "#{name}/#{@arities[name]}: facts #{@facts.fetch(name, Set.new).length}, rules #{count}, tuples #{data[name].length}"
      end
    when :check
      constraints = @rules.reject { |rule| rule[:head] }
      return ['no constraints'] if constraints.empty?
      data = model[0]
      constraints.flat_map do |rule|
        variables, tuples = answers(rule[:body], data)
        if tuples.empty?
          ["constraint #{rule[:number]}: ok"]
        else
          ["constraint #{rule[:number]}: #{tuples.length} #{tuples.length == 1 ? 'violation' : 'violations'}"] + (variables.empty? ? [] : tuples.map { |tuple| '  ' + answer_text(variables, tuple) })
        end
      end
    end
  end

  def run
    STDIN.each_line.with_index(1) do |input, line|
      begin
        statement = Parser.new(input.delete_suffix("\n")).statement
        next unless statement
        output = execute(statement, line)
        break if output == :halt
        output.each { |text| puts text }
      rescue DatalogError => error
        puts "ERROR line #{line}: #{error.message}"
      end
    end
  end
end

Engine.new.run
