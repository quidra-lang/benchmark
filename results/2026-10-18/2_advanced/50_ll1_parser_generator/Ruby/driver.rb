require_relative 'grammar_parser'

module Driver
  module_function

  def node(symbol)
    {symbol: symbol, mark: nil, children: []}
  end

  def parse(tokens, grammar, sets, table)
    input = tokens + [['$', nil]]
    root = node(grammar[:start])
    stack = [['$', nil], [grammar[:start], root]]
    cursor = 0
    trace = []
    left_parse = []
    counts = {predict: 0, match: 0, skip: 0, pop: 0, missing: 0, max_stack: 0}
    loop do
      top, current_node = stack.last
      token, position = input[cursor]
      counts[:max_stack] = [counts[:max_stack], stack.length].max
      record = {step: trace.length + 1, stack: stack.map(&:first),
                input: input.drop(cursor).map(&:first), top: top, token: token, position: position}
      if top == '$' && token == '$'
        kind = :accept
      elsif top == '$'
        kind = :skip
        cursor += 1
      elsif !GrammarParser.nonterminal?(top)
        if top == token
          kind = :match
          cursor += 1
        else
          kind = :missing
          current_node[:mark] = 'missing'
        end
        stack.pop
      elsif (number = table[:choices][[top, token]])
        kind = :predict
        record[:production] = number
        left_parse << number
        stack.pop
        rhs = table[:productions][number - 1][:rhs]
        children = rhs.map { |symbol| node(symbol) }
        current_node[:children] = children.empty? ? [node('%empty')] : children
        children.reverse_each { |child| stack << [child[:symbol], child] }
      elsif token == '$' || sets[:follow][top].include?(token)
        kind = :pop
        current_node[:mark] = 'error'
        stack.pop
      else
        kind = :skip
        cursor += 1
      end
      record[:kind] = kind
      trace << record
      break if kind == :accept
      counts[kind] += 1
    end
    {root: root, trace: trace, left_parse: left_parse, counts: counts}
  end
end
