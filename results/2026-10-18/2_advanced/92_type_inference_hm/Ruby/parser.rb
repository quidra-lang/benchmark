Node = Struct.new(:kind, :position, :children, :value, :inferred) do
  def initialize(kind, position, children = [], value = nil)
    super(kind, position, children, value, nil)
  end
end
Binding = Struct.new(:name, :position, :expression, :scheme, :classification)
Group = Struct.new(:bindings, :rec_position)
Item = Struct.new(:kind, :value)
class SyntaxFailure < StandardError
  attr_reader :token
  def initialize(token)
    @token = token
    super()
  end
end

class Parser
  OPERATORS = {
    '||' => [1, true], '&&' => [2, true],
    '=' => [3, false], '<>' => [3, false], '<' => [3, false], '>' => [3, false],
    '<=' => [3, false], '>=' => [3, false], '::' => [4, true], '^' => [4, true],
    '+' => [5, false], '-' => [5, false], '*' => [6, false], '/' => [6, false], 'mod' => [6, false]
  }.freeze
  def initialize(tokens)
    @tokens, @index = tokens, 0
  end
  def peek = @tokens[@index]
  def accept(kind)
    return unless peek.kind == kind
    token = peek
    @index += 1
    token
  end
  def expect(kind) = accept(kind) || raise(SyntaxFailure.new(peek))
  def name
    raise SyntaxFailure.new(peek) unless peek.name?
    expect('identifier')
  end
  def recover
    @index += 1 until [';;', 'EOF'].include?(peek.kind)
    accept(';;')
  end
  def item
    if accept('val')
      token = name
      expect(':')
      result = Item.new('signature', [token, type_expression])
    elsif (opening = accept('let'))
      bindings = group
      result = if accept('in')
                 Item.new('expression', Node.new('let', opening.position, [expression], bindings))
               else
                 Item.new('declaration', bindings)
               end
    else
      result = Item.new('expression', expression)
    end
    expect(';;')
    result
  end
  def group
    recursive = accept('rec')
    bindings = [binding]
    bindings << binding while accept('and')
    Group.new(bindings, recursive&.position)
  end
  def binding
    token = name
    parameters = []
    parameters << expect('identifier') while peek.kind == 'identifier'
    expect('=')
    body = expression
    parameters.reverse_each { |parameter| body = Node.new('fun', parameter.position, [body], parameter) }
    Binding.new(token.spelling, token.position, body, nil, '')
  end
  def expression
    if (opening = accept('let'))
      bindings = group
      expect('in')
      return Node.new('let', opening.position, [expression], bindings)
    elsif (opening = accept('fun'))
      parameters = [expect('identifier')]
      parameters << expect('identifier') while peek.kind == 'identifier'
      expect('->')
      body = expression
      parameters.reverse_each { |parameter| body = Node.new('fun', parameter.position, [body], parameter) }
      body.position = opening.position
      return body
    elsif (opening = accept('if'))
      condition = expression
      expect('then')
      first = expression
      expect('else')
      return Node.new('if', opening.position, [condition, first, expression])
    elsif (opening = accept('match'))
      matched = expression
      expect('with')
      accept('|')
      arms = [arm]
      arms << arm while accept('|')
      return Node.new('match', opening.position, [matched], arms)
    end
    binary(1)
  end
  def arm
    first = pattern
    expect('->')
    [first, expression]
  end
  def binary(minimum)
    left = unary
    while (details = OPERATORS[peek.kind]) && details[0] >= minimum
      operator = peek
      @index += 1
      right = binary(details[1] ? details[0] : details[0] + 1)
      left = Node.new('binary', left.position, [left, right], operator)
    end
    left
  end
  def starts_atom? = ['integer', 'string', 'true', 'false', '(', '['].include?(peek.kind) || peek.name?
  def unary
    if (operator = accept('-'))
      return Node.new('negate', operator.position, [unary], operator)
    end
    result = atom
    result = Node.new('apply', result.position, [result, atom]) while starts_atom?
    result
  end
  def atom
    token = peek
    if %w[integer string].include?(token.kind)
      @index += 1
      return Node.new(token.kind, token.position, [], token.value)
    elsif %w[true false].include?(token.kind)
      @index += 1
      return Node.new('boolean', token.position, [], token.kind == 'true')
    elsif token.name?
      @index += 1
      return Node.new('name', token.position, [], token.spelling)
    elsif accept('(')
      first = expression
      if accept(',')
        second = expression
        expect(')')
        return Node.new('pair', token.position, [first, second])
      end
      expect(')')
      return first
    elsif accept('[')
      elements = []
      unless accept(']')
        elements << expression
        elements << expression while accept(';')
        expect(']')
      end
      return Node.new('list', token.position, elements)
    end
    raise SyntaxFailure.new(token)
  end
  def pattern
    first = pattern_atom
    accept('::') ? Node.new('cons', first.position, [first, pattern]) : first
  end
  def pattern_atom
    token = peek
    if accept('identifier')
      return Node.new(token.spelling == '_' ? 'wildcard' : 'name', token.position, [], token.spelling)
    elsif accept('-')
      return Node.new('integer', token.position, [], -expect('integer').value)
    elsif %w[integer string true false].include?(token.kind)
      return atom
    elsif accept('(')
      first = pattern
      if accept(',')
        second = pattern
        expect(')')
        return Node.new('pair', token.position, [first, second])
      end
      expect(')')
      return first
    elsif accept('[')
      elements = []
      unless accept(']')
        elements << pattern
        elements << pattern while accept(';')
        expect(']')
      end
      return Node.new('list', token.position, elements)
    end
    raise SyntaxFailure.new(token)
  end
  def type_expression
    first = list_type
    first = Node.new('pair', first.position, [first, list_type]) if accept('*')
    first = Node.new('function', first.position, [first, type_expression]) if accept('->')
    first
  end
  def list_type
    result = type_atom
    while peek.kind == 'identifier' && peek.spelling == 'list'
      @index += 1
      result = Node.new('list', result.position, [result])
    end
    result
  end
  def type_atom
    token = peek
    if token.kind == 'identifier' && %w[int bool string].include?(token.spelling)
      @index += 1
      return Node.new(token.spelling, token.position)
    elsif accept('type_variable')
      return Node.new('type_variable', token.position, [], token.spelling)
    elsif accept('(')
      result = type_expression
      expect(')')
      return result
    end
    raise SyntaxFailure.new(token)
  end
end
