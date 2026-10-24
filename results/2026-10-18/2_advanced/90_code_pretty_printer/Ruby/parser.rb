require_relative 'lexer'

class Parser
  PRECEDENCE = {'||'=>1, '&&'=>2, '=='=>3, '!='=>3, '<'=>4, '<='=>4,
                '>'=>4, '>='=>4, '+'=>5, '-'=>5, '*'=>6, '/'=>6, '%'=>6}.freeze
  def initialize(tokens)
    @tokens, @cursor = tokens, 0
  end
  def peek = @tokens[@cursor]
  def at?(text) = peek[:text] == text
  def shift
    token = peek
    @cursor += 1
    token
  end
  def fail_expected(expected)
    actual = peek[:kind] == :end ? 'end of file' : "'#{peek[:text]}'"
    raise SourceError.new(peek[:line], peek[:column], "expected #{expected}, found #{actual}")
  end
  def take(text)
    fail_expected("'#{text}'") unless at?(text)
    shift
  end
  def identifier
    fail_expected('identifier') unless peek[:kind] == :identifier
    shift
  end
  def type
    fail_expected('type') unless type?
    shift
  end
  def type? = Lexer::TYPES.include?(peek[:text])
  def node(tag, first, **props) = {tag: tag, first: first, **props}
  def allow(token) = token[:allowed] = true
  def parse
    items = []
    until peek[:kind] == :end
      typ, name = type, identifier
      allow(typ)
      items << if at?('(')
                 params = list('(', ')', false) { parameter }
                 node(:function, typ, typ: typ, name: name, parameters: params, body: block)
               else
                 variable(typ, name, true)
               end
    end
    items
  end
  def parameter
    typ, name, brackets = type, identifier, []
    brackets << [take('['), take(']')] while at?('[')
    node(:parameter, typ, typ: typ, name: name, brackets: brackets)
  end
  def variable(typ, name, semicolon)
    dimensions = []
    while at?('[')
      left = take('[')
      value = at?(']') ? nil : expression
      dimensions << [left, value, take(']')]
    end
    equals = at?('=') ? take('=') : nil
    value = equals ? initializer : nil
    semi = semicolon ? take(';') : nil
    node(:variable, typ, typ: typ, name: name, dimensions: dimensions,
         equals: equals, initializer: value, semi: semi)
  end
  def initializer
    at?('{') ? list('{', '}', true) { initializer } : expression
  end
  def list(opening, closing, trailing)
    left, elements, commas, final = take(opening), [], [], nil
    unless at?(closing)
      element = yield
      allow(element[:first])
      elements << element
      while at?(',')
        comma = take(',')
        if trailing && at?(closing)
          comma[:trailing_comma] = true
          final = comma
          break
        end
        commas << comma
        element = yield
        allow(element[:first])
        elements << element
      end
    end
    node(:list, left, left: left, right: take(closing), elements: elements,
         commas: commas, trailing: final, role: opening)
  end
  def block
    left, statements = take('{'), []
    until at?('}') || peek[:kind] == :end
      stmt = statement
      allow(stmt[:first])
      statements << stmt
    end
    right = take('}')
    allow(right)
    node(:block, left, left: left, right: right, statements: statements)
  end
  def body
    stmt = statement
    allow(stmt[:first]) unless stmt[:tag] == :block
    stmt
  end
  def statement
    return block if at?('{')
    return variable(type, identifier, true) if type?
    return control_if if at?('if')
    return control_while if at?('while')
    return control_for if at?('for')
    return control_switch if at?('switch')
    if at?('return')
      keyword = shift
      value = at?(';') ? nil : expression
      return node(:return, keyword, keyword: keyword, expr: value, semi: take(';'))
    end
    if at?('break') || at?('continue')
      keyword = shift
      return node(:flow, keyword, keyword: keyword, semi: take(';'))
    end
    value = simple
    node(:simple_stmt, value[:first], value: value, semi: take(';'))
  end
  def control_if
    keyword, left = take('if'), take('(')
    test = expression
    right, before = take(')'), body
    else_token = at?('else') ? take('else') : nil
    alternative = if else_token
                    at?('if') ? control_if : body
                  end
    node(:if, keyword, keyword: keyword, left: left, test: test, right: right,
         body: before, else_token: else_token, alternative: alternative)
  end
  def control_while
    keyword, left = take('while'), take('(')
    test = expression
    right = take(')')
    node(:while, keyword, keyword: keyword, left: left, test: test, right: right, body: body)
  end
  def control_for
    keyword, left = take('for'), take('(')
    initial = at?(';') ? nil : (type? ? variable(type, identifier, false) : simple)
    first_semi = take(';')
    condition = at?(';') ? nil : expression
    second_semi = take(';')
    update = at?(')') ? nil : simple
    right = take(')')
    node(:for, keyword, keyword: keyword, left: left, initial: initial,
         first_semi: first_semi, condition: condition, second_semi: second_semi,
         update: update, right: right, body: body)
  end
  def control_switch
    keyword, left = take('switch'), take('(')
    test = expression
    right, opening, clauses = take(')'), take('{'), []
    while at?('case') || at?('default')
      label = shift
      allow(label)
      value = label[:text] == 'case' ? expression : nil
      colon, statements = take(':'), []
      until %w[case default }].include?(peek[:text]) || peek[:kind] == :end
        stmt = statement
        allow(stmt[:first])
        statements << stmt
      end
      clauses << node(:clause, label, label: label, value: value, colon: colon, statements: statements)
    end
    closing = take('}')
    allow(closing)
    node(:switch, keyword, keyword: keyword, left: left, test: test, right: right,
         opening: opening, closing: closing, clauses: clauses)
  end
  def simple
    left = expression
    if Lexer::ASSIGNMENT.include?(peek[:text])
      op = shift
      node(:assign, left[:first], left: left, op: op, right: expression)
    else
      node(:expr_stmt, left[:first], expr: left)
    end
  end
  def expression
    test = binary(1)
    return test unless at?('?')
    question = take('?')
    yes = expression
    colon = take(':')
    node(:conditional, test[:first], test: test, question: question, yes: yes,
         colon: colon, no: expression, level: 0)
  end
  def binary(level)
    return unary if level > 6
    left = binary(level + 1)
    while PRECEDENCE[peek[:text]] == level
      op = shift
      left = node(:binary, left[:first], left: left, op: op, right: binary(level + 1), level: level)
    end
    left
  end
  def unary
    if at?('-') || at?('!')
      op = shift
      return node(:unary, op, op: op, operand: unary, level: 7)
    end
    target = primary
    loop do
      target = if at?('(')
                 node(:call, target[:first], target: target, arguments: list('(', ')', false) { expression })
               elsif at?('[')
                 left = take('[')
                 index = expression
                 node(:index, target[:first], target: target, left: left, index: index, right: take(']'))
               elsif at?('.')
                 node(:member, target[:first], target: target, dot: take('.'), member: identifier)
               else
                 break
               end
    end
    target
  end
  def primary
    if %i[identifier number string].include?(peek[:kind]) || %w[true false].include?(peek[:text])
      token = shift
      return node(:primary, token, value: token)
    end
    if at?('(')
      left = take('(')
      inner = expression
      return node(:paren, left, left: left, inner: inner, right: take(')'))
    end
    fail_expected('expression')
  end
end
