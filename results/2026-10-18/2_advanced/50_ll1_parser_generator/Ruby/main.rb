require_relative 'grammar_parser'
require_relative 'transform'
require_relative 'first_follow'
require_relative 'table'
require_relative 'driver'

def list(heading, items)
  heading + items.map { |item| " #{item}" }.join
end

def reachable(grammar)
  seen = Set[grammar[:start]]
  queue = [grammar[:start]]
  until queue.empty?
    grammar[:rules][queue.shift].each do |rhs|
      rhs.each do |symbol|
        queue << symbol if GrammarParser.nonterminal?(symbol) && seen.add?(symbol)
      end
    end
  end
  seen
end

def clean_grammar(source)
  g = Transform.copy(source)
  diagnostics = []
  undefined = g[:rules].values.flatten(2).select do |s|
    GrammarParser.nonterminal?(s) && !g[:rules].key?(s)
  end.to_set
  undefined.sort_by { |s| s[1...-1] }.each { |s| diagnostics << "undefined nonterminal #{s}" }
  g[:order].each do |lhs|
    g[:rules][lhs] = g[:rules][lhs].reject do |rhs|
      bad = rhs.find { |s| undefined.include?(s) }
      diagnostics << "removed #{GrammarParser.production(lhs, rhs)} (undefined #{bad})" if bad
      bad
    end
  end
  productive = Set.new
  loop do
    old_size = productive.size
    g[:order].each do |lhs|
      can_produce = g[:rules][lhs].any? do |rhs|
        rhs.all? { |s| !GrammarParser.nonterminal?(s) || productive.include?(s) }
      end
      productive.add(lhs) if can_produce
    end
    break if productive.size == old_size
  end
  removed = g[:order].reject { |s| productive.include?(s) }.to_set
  g[:order].each { |s| diagnostics << "unproductive nonterminal #{s}" if removed.include?(s) }
  g[:order].reject! { |s| removed.include?(s) }
  removed.each { |s| g[:rules].delete(s) }
  g[:order].each do |lhs|
    g[:rules][lhs] = g[:rules][lhs].reject do |rhs|
      bad = rhs.find { |s| removed.include?(s) }
      diagnostics << "removed #{GrammarParser.production(lhs, rhs)} (unproductive #{bad})" if bad
      bad
    end
  end
  reached = reachable(g)
  g[:order].reject! do |lhs|
    next false if reached.include?(lhs)
    diagnostics << "unreachable nonterminal #{lhs}"
    g[:rules].delete(lhs)
    true
  end
  [g, diagnostics]
end

def left_recursion_diagnostics(g)
  g[:order].filter_map do |start|
    queue = [start]
    parents = {start => nil}
    found = nil
    until queue.empty? || found
      lhs = queue.shift
      g[:rules][lhs].each do |rhs|
        next if rhs.empty? || !GrammarParser.nonterminal?(rhs[0])
        child = rhs[0]
        if child == start
          path = [lhs]
          path << parents[path.last] while parents[path.last]
          found = path.reverse + [start]
          break
        end
        unless parents.key?(child)
          parents[child] = lhs
          queue << child
        end
      end
    end
    "left recursion: #{found.join(' -> ')}" if found
  end
end

def prune_final(grammar)
  g = Transform.copy(grammar)
  reached = reachable(g)
  removed = g[:order].reject { |s| reached.include?(s) }
  g[:order] -= removed
  removed.each { |s| g[:rules].delete(s) }
  [g, removed.map { |s| "remove unreachable #{s}" },
   removed.map { |s| "unreachable after transformation #{s}" }]
end

def grammar_summary(g)
  rows = g[:order].flat_map { |lhs| g[:rules][lhs] }
  "start=#{g[:start]} nonterminals=#{g[:order].length} terminals=#{FirstFollow.terminals(g).size} " \
    "productions=#{rows.length} empty=#{rows.count(&:empty?)} " \
    "unit=#{rows.count { |rhs| rhs.length == 1 && GrammarParser.nonterminal?(rhs[0]) }}"
end

def grammar_listing(g, numbered = false)
  productions = ParseTable.number(g)
  width = productions.length.to_s.length
  previous = nil
  productions.map do |p|
    line = if p[:lhs] == previous
             ' ' * p[:lhs].length + ' | ' + GrammarParser.notation(p[:rhs])
           else
             p[:notation]
           end
    previous = p[:lhs]
    numbered ? p[:number].to_s.rjust(width) + '  ' + line : line
  end
end

def grammar_report(cleaned, recursion, factored, final, logs)
  lines = ['== cleaned grammar ==', grammar_summary(cleaned)] + grammar_listing(cleaned)
  [['left recursion elimination', recursion], ['left factoring', factored], ['final grammar', final]].each_with_index do |(title, g), i|
    lines += ['', "== #{title} =="] + (logs[i].empty? ? ['none'] : logs[i])
    lines += [grammar_summary(g)] + grammar_listing(g, i == 2)
  end
  lines += ['', '== cross reference ==']
  productions = ParseTable.number(final)
  (final[:order] + FirstFollow.terminal_order(FirstFollow.terminals(final))).each do |symbol|
    numbers = productions.select { |p| p[:rhs].include?(symbol) }.map { |p| p[:number] }
    name = GrammarParser.nonterminal?(symbol) ? symbol : "\"#{symbol}\""
    lines << (numbers.empty? ? "#{name} not used" : list("#{name} used in", numbers))
  end
  lines
end

def measure(rhs, scores)
  return nil if rhs.any? { |s| GrammarParser.nonterminal?(s) && !scores.key?(s) }
  length = rhs.sum { |s| GrammarParser.nonterminal?(s) ? scores[s][0] : 1 }
  heights = rhs.select { |s| GrammarParser.nonterminal?(s) }.map { |s| scores[s][1] }
  [length, (heights.max || 0) + 1]
end

def shortest_sentences(g)
  scores = {}
  loop do
    changed = false
    g[:order].each do |lhs|
      g[:rules][lhs].each do |rhs|
        candidate = measure(rhs, scores)
        if candidate && (!scores[lhs] || (candidate <=> scores[lhs]) < 0)
          scores[lhs] = candidate
          changed = true
        end
      end
    end
    break unless changed
  end
  chosen = g[:order].to_h do |lhs|
    [lhs, g[:rules][lhs].find { |rhs| measure(rhs, scores) == scores[lhs] }]
  end
  sentences = {}
  expand = lambda do |symbol|
    return [symbol] unless GrammarParser.nonterminal?(symbol)
    sentences[symbol] ||= chosen[symbol].flat_map { |s| expand.call(s) }
  end
  g[:order].each { |s| expand.call(s) }
  [scores, sentences]
end

def shortest_contexts(g, scores, sentences)
  costs = {g[:start] => [0, 0]}
  parents = {}
  productions = ParseTable.number(g)
  loop do
    changed = false
    productions.each do |p|
      next unless costs.key?(p[:lhs])
      p[:rhs].each_with_index do |symbol, index|
        next unless GrammarParser.nonterminal?(symbol) && symbol != g[:start]
        before, after = p[:rhs].take(index), p[:rhs].drop(index + 1)
        extra = (before + after).sum { |s| GrammarParser.nonterminal?(s) ? scores[s][0] : 1 }
        candidate = [costs[p[:lhs]][0] + extra, costs[p[:lhs]][1] + 1]
        key = [p[:number], index]
        if !costs[symbol] || (candidate <=> costs[symbol]) < 0 ||
           (candidate == costs[symbol] && (key <=> parents[symbol][0]) < 0)
          costs[symbol] = candidate
          parents[symbol] = [key, p[:lhs], before, after]
          changed = true
        end
      end
    end
    break unless changed
  end
  contexts = {g[:start] => [[], []]}
  expand = ->(rhs) { rhs.flat_map { |s| GrammarParser.nonterminal?(s) ? sentences[s] : [s] } }
  context = lambda do |symbol|
    return contexts[symbol] if contexts.key?(symbol)
    _, parent, before, after = parents[symbol]
    prefix, suffix = context.call(parent)
    contexts[symbol] = [prefix + expand.call(before), expand.call(after) + suffix]
  end
  g[:order].each { |s| context.call(s) }
  contexts
end

def sets_report(g, sets, sentences)
  lines = ['passes: ' + %i[nullable first follow].map { |key| "#{key}=#{sets[:passes][key]}" }.join(' '), '']
  g[:order].each do |lhs|
    lines += [lhs, '  nullable: ' + (sets[:nullable][lhs] ? 'yes' : 'no'),
              list('  first:', FirstFollow.terminal_order(sets[:first][lhs])),
              list('  follow:', FirstFollow.terminal_order(sets[:follow][lhs])),
              list('  shortest:', sentences[lhs])]
  end
  lines
end

def first_path(number, token, table, sets)
  by_lhs = table[:productions].group_by { |p| p[:lhs] }
  queue = [number]
  parent = {number => nil}
  until queue.empty?
    current = queue.shift
    table[:productions][current - 1][:rhs].each do |symbol|
      if symbol == token
        path = []
        while current != number
          path << current
          current = parent[current]
        end
        return path.reverse
      end
      break unless GrammarParser.nonterminal?(symbol)
      by_lhs[symbol].each do |p|
        next if parent.key?(p[:number])
        parent[p[:number]] = current
        queue << p[:number]
      end
      break unless sets[:nullable][symbol]
    end
  end
  []
end

def follow_path(lhs, token, g, table, sets)
  queue = [lhs]
  paths = {lhs => []}
  until queue.empty?
    symbol = queue.shift
    path = paths[symbol]
    return path if symbol == g[:start] && token == '$'
    table[:productions].each do |p|
      p[:rhs].each_with_index do |s, index|
        next unless s == symbol
        first, empty = FirstFollow.sequence(p[:rhs].drop(index + 1), sets[:nullable], sets[:first])
        return path + [p[:number]] if first.include?(token)
        if empty && !paths.key?(p[:lhs])
          paths[p[:lhs]] = path + [p[:number]]
          queue << p[:lhs]
        end
      end
    end
  end
  []
end

def table_report(g, sets, table, before)
  lines = ['== predict sets ==']
  table[:productions].each do |p|
    lines += ["#{p[:number]}: #{p[:notation]}", list('  predict:', FirstFollow.terminal_order(p[:predict].keys))]
  end
  tokens = sets[:terminals] + ['$']
  rows = [[''] + tokens]
  g[:order].each do |lhs|
    values = tokens.map do |t|
      entries = table[:cells][[lhs, t]]
      entries.empty? ? '.' : entries.map { |e| e[:number] }.join('/')
    end
    rows << [lhs] + values
  end
  widths = rows.transpose.map { |column| column.map(&:length).max }
  lines += ['', '== parse table ==']
  rows.each do |row|
    lines << row[0].ljust(widths[0]) + row.drop(1).each_with_index.map { |s, i| '  ' + s.rjust(widths[i + 1]) }.join
  end
  lines += ['', '== conflicts ==']
  lines << 'none' if table[:conflicts].empty?
  table[:conflicts].each do |c|
    lines << "conflict #{c[:lhs]} on #{c[:token]}: #{c[:kind]}, chosen #{c[:chosen]}"
    c[:entries].each do |e|
      p = table[:productions][e[:number] - 1]
      path = e[:reason] == 'FIRST' ? first_path(e[:number], c[:token], table, sets) : follow_path(c[:lhs], c[:token], g, table, sets)
      reason = e[:reason] + (path.empty? ? '' : list(' via', path))
      lines << "  #{e[:number]}: #{p[:notation]} (#{reason})"
    end
  end
  lines + ['LL(1): ' + (table[:conflicts].empty? ? 'yes' : 'no'), "conflicts before transformation: #{before}"]
end

def compact_tree(node)
  children = []
  node[:children].each do |original|
    next if original[:symbol] == '%empty'
    child = compact_tree(original)
    next if GrammarParser.nonterminal?(child[:symbol]) && !child[:mark] && child[:children].empty?
    if GrammarParser.nonterminal?(child[:symbol]) && child[:symbol].include?("'") && !child[:mark]
      children.concat(child[:children])
    else
      children << child
    end
  end
  return children.first if children.length == 1 && !node[:mark]
  {symbol: node[:symbol], mark: node[:mark], children: children}
end

def tree_lines(root)
  label = ->(node) { node[:symbol] + (node[:mark] ? " (#{node[:mark]})" : '') }
  lines = [label.call(root)]
  visit = lambda do |node, prefix, last|
    lines << prefix + (last ? '`-- ' : '|-- ') + label.call(node)
    node[:children].each_with_index do |child, index|
      visit.call(child, prefix + (last ? '    ' : '|   '), index == node[:children].length - 1)
    end
  end
  root[:children].each_with_index { |node, i| visit.call(node, '', i == root[:children].length - 1) }
  lines
end

def recognize?(g, tokens)
  # Earley states are [lhs, rhs, dot, origin]; nil is a unique synthetic root.
  chart = Array.new(tokens.length + 1) { Set.new }
  pending = Array.new(tokens.length + 1) { [] }
  add = lambda do |position, state|
    pending[position] << state if chart[position].add?(state)
  end
  add.call(0, [nil, [g[:start]], 0, 0])
  (0..tokens.length).each do |position|
    cursor = 0
    while cursor < pending[position].length
      lhs, rhs, dot, origin = pending[position][cursor]
      cursor += 1
      if dot == rhs.length
        pending[origin].dup.each do |a, body, consumed, start|
          add.call(position, [a, body, consumed + 1, start]) if consumed < body.length && body[consumed] == lhs
        end
      elsif GrammarParser.nonterminal?(rhs[dot])
        symbol = rhs[dot]
        g[:rules][symbol].each { |body| add.call(position, [symbol, body, 0, position]) }
        pending[position].dup.each do |a, body, consumed, start|
          add.call(position, [lhs, rhs, dot + 1, origin]) if a == symbol && consumed == body.length && start == position
        end
      elsif position < tokens.length && rhs[dot] == tokens[position]
        add.call(position + 1, [lhs, rhs, dot + 1, origin])
      end
    end
  end
  chart[-1].include?([nil, [g[:start]], 1, 0])
end

def step_error(record, sets, table)
  token, top, kind = record.values_at(:token, :top, :kind)
  unexpected = token == '$' ? 'end of input' : "\"#{token}\" at token #{record[:position]}"
  expected = if GrammarParser.nonterminal?(top)
               (sets[:terminals] + ['$']).select { |t| table[:choices].key?([top, t]) }
             else
               [top]
             end
  expected = expected.map { |t| t == '$' ? '$' : "\"#{t}\"" }.join(' ')
  recovery = case kind
             when :skip then "skipped \"#{token}\""
             when :pop then "popped #{top}"
             when :missing then "inserted \"#{top}\""
             end
  "step #{record[:step]}: unexpected #{unexpected}; expected #{expected}; #{recovery}"
end

def trace_lines(trace, table)
  rows = [%w[step stack input action]]
  trace.each do |r|
    action = case r[:kind]
             when :accept then 'accept'
             when :match then "match #{r[:token]}"
             when :predict then "predict #{r[:production]}: #{table[:productions][r[:production] - 1][:notation]}"
             when :skip then "error: skip #{r[:token]}"
             when :pop then "error: pop #{r[:top]}"
             when :missing then "error: missing #{r[:top]}"
             end
    rows << [r[:step].to_s, GrammarParser.notation(r[:stack]), GrammarParser.notation(r[:input]), action]
  end
  widths = (0..2).map { |i| rows.map { |r| r[i].length }.max }
  rows.map { |row| (0..2).map { |i| row[i].ljust(widths[i]) }.join('  ') + '  ' + row[3] }
end

def derivation(start, numbers, productions)
  symbols = [start]
  lines = ['  ' + start]
  numbers.each do |number|
    index = symbols.index { |s| GrammarParser.nonterminal?(s) }
    symbols[index, 1] = productions[number - 1][:rhs]
    lines << '  => ' + GrammarParser.notation(symbols)
  end
  lines
end

def parse_input(tokens, g, sets, table, cleaned)
  errors = []
  kept = []
  tokens.each_with_index do |token, i|
    if sets[:terminals].include?(token)
      kept << [token, i + 1]
    else
      errors << "unknown \"#{token}\" at token #{i + 1}; removed"
    end
  end
  parsed = Driver.parse(kept, g, sets, table)
  parsed[:unknown] = errors.length
  parsed[:trace].each { |r| errors << step_error(r, sets, table) if %i[skip pop missing].include?(r[:kind]) }
  parsed.merge(original: tokens, errors: errors, accepted: errors.empty?, language: recognize?(cleaned, tokens))
end

def parses_report(parses, g, sets, table, sentences, contexts)
  lines = []
  parses.each_with_index do |p, index|
    c = p[:counts]
    lines += ["== input #{index + 1} ==", list('tokens:', p[:original])] + trace_lines(p[:trace], table)
    lines += [list('left parse:', p[:left_parse]),
              "stats: steps=#{p[:trace].length} predicts=#{c[:predict]} matches=#{c[:match]} max_stack=#{c[:max_stack]}"]
    lines += ['errors:'] + p[:errors].map { |e| '  ' + e } unless p[:errors].empty?
    lines << (p[:accepted] ? 'result: accepted' : "result: rejected (errors: #{p[:errors].length})")
    lines << 'language: ' + (p[:language] ? 'yes' : 'no')
    lines += ['derivation:'] + derivation(g[:start], p[:left_parse], table[:productions]) if p[:accepted]
    lines += ['tree:'] + tree_lines(p[:root]) + ['compact tree:'] + tree_lines(compact_tree(p[:root])) + ['']
  end
  used = parses.flat_map { |p| p[:left_parse] }.to_set
  unused = table[:productions].reject { |p| used.include?(p[:number]) }
  accepted = parses.count { |p| p[:accepted] }
  mismatches = parses.each_index.select { |i| parses[i][:accepted] != parses[i][:language] }.map { |i| i + 1 }
  recovery = ["unknown=#{parses.sum { |p| p[:unknown] }}"] + %i[skip pop missing].map { |k| "#{k}=#{parses.sum { |p| p[:counts][k] }}" }
  lines += ['== summary ==',
            "inputs=#{parses.length} accepted=#{accepted} rejected=#{parses.length - accepted} in_language=#{parses.count { |p| p[:language] }}",
            list('mismatches:', mismatches), list('recovery:', recovery),
            "coverage: #{used.size} of #{table[:productions].length} productions used", list('unused:', unused.map { |p| p[:number] })]
  unused.each do |production|
    prefix, suffix = contexts[production[:lhs]]
    sentence = prefix + production[:rhs].flat_map { |s| GrammarParser.nonterminal?(s) ? sentences[s] : [s] } + suffix
    parsed = Driver.parse(sentence.each_with_index.map { |word, i| [word, i + 1] }, g, sets, table)
    errors = %i[skip pop missing].sum { |k| parsed[:counts][k] }
    lines += ["  #{production[:number]}: #{production[:notation]}", list('    example:', sentence),
              errors.zero? ? '    result: accepted' : "    result: rejected (errors: #{errors})",
              '    used: ' + (parsed[:left_parse].include?(production[:number]) ? 'yes' : 'no')]
  end
  lines
end

def save(name, lines)
  File.write("output/#{name}", lines.join("\n") + "\n")
end

def main
  source = GrammarParser.read(File.readlines('input/grammar.bnf', chomp: true))
  declarations = if source[:has_declaration]
                   source[:words].keys.sort.reject { |s| source[:declared].include?(s) }.map do |s|
                     "undeclared terminal #{s} at line #{source[:words][s]}"
                   end
                 else
                   []
                 end
  cleaned, cleaning_diagnostics = clean_grammar(source)
  recursion_diagnostics = left_recursion_diagnostics(cleaned)
  recursion, recursion_log = Transform.eliminate(cleaned)
  factored, factoring_log = Transform.factor(recursion)
  final, final_log, final_diagnostics = prune_final(factored)
  unused_diagnostics = source[:has_declaration] ? (source[:declared] - FirstFollow.terminals(final)).sort.map { |s| "unused token #{s}" } : []
  before = ParseTable.build(cleaned, FirstFollow.analyze(cleaned))[:conflicts].length
  sets = FirstFollow.analyze(final)
  table = ParseTable.build(final, sets)
  scores, sentences = shortest_sentences(final)
  contexts = shortest_contexts(final, scores, sentences)
  parses = File.readlines('input/inputs.txt', chomp: true).map do |line|
    parse_input(line.empty? ? [] : line.split(' '), final, sets, table, cleaned)
  end
  diagnostics = source[:diagnostics] + declarations + cleaning_diagnostics + recursion_diagnostics + final_diagnostics + unused_diagnostics
  diagnostics << (table[:conflicts].empty? ? 'result: LL(1)' : "result: not LL(1) (conflicts: #{table[:conflicts].length})")
  save('grammar.txt', grammar_report(cleaned, recursion, factored, final, [recursion_log, factoring_log, final_log]))
  save('sets.txt', sets_report(final, sets, sentences))
  save('table.txt', table_report(final, sets, table, before))
  save('parses.txt', parses_report(parses, final, sets, table, sentences, contexts))
  save('diagnostics.txt', diagnostics)
end

main if $PROGRAM_NAME == __FILE__
