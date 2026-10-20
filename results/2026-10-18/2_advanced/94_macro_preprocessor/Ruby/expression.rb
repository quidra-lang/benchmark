module Expression
  LEVELS = [%w[||], %w[&&], %w[|], %w[^], %w[&], %w[== !=], %w[< > <= >=], %w[<< >>], %w[+ -], %w[* / %]].freeze
  class Error < StandardError; end
  module_function

  def integer(spelling)
    value = spelling.sub(/(?:ll|LL|l|L)\z/, '')
    return value.to_i(16) if value.match?(/\A0[xX][0-9a-fA-F]+\z/)
    return value.to_i(8) if value.match?(/\A0[0-7]*\z/)
    return value.to_i if value.match?(/\A[1-9][0-9]*\z/)
    raise Error, "invalid integer constant \"#{spelling}\""
  end

  def character(spelling)
    value = spelling[1...-1]
    return value.ord if value.length == 1 && !["'", '\\'].include?(value)
    escapes = {'n' => 10, 't' => 9, '\\' => 92, "'" => 39, '"' => 34, '0' => 0}
    return escapes[value[1]] if value.length == 2 && value[0] == '\\' && escapes.key?(value[1])
    raise Error, "invalid character constant #{spelling}"
  end

  # An explicit parsing stack avoids a host call-stack limit for deep input.
  def parse(tokens, directive)
    raise Error, "##{directive} with no expression" if tokens.empty?
    tasks, values, position = [[:expression]], [], 0
    until tasks.empty?
      operation, *args = tasks.pop
      spelling = tokens[position]&.spelling
      case operation
      when :expression
        tasks.push([:conditional], [:binary, 0])
      when :conditional
        if spelling == '?'
          position += 1
          tasks.push([:middle, values.pop], [:expression])
        end
      when :middle
        raise Error, "'?' without following ':'" unless spelling == ':'
        position += 1
        tasks.push([:finish_conditional, args[0], values.pop], [:expression])
      when :finish_conditional
        values << [:conditional, args[0], args[1], values.pop]
      when :binary
        level = args[0]
        if level == LEVELS.length
          tasks << [:unary]
        else
          tasks.push([:binary_tail, level], [:binary, level + 1])
        end
      when :binary_tail
        level = args[0]
        if LEVELS[level].include?(spelling)
          position += 1
          tasks.push([:finish_binary, level, spelling, values.pop], [:binary, level + 1])
        end
      when :finish_binary
        level, operator, left = args
        values << [:binary, operator, left, values.pop]
        tasks << [:binary_tail, level]
      when :unary
        if %w[+ - ! ~].include?(spelling)
          position += 1
          tasks.push([:finish_unary, spelling], [:unary])
          next
        end
        token = tokens[position]
        raise Error, 'expected value at end of expression' unless token
        position += 1
        case token.kind
        when :number then values << [:constant, integer(token.spelling)]
        when :character then values << [:constant, character(token.spelling)]
        when :identifier then values << [:identifier, token.spelling]
        else
          raise Error, "expected value before \"#{token.spelling}\"" unless token.spelling == '('
          tasks.push([:closing], [:expression])
        end
      when :closing
        raise Error, "missing ')' in expression" unless spelling == ')'
        position += 1
      when :finish_unary
        values << [:unary, args[0], values.pop]
      end
    end
    raise Error, "missing binary operator before \"#{tokens[position].spelling}\"" if position < tokens.length
    values[0]
  end

  def binary(operator, left, right)
    case operator
    when '/', '%'
      raise Error, 'division by zero in #if' if right.zero?
      quotient = left.abs / right.abs
      quotient = -quotient if left.negative? != right.negative?
      operator == '/' ? quotient : left - right * quotient
    when '+' then left + right
    when '-' then left - right
    when '*' then left * right
    when '<<' then left << right
    when '>>' then left >> right
    when '&' then left & right
    when '|' then left | right
    when '^' then left ^ right
    else
      (left.public_send(operator, right)) ? 1 : 0
    end
  end

  def evaluate(tree, &warning)
    tasks, values = [[:evaluate, tree]], []
    until tasks.empty?
      operation, item = tasks.pop
      case operation
      when :evaluate
        case item[0]
        when :constant then values << item[1]
        when :identifier
          warning.call("identifier \"#{item[1]}\" evaluates to 0")
          values << 0
        when :unary then tasks.push([:unary, item[1]], [:evaluate, item[2]])
        when :conditional then tasks.push([:choose, [item[2], item[3]]], [:evaluate, item[1]])
        when :binary
          if %w[&& ||].include?(item[1])
            tasks.push([:logical, [item[1], item[3]]], [:evaluate, item[2]])
          else
            tasks.push([:binary, item[1]], [:evaluate, item[3]], [:evaluate, item[2]])
          end
        end
      when :choose then tasks << [:evaluate, values.pop.zero? ? item[1] : item[0]]
      when :logical
        left = values.pop
        if (item[0] == '&&' && left.zero?) || (item[0] == '||' && !left.zero?)
          values << (left.zero? ? 0 : 1)
        else
          tasks.push([:truth, nil], [:evaluate, item[1]])
        end
      when :truth then values << (values.pop.zero? ? 0 : 1)
      when :unary
        value = values.pop
        values << case item
                  when '+' then value
                  when '-' then -value
                  when '!' then value.zero? ? 1 : 0
                  when '~' then -value - 1
                  end
      when :binary
        right, left = values.pop, values.pop
        values << binary(item, left, right)
      end
    end
    values[0]
  end
end
