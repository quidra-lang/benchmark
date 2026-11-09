require 'set'

class AutomatonError < StandardError
end

class Automaton
  attr_reader :kind, :states, :alphabet, :start, :accepting, :edges

  def initialize(kind, states, alphabet, start, accepting, triples)
    @kind = kind
    @states = states
    @alphabet = alphabet.sort
    @start = start
    @accepting = accepting.to_set
    @edges = Array.new(states.length) { {} }
    triples.each do |p, c, q|
      (@edges[p][c] ||= []) << q
    end
    @edges.each do |row|
      row.each_value(&:sort!)
      row.each_value(&:uniq!)
    end
  end

  def triples
    result = []
    @edges.each_with_index do |row, p|
      (@alphabet + ['e']).each do |c|
        (row[c] || []).each { |q| result << [p, c, q] }
      end
    end
    result
  end

  def summary(name)
    "#{@kind} #{name}: alphabet=#{@alphabet.join} states=#{@states.length} accepting=#{@accepting.length} transitions=#{triples.length}"
  end

  def set_text(values)
    '{' + values.sort.map { |i| @states[i] }.join(',') + '}'
  end

  def list_text(values)
    values.empty? ? 'none' : values.sort.map { |i| @states[i] }.join(',')
  end

  def closure(values)
    seen = values.to_set
    queue = seen.to_a
    i = 0
    while i < queue.length
      (@edges[queue[i]]['e'] || []).each do |q|
        next if seen.include?(q)
        seen.add(q)
        queue << q
      end
      i += 1
    end
    seen.to_a.sort
  end

  def move(values, c)
    closure(values.flat_map { |p| @edges[p][c] || [] }.uniq)
  end

  def accepts_set?(values)
    values.any? { |p| @accepting.include?(p) }
  end

  def graph_reachable(seeds, reverse = false)
    graph = Array.new(@states.length) { [] }
    triples.each do |p, _, q|
      reverse ? graph[q] << p : graph[p] << q
    end
    seen = seeds.to_set
    queue = seen.to_a
    i = 0
    while i < queue.length
      graph[queue[i]].each do |q|
        next if seen.include?(q)
        seen.add(q)
        queue << q
      end
      i += 1
    end
    seen.to_a.sort
  end

  def determinize
    subsets = [closure([@start])]
    indices = { subsets[0] => 0 }
    transitions = []
    accepting = []
    i = 0
    while i < subsets.length
      accepting << i if accepts_set?(subsets[i])
      @alphabet.each do |c|
        target = move(subsets[i], c)
        unless indices.key?(target)
          indices[target] = subsets.length
          subsets << target
        end
        transitions << [i, c, indices[target]]
      end
      i += 1
    end
    result = Automaton.new('DFA', Array.new(subsets.length) { |j| "D#{j}" }, @alphabet, 0, accepting, transitions)
    [result, subsets]
  end

  def minimize
    reachable = graph_reachable([@start])
    blocks = [reachable.select { |p| @accepting.include?(p) }, reachable.reject { |p| @accepting.include?(p) }]
    blocks.reject!(&:empty?)
    blocks.sort_by!(&:first)
    rounds = [blocks]
    loop do
      membership = {}
      blocks.each_with_index { |block, i| block.each { |p| membership[p] = i } }
      groups = {}
      reachable.each do |p|
        signature = [membership[p]] + @alphabet.map { |c| membership[@edges[p][c][0]] }
        (groups[signature] ||= []) << p
      end
      refined = groups.values.sort_by(&:first)
      break if refined.length == blocks.length
      blocks = refined
      rounds << blocks
    end
    membership = {}
    blocks.each_with_index { |block, i| block.each { |p| membership[p] = i } }
    order = [membership[@start]]
    named = { order[0] => 0 }
    transitions = []
    accepting = []
    i = 0
    while i < order.length
      representative = blocks[order[i]][0]
      accepting << i if @accepting.include?(representative)
      @alphabet.each do |c|
        target = membership[@edges[representative][c][0]]
        unless named.key?(target)
          named[target] = order.length
          order << target
        end
        transitions << [i, c, named[target]]
      end
      i += 1
    end
    result = Automaton.new('DFA', Array.new(order.length) { |j| "M#{j}" }, @alphabet, 0, accepting, transitions)
    unreachable = (0...@states.length).to_a - reachable
    [result, unreachable, rounds, order.map { |j| blocks[j] }]
  end

  def shortest_word
    queue = [[@start, '']]
    seen = Set[@start]
    i = 0
    while i < queue.length
      p, word = queue[i]
      return word if @accepting.include?(p)
      @alphabet.each do |c|
        q = @edges[p][c][0]
        next if seen.include?(q)
        seen.add(q)
        queue << [q, word + c]
      end
      i += 1
    end
    nil
  end

  def finite_size(count = true)
    live = graph_reachable(@accepting.to_a, true).to_set
    color = Array.new(@states.length, 0)
    counts = Array.new(@states.length, 0)
    visit = lambda do |p|
      return 0 unless live.include?(p)
      return nil if color[p] == 1
      return counts[p] if color[p] == 2
      color[p] = 1
      total = @accepting.include?(p) ? 1 : 0
      @alphabet.each do |c|
        value = visit.call(@edges[p][c][0])
        return nil if value.nil?
        total = count ? total + value : (total.positive? || value.positive? ? 1 : 0)
      end
      color[p] = 2
      counts[p] = total
    end
    visit.call(@start)
  end
end

class RegexParser
  def initialize(text)
    @text = text
    @position = 0
  end

  def peek
    @text[@position]
  end

  def fail_parse
    raise AutomatonError, "syntax error at #{@position + 1}"
  end

  def parse
    result = alternation
    fail_parse unless peek.nil?
    result
  end

  def alternation
    parts = [concatenation]
    while peek == '|'
      @position += 1
      parts << concatenation
    end
    parts.length == 1 ? parts[0] : [:alternation, parts]
  end

  def concatenation
    parts = [factor]
    while peek && peek.match?(/[a-z0-9(]/)
      parts << factor
    end
    parts.length == 1 ? parts[0] : [:concatenation, parts]
  end

  def factor
    result = atom
    while ['*', '+', '?'].include?(peek)
      operator = peek
      @position += 1
      result = [operator, result]
    end
    result
  end

  def atom
    c = peek
    if c && c.match?(/[a-z0-9]/)
      @position += 1
      [:symbol, c]
    elsif c == '('
      @position += 1
      result = alternation
      fail_parse unless peek == ')'
      @position += 1
      result
    else
      fail_parse
    end
  end
end

class Toolkit
  ROLES = {
    'ACCEPT' => [:reference, :other], 'CLOSURE' => [:reference, :other],
    'ENUM' => [:reference, :other], 'COUNT' => [:reference, :other],
    'TODFA' => [:reference, :new], 'EPSFREE' => [:reference, :new],
    'REVERSE' => [:reference, :new], 'STAR' => [:reference, :new],
    'MINIMIZE' => [:dfa, :new], 'COMPLEMENT' => [:dfa, :new],
    'EQUIV' => [:reference, :reference],
    'UNION' => [:dfa, :dfa, :new], 'INTERSECT' => [:dfa, :dfa, :new],
    'DIFF' => [:dfa, :dfa, :new], 'CONCAT' => [:reference, :reference, :new],
    'EMPTY' => [:reference], 'FINITE' => [:reference], 'INFO' => [:reference],
    'TABLE' => [:reference], 'SHOW' => [:reference], 'DELETE' => [:reference],
    'SYNC' => [:dfa], 'LIST' => []
  }.freeze

  def initialize
    @table = {}
  end

  def register(name, automaton, details = [])
    @table[name] = automaton
    [automaton.summary(name)] + details
  end

  def define(kind, args)
    raise AutomatonError, 'wrong number of arguments' if args.length < 5
    name, state_word, alphabet_word, start, accept_word, *transition_words = args
    raise AutomatonError, "#{name} already exists" if @table.key?(name)
    states = state_word.split(',')
    indices = {}
    states.each_with_index do |state, i|
      raise AutomatonError, "duplicate state #{state}" if indices.key?(state)
      indices[state] = i
    end
    raise AutomatonError, "unknown state #{start}" unless indices.key?(start)
    accepting = []
    unless accept_word == '-'
      accept_word.split(',').each do |state|
        raise AutomatonError, "unknown state #{state}" unless indices.key?(state)
        raise AutomatonError, "duplicate state #{state}" if accepting.include?(indices[state])
        accepting << indices[state]
      end
    end
    alphabet = alphabet_word.chars.sort
    triples = []
    seen = Set.new
    pairs = Set.new
    transition_words.each do |word|
      p, c, q = word.split(':')
      raise AutomatonError, "unknown state #{p}" unless indices.key?(p)
      raise AutomatonError, 'epsilon transition in DFA' if c == 'e' && kind == 'DFA'
      raise AutomatonError, "unknown symbol #{c}" unless c == 'e' || alphabet.include?(c)
      raise AutomatonError, "unknown state #{q}" unless indices.key?(q)
      raise AutomatonError, "duplicate transition #{word}" if seen.include?(word)
      pair = [p, c]
      raise AutomatonError, "conflicting transition #{word}" if kind == 'DFA' && pairs.include?(pair)
      seen.add(word)
      pairs.add(pair)
      triples << [indices[p], c, indices[q]]
    end
    if kind == 'DFA'
      states.each do |p|
        alphabet.each do |c|
          raise AutomatonError, "missing transition #{p}:#{c}" unless pairs.include?([p, c])
        end
      end
    end
    register(name, Automaton.new(kind, states, alphabet, indices[start], accepting, triples))
  end

  def regex(args)
    raise AutomatonError, 'wrong number of arguments' unless args.length == 3
    name, alphabet, text = args
    raise AutomatonError, "#{name} already exists" if @table.key?(name)
    text.each_char do |c|
      if c.match?(/[a-z0-9]/) && c != 'e' && !alphabet.include?(c)
        raise AutomatonError, "unknown symbol #{c}"
      end
    end
    tree = RegexParser.new(text).parse
    states = []
    triples = []
    create = lambda do
      index = states.length
      states << "N#{index}"
      index
    end
    build = lambda do |node|
      case node[0]
      when :symbol
        s = create.call
        f = create.call
        triples << [s, node[1], f]
        [s, f]
      when :concatenation
        parts = node[1].map { |part| build.call(part) }
        parts.each_cons(2) { |a, b| triples << [a[1], 'e', b[0]] }
        [parts[0][0], parts[-1][1]]
      when :alternation
        s = create.call
        parts = node[1].map { |part| build.call(part) }
        f = create.call
        parts.each do |a, b|
          triples << [s, 'e', a]
          triples << [b, 'e', f]
        end
        [s, f]
      else
        s = create.call
        a, b = build.call(node[1])
        f = create.call
        triples << [s, 'e', a]
        triples << [b, 'e', f]
        triples << [b, 'e', a] unless node[0] == '?'
        triples << [s, 'e', f] unless node[0] == '+'
        [s, f]
      end
    end
    start, finish = build.call(tree)
    register(name, Automaton.new('NFA', states, alphabet.chars, start, [finish], triples))
  end

  def product(x, z, operation)
    pairs = [[x.start, z.start]]
    indices = { pairs[0] => 0 }
    triples = []
    accepting = []
    i = 0
    while i < pairs.length
      p, q = pairs[i]
      a = x.accepting.include?(p)
      b = z.accepting.include?(q)
      good = operation == 'UNION' ? a || b : operation == 'INTERSECT' ? a && b : a && !b
      accepting << i if good
      x.alphabet.each do |c|
        target = [x.edges[p][c][0], z.edges[q][c][0]]
        unless indices.key?(target)
          indices[target] = pairs.length
          pairs << target
        end
        triples << [i, c, indices[target]]
      end
      i += 1
    end
    result = Automaton.new('DFA', Array.new(pairs.length) { |j| "P#{j}" }, x.alphabet, 0, accepting, triples)
    [result, pairs]
  end

  def equivalent(x, z, names)
    a = x.determinize[0]
    b = z.determinize[0]
    queue = [[a.start, b.start, '']]
    seen = Set[[a.start, b.start]]
    i = 0
    while i < queue.length
      p, q, word = queue[i]
      if a.accepting.include?(p) != b.accepting.include?(q)
        owner = a.accepting.include?(p) ? names[0] : names[1]
        return ["NOT EQUIVALENT: #{word.empty? ? 'e' : word} is accepted only by #{owner}"]
      end
      a.alphabet.each do |c|
        target = [a.edges[p][c][0], b.edges[q][c][0]]
        next if seen.include?(target)
        seen.add(target)
        queue << [target[0], target[1], word + c]
      end
      i += 1
    end
    ['EQUIVALENT']
  end

  def synchronization(x)
    initial = (0...x.states.length).to_a
    queue = [[initial, '']]
    seen = Set[initial]
    i = 0
    while i < queue.length
      subset, word = queue[i]
      return ["SYNCHRONIZING #{word.empty? ? 'e' : word} -> #{x.states[subset[0]]}"] if subset.length == 1
      x.alphabet.each do |c|
        target = subset.map { |p| x.edges[p][c][0] }.uniq.sort
        next if seen.include?(target)
        seen.add(target)
        queue << [target, word + c]
      end
      i += 1
    end
    ['NOT SYNCHRONIZING']
  end

  def execute(command, args)
    return define(command, args) if ['DFA', 'NFA'].include?(command)
    return regex(args) if command == 'REGEX'
    roles = ROLES[command]
    raise AutomatonError, "unknown command #{command}" unless roles
    raise AutomatonError, 'wrong number of arguments' unless roles.length == args.length
    roles.each_with_index do |role, i|
      if [:reference, :dfa].include?(role) && !@table.key?(args[i])
        raise AutomatonError, "unknown automaton #{args[i]}"
      end
    end
    roles.each_with_index do |role, i|
      raise AutomatonError, "#{args[i]} already exists" if role == :new && @table.key?(args[i])
    end
    roles.each_with_index do |role, i|
      raise AutomatonError, "#{args[i]} is not a DFA" if role == :dfa && @table[args[i]].kind != 'DFA'
    end
    references = roles.each_index.select { |i| [:reference, :dfa].include?(roles[i]) }
    x = references.empty? ? nil : @table[args[0]]
    z = references.length == 2 ? @table[args[1]] : nil
    raise AutomatonError, 'alphabets differ' if z && x.alphabet != z.alphabet
    case command
    when 'LIST'
      @table.empty? ? ['(none)'] : @table.map { |name, a| a.summary(name) }
    when 'DELETE'
      @table.delete(args[0])
      ["deleted #{args[0]}"]
    when 'ACCEPT'
      word = args[1] == 'e' ? '' : args[1]
      word.each_char do |c|
        raise AutomatonError, "unknown symbol #{c}" unless x.alphabet.include?(c)
      end
      current = x.closure([x.start])
      format_set = ->(s) { x.kind == 'DFA' ? x.states[s[0]] : x.set_text(s) }
      trace = format_set.call(current)
      word.each_char do |c|
        current = x.move(current, c)
        trace += " -#{c}-> #{format_set.call(current)}"
      end
      ["#{x.accepts_set?(current) ? 'ACCEPT' : 'REJECT'} #{trace}"]
    when 'CLOSURE'
      values = args[1].split(',').map do |name|
        index = x.states.index(name)
        raise AutomatonError, "unknown state #{name}" unless index
        index
      end
      [x.set_text(x.closure(values))]
    when 'TODFA'
      result, subsets = x.determinize
      register(args[1], result, subsets.each_with_index.map { |s, i| "  D#{i} = #{x.set_text(s)}" })
    when 'EPSFREE'
      triples = []
      accepting = []
      x.states.each_index do |p|
        initial = x.closure([p])
        accepting << p if x.accepts_set?(initial)
        x.alphabet.each do |c|
          x.move(initial, c).each { |q| triples << [p, c, q] }
        end
      end
      register(args[1], Automaton.new('NFA', x.states, x.alphabet, x.start, accepting, triples))
    when 'MINIMIZE'
      result, unreachable, rounds, blocks = x.minimize
      details = ["  unreachable: #{x.list_text(unreachable)}"]
      rounds.each_with_index { |partition, i| details << "  round #{i}: #{partition.map { |s| x.set_text(s) }.join(' ')}" }
      blocks.each_with_index { |block, i| details << "  M#{i} = #{x.set_text(block)}" }
      register(args[1], result, details)
    when 'EQUIV'
      equivalent(x, z, args)
    when 'UNION', 'INTERSECT', 'DIFF'
      result, pairs = product(x, z, command)
      details = pairs.each_with_index.map { |(p, q), i| "  P#{i} = (#{x.states[p]},#{z.states[q]})" }
      register(args[2], result, details)
    when 'COMPLEMENT'
      accepting = (0...x.states.length).to_a - x.accepting.to_a
      register(args[1], Automaton.new('DFA', x.states, x.alphabet, x.start, accepting, x.triples))
    when 'REVERSE'
      triples = x.triples.map { |p, c, q| [q + 1, c, p + 1] }
      x.accepting.each { |p| triples << [0, 'e', p + 1] }
      register(args[1], Automaton.new('NFA', Array.new(x.states.length + 1) { |i| "N#{i}" }, x.alphabet, 0, [x.start + 1], triples))
    when 'CONCAT'
      offset = x.states.length
      triples = x.triples + z.triples.map { |p, c, q| [p + offset, c, q + offset] }
      x.accepting.each { |p| triples << [p, 'e', z.start + offset] }
      accepting = z.accepting.map { |p| p + offset }
      register(args[2], Automaton.new('NFA', Array.new(offset + z.states.length) { |i| "N#{i}" }, x.alphabet, x.start, accepting, triples))
    when 'STAR'
      triples = x.triples.map { |p, c, q| [p + 1, c, q + 1] }
      triples << [0, 'e', x.start + 1]
      x.accepting.each { |p| triples << [p + 1, 'e', x.start + 1] }
      accepting = [0] + x.accepting.map { |p| p + 1 }
      register(args[1], Automaton.new('NFA', Array.new(x.states.length + 1) { |i| "N#{i}" }, x.alphabet, 0, accepting, triples))
    when 'ENUM'
      dfa = x.determinize[0]
      level = [[dfa.start, '']]
      total = 0
      examples = []
      (0..args[1].to_i).each do |length|
        level.each do |p, word|
          next unless dfa.accepting.include?(p)
          total += 1
          examples << (word.empty? ? 'e' : word) if examples.length < 50
        end
        if length < args[1].to_i
          level = level.flat_map { |p, word| dfa.alphabet.map { |c| [dfa.edges[p][c][0], word + c] } }
        end
      end
      [[total.to_s, *examples, *(total > 50 ? ['...'] : [])].join(' ')]
    when 'COUNT'
      dfa = x.determinize[0]
      counts = Array.new(dfa.states.length, 0)
      counts[dfa.start] = 1
      args[1].to_i.times do
        next_counts = Array.new(counts.length, 0)
        counts.each_with_index do |value, p|
          dfa.alphabet.each { |c| next_counts[dfa.edges[p][c][0]] += value }
        end
        counts = next_counts
      end
      [dfa.accepting.sum { |p| counts[p] }.to_s]
    when 'EMPTY'
      word = x.determinize[0].shortest_word
      [word.nil? ? 'EMPTY' : "NOT EMPTY #{word.empty? ? 'e' : word}"]
    when 'FINITE'
      size = x.determinize[0].finite_size
      [size.nil? ? 'INFINITE' : "FINITE #{size}"]
    when 'SYNC'
      synchronization(x)
    when 'INFO'
      dfa = x.determinize[0]
      size = dfa.finite_size(false)
      epsilon = x.triples.count { |_, c, _| c == 'e' }
      deterministic = epsilon.zero? && x.edges.all? { |row| x.alphabet.all? { |c| (row[c] || []).length <= 1 } }
      complete = x.edges.all? { |row| x.alphabet.all? { |c| !(row[c] || []).empty? } }
      language = size.nil? ? 'infinite' : size.zero? ? 'empty' : 'finite'
      [x.summary(args[0]), "  epsilon transitions: #{epsilon}",
       "  reachable: #{x.list_text(x.graph_reachable([x.start]))}",
       "  live: #{x.list_text(x.graph_reachable(x.accepting.to_a, true))}",
       "  deterministic: #{deterministic ? 'yes' : 'no'}", "  complete: #{complete ? 'yes' : 'no'}",
       "  language: #{language}", "  minimal DFA states: #{dfa.minimize[0].states.length}"]
    when 'TABLE'
      symbols = x.alphabet + (x.kind == 'NFA' && x.triples.any? { |_, c, _| c == 'e' } ? ['e'] : [])
      rows = [[''] + symbols]
      x.states.each_with_index do |name, p|
        marker = (p == x.start ? '->' : '  ') + (x.accepting.include?(p) ? '*' : ' ') + name
        row = [marker]
        symbols.each do |c|
          values = x.edges[p][c] || []
          row << (x.kind == 'DFA' ? x.states[values[0]] : values.empty? ? '-' : x.set_text(values))
        end
        rows << row
      end
      widths = rows[0].each_index.map { |i| rows.map { |row| row[i].length }.max }
      rows.map { |row| row.each_with_index.map { |cell, i| cell.ljust(widths[i]) }.join('  ').rstrip }
    when 'SHOW'
      accepting = x.accepting.empty? ? '-' : x.accepting.to_a.sort.map { |p| x.states[p] }.join(',')
      words = [x.kind, args[0], x.states.join(','), x.alphabet.join, x.states[x.start], accepting]
      x.triples.each { |p, c, q| words << "#{x.states[p]}:#{c}:#{x.states[q]}" }
      [words.join(' ')]
    end
  end
end

first = STDIN.gets
toolkit = Toolkit.new
first.to_i.times do
  line = STDIN.gets.chomp
  next if line.start_with?('#')
  command, *args = line.split(' ')
  begin
    puts toolkit.execute(command, args)
  rescue AutomatonError => error
    puts "error: #{error.message}"
  end
end
