require_relative 'grammar_parser'

module Transform
  module_function

  def copy(grammar)
    {start: grammar[:start], order: grammar[:order].dup,
     rules: grammar[:rules].transform_values { |rows| rows.map(&:dup) }}
  end

  def fresh(lhs, rules)
    name = lhs[0...-1] + "'>"
    name = name[0...-1] + "'>" while rules.key?(name)
    name
  end

  def leading_reaches?(rules, source, target)
    queue = [source]
    seen = Set[source]
    until queue.empty?
      rules[queue.shift].each do |rhs|
        next if rhs.empty? || !GrammarParser.nonterminal?(rhs[0])
        return true if rhs[0] == target
        queue << rhs[0] if seen.add?(rhs[0])
      end
    end
    false
  end

  def eliminate(grammar)
    g = copy(grammar)
    original = g[:order].dup
    log = []
    original.each_with_index do |lhs, index|
      original.take(index).each do |earlier|
        next unless g[:rules][lhs].any? { |rhs| rhs[0] == earlier }
        next unless leading_reaches?(g[:rules], earlier, lhs)
        g[:rules][lhs] = g[:rules][lhs].flat_map do |rhs|
          rhs[0] == earlier ? g[:rules][earlier].map { |delta| delta + rhs.drop(1) } : [rhs]
        end.uniq
        log << "substitute #{earlier} into #{lhs}"
      end
      if g[:rules][lhs].delete([lhs])
        log << "remove cycle #{lhs} -> #{lhs}"
      end
      recursive, others = g[:rules][lhs].partition { |rhs| rhs[0] == lhs }
      next if recursive.empty?
      created = fresh(lhs, g[:rules])
      g[:rules][lhs] = others.map { |rhs| rhs + [created] }
      g[:rules][created] = recursive.map { |rhs| rhs.drop(1) + [created] } + [[]]
      g[:order].insert(g[:order].index(lhs) + 1, created)
      log << "eliminate left recursion in #{lhs} with #{created}"
    end
    [g, log]
  end

  def factor(grammar)
    g = copy(grammar)
    log = []
    position = 0
    while position < g[:order].length
      lhs = g[:order][position]
      rows = g[:rules][lhs]
      result = []
      created_names = []
      handled = Set.new
      rows.each do |rhs|
        if rhs.empty?
          result << rhs
          next
        end
        next unless handled.add?(rhs[0])
        group = rows.select { |other| other[0] == rhs[0] }
        if group.length == 1
          result << rhs
          next
        end
        length = 0
        limit = group.map(&:length).min
        length += 1 while length < limit && group.all? { |row| row[length] == rhs[length] }
        prefix = rhs.take(length)
        created = fresh(lhs, g[:rules])
        g[:rules][created] = group.map { |row| row.drop(length) }
        result << prefix + [created]
        created_names << created
        log << "left factor #{lhs} on #{GrammarParser.notation(prefix)} with #{created}"
      end
      g[:rules][lhs] = result
      g[:order].insert(position + 1, *created_names)
      position += 1
    end
    [g, log]
  end
end
