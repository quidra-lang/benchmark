require_relative 'grammar_parser'

module FirstFollow
  module_function

  def terminal_order(tokens)
    tokens.reject { |t| t == '$' }.sort + (tokens.include?('$') ? ['$'] : [])
  end

  def terminals(grammar)
    grammar[:order].flat_map { |lhs| grammar[:rules][lhs].flatten }
           .reject { |s| GrammarParser.nonterminal?(s) }.to_set
  end

  def sequence(rhs, nullable, first)
    result = Set.new
    rhs.each do |symbol|
      unless GrammarParser.nonterminal?(symbol)
        result.add(symbol)
        return [result, false]
      end
      result.merge(first[symbol])
      return [result, false] unless nullable[symbol]
    end
    [result, true]
  end

  def analyze(grammar)
    order, rules = grammar.values_at(:order, :rules)
    nullable = order.to_h { |s| [s, false] }
    first = order.to_h { |s| [s, Set.new] }
    follow = order.to_h { |s| [s, Set.new] }
    follow[grammar[:start]].add('$')
    passes = {}
    %i[nullable first follow].each do |stage|
      count = 0
      loop do
        count += 1
        changed = false
        order.each do |lhs|
          rules[lhs].each do |rhs|
            if stage == :nullable
              if !nullable[lhs] && rhs.all? { |s| GrammarParser.nonterminal?(s) && nullable[s] }
                nullable[lhs] = true
                changed = true
              end
            elsif stage == :first
              more, = sequence(rhs, nullable, first)
              unless more.subset?(first[lhs])
                first[lhs].merge(more)
                changed = true
              end
            else
              rhs.each_with_index do |symbol, index|
                next unless GrammarParser.nonterminal?(symbol)
                more, empty = sequence(rhs.drop(index + 1), nullable, first)
                more.merge(follow[lhs]) if empty
                unless more.subset?(follow[symbol])
                  follow[symbol].merge(more)
                  changed = true
                end
              end
            end
          end
        end
        break unless changed
      end
      passes[stage] = count
    end
    {nullable: nullable, first: first, follow: follow, passes: passes,
     terminals: terminal_order(terminals(grammar))}
  end
end
