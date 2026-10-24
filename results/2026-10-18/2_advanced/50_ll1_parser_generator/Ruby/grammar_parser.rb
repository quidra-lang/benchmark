require 'set'

module GrammarParser
  module_function

  def nonterminal?(symbol)
    symbol.start_with?('<') && symbol.end_with?('>')
  end

  def notation(symbols)
    symbols.empty? ? '%empty' : symbols.join(' ')
  end

  def production(lhs, rhs)
    "#{lhs} -> #{notation(rhs)}"
  end

  def lex(line)
    tokens = []
    cursor = 0
    while cursor < line.length
      if line[cursor] == ' '
        cursor += 1
        next
      end
      break if line[cursor] == '#'
      start = cursor
      rest = line[cursor..]
      kind, value, raw = if (match = /\A<[A-Za-z][A-Za-z0-9_]*>/.match(rest))
                           [:nonterminal, match[0], match[0]]
                         elsif (match = /\A"([^ "]+)"/.match(rest))
                           [:terminal, match[1], match[0]]
                         elsif (match = /\A[A-Za-z][A-Za-z0-9_]*/.match(rest))
                           [:word, match[0], match[0]]
                         elsif rest.start_with?('::=')
                           [:definition, '::=', '::=']
                         elsif rest.start_with?('|')
                           [:separator, '|', '|']
                         elsif (match = /\A%([A-Za-z]+)/.match(rest)) && %w[empty start token].include?(match[1])
                           [:directive, match[0], match[0]]
                         else
                           [:invalid, line[cursor], line[cursor]]
                         end
      cursor += raw.length
      tokens << {kind: kind, value: value, start: start + 1, end: cursor}
      break if kind == :invalid
    end
    tokens
  end

  def error_column(tokens, cursor)
    cursor < tokens.length ? tokens[cursor][:start] : tokens[-1][:end] + 1
  end

  def alternatives(tokens, cursor)
    result = []
    loop do
      return [nil, error_column(tokens, cursor)] if cursor >= tokens.length
      token = tokens[cursor]
      if token[:kind] == :directive && token[:value] == '%empty'
        rhs = []
        cursor += 1
      elsif %i[nonterminal terminal word].include?(token[:kind])
        rhs = []
        while cursor < tokens.length && %i[nonterminal terminal word].include?(tokens[cursor][:kind])
          rhs << tokens[cursor][:value]
          cursor += 1
        end
      else
        return [nil, error_column(tokens, cursor)]
      end
      result << rhs
      return [result, nil] if cursor == tokens.length
      return [nil, error_column(tokens, cursor)] unless tokens[cursor][:kind] == :separator
      cursor += 1
    end
  end

  def parse_line(tokens)
    return [:blank, nil, nil, nil] if tokens.empty?
    first = tokens[0]
    if first[:kind] == :nonterminal
      return [nil, nil, nil, error_column(tokens, 1)] unless tokens[1] && tokens[1][:kind] == :definition
      rows, error = alternatives(tokens, 2)
      return [:rule, first[:value], rows, error]
    end
    if first[:kind] == :separator
      rows, error = alternatives(tokens, 1)
      return [:continuation, nil, rows, error]
    end
    if first[:kind] == :directive && first[:value] == '%start'
      return [nil, nil, nil, error_column(tokens, 1)] unless tokens[1] && tokens[1][:kind] == :nonterminal
      return [nil, nil, nil, error_column(tokens, 2)] if tokens.length > 2
      return [:start, tokens[1][:value], nil, nil]
    end
    if first[:kind] == :directive && first[:value] == '%token'
      bad = (1...tokens.length).find { |i| tokens[i][:kind] != :word }
      bad = 1 if tokens.length == 1
      return [nil, nil, nil, error_column(tokens, bad)] if bad
      return [:declaration, nil, tokens.drop(1).map { |t| t[:value] }, nil]
    end
    [nil, nil, nil, error_column(tokens, 0)]
  end

  def read(lines)
    grammar = {order: [], rules: {}, start: nil, declared: Set.new,
               has_declaration: false, words: {}, diagnostics: []}
    attachment = nil
    lines.each_with_index do |line, index|
      number = index + 1
      tokens = lex(line)
      kind, lhs, rows, error = parse_line(tokens)
      if error
        grammar[:diagnostics] << "line #{number}: syntax error at column #{error}"
        attachment = nil
        next
      end
      case kind
      when :blank
        next
      when :rule
        attachment = lhs
        unless grammar[:rules].key?(lhs)
          grammar[:order] << lhs
          grammar[:rules][lhs] = []
        end
      when :continuation
        unless attachment
          grammar[:diagnostics] << "line #{number}: continuation without a rule"
          next
        end
        lhs = attachment
      when :start
        attachment = nil
        if grammar[:start]
          grammar[:diagnostics] << "line #{number}: duplicate %start"
        else
          grammar[:start] = lhs
        end
      when :declaration
        attachment = nil
        grammar[:has_declaration] = true
        grammar[:declared].merge(rows)
      end
      next unless %i[rule continuation].include?(kind)
      tokens.each do |token|
        grammar[:words][token[:value]] ||= number if token[:kind] == :word
      end
      rows.each do |rhs|
        if grammar[:rules][lhs].include?(rhs)
          grammar[:diagnostics] << "line #{number}: duplicate alternative #{production(lhs, rhs)}"
        else
          grammar[:rules][lhs] << rhs
        end
      end
    end
    grammar[:start] ||= grammar[:order].first
    grammar
  end
end
