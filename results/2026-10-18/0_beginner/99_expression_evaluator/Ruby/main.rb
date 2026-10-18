class Parser
  def initialize(tokens, variables)
    @tokens = tokens
    @variables = variables
    @index = 0
  end

  def peek
    @tokens[@index]
  end

  def factor
    token = peek
    @index += 1
    return -factor if token == '-'
    if token == '('
      value = expression
      @index += 1
      return value
    end
    return token.to_i if token.match?(/\A\d+\z/)
    raise "undefined variable #{token}" unless @variables.key?(token)
    @variables[token]
  end

  def term
    value = factor
    while %w[* /].include?(peek)
      operation = peek
      @index += 1
      right = factor
      if operation == '*'
        value *= right
      else
        raise 'division by zero' if right.zero?
        quotient = value.abs / right.abs
        value = value.negative? != right.negative? ? -quotient : quotient
      end
    end
    value
  end

  def expression
    value = term
    while %w[+ -].include?(peek)
      operation = peek
      @index += 1
      right = term
      value = operation == '+' ? value + right : value - right
    end
    value
  end
end

lines = [
  'width = 12', 'height = width - 5', 'area = width * height', '(area + 6) / 4',
  'shift = -area / 8 + 3', 'height = 100 / (height - 7) + bonus',
  'volume = area * depth', 'width = (width+3)*-(2-4)', 'width * shift - height'
]
variables = {}
lines.each do |line|
  tokens = line.scan(/\d+|[a-z]+|[-+*\/()=]/)
  name = tokens[1] == '=' ? tokens[0] : nil
  expression = name ? tokens.drop(2) : tokens
  begin
    value = Parser.new(expression, variables).expression
    if name
      variables[name] = value
      puts "#{name} = #{value}"
    else
      puts value
    end
  rescue RuntimeError => error
    puts "error: #{error.message}"
  end
end
