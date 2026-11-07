Node = Struct.new(:kind, :token, :args)

class Parser
  ASSIGNMENTS = %w[= += -= *= /= %= ^=].freeze
  attr_reader :rules, :functions, :statement_lines

  def initialize(tokens)
    @tokens, @at, @rules, @functions = tokens, 0, [], []
    @statement_lines, @context, @loops, @stop_gt = {}, :rule, 0, false
  end

  def current
    @tokens[@at]
  end

  def kind
    current.kind
  end

  def take
    token = current
    @at += 1
    token
  end

  def expect(wanted)
    raise AwkSyntaxError.new(current) unless kind == wanted
    take
  end

  def accept(wanted)
    take if kind == wanted
  end

  def newlines
    take while kind == :nl
  end

  def node(kind, token, *args)
    Node.new(kind, token, args)
  end

  def parse
    until kind == :eof
      if [:nl, ';'].include?(kind)
        take
      elsif kind == 'function'
        function
      else
        item
      end
    end
    self
  end

  def function
    take
    raise AwkSyntaxError.new(current) unless [:name, :funcname].include?(kind)
    name = take
    expect('(')
    parameters = []
    unless kind == ')'
      parameters << expect(:name)
      while accept(',')
        newlines
        parameters << expect(:name)
      end
    end
    expect(')')
    newlines
    @context = :function
    body = block
    @functions << { name: name, parameters: parameters, body: body, calls: 0, active: 0, depth: 0 }
    @context = :rule
  end

  def item
    token, first, last = current, nil, nil
    if ['BEGIN', 'END'].include?(kind)
      type = take.text
      @context = type.to_sym
      action = block
      @context = :rule
    elsif kind == '{'
      type, action = 'all', block
    else
      type, first = 'pattern', expression
      if accept(',')
        newlines
        last, type = expression, 'range'
      end
      if kind == '{'
        action = block
      elsif ![:nl, ';', :eof].include?(kind)
        raise AwkSyntaxError.new(current)
      end
    end
    @rules << { token: token, kind: type, first: first, last: last, action: action, count: 0, inside: false }
  end

  def block
    token = expect('{')
    statements = []
    until kind == '}'
      if [:nl, ';'].include?(kind)
        take
      else
        statements << statement
      end
    end
    expect('}')
    node(:block, token, statements)
  end

  def statement
    return block if kind == '{'
    return node(:empty, take) if kind == ';'
    token = current
    @statement_lines[token.line] = 0
    case kind
    when 'if'
      take
      condition = parenthesized
      newlines
      yes = statement
      newlines
      no = nil
      if accept('else')
        newlines
        no = statement
      end
      node(:if, token, condition, yes, no)
    when 'while'
      take
      condition = parenthesized
      node(:while, token, condition, loop_body)
    when 'do'
      take
      body = loop_body
      newlines
      expect('while')
      condition = parenthesized
      terminator
      node(:do, token, condition, body)
    when 'for' then for_statement
    else
      result = simple_statement
      terminator
      result
    end
  end

  def loop_body
    newlines
    @loops += 1
    body = statement
    @loops -= 1
    body
  end

  def for_statement
    token = take
    expect('(')
    if @tokens[@at, 4].map(&:kind) == [:name, 'in', :name, ')']
      variable = take
      take
      array = take
      take
      node(:forin, token, variable, array, loop_body)
    else
      first = expression unless kind == ';'
      expect(';')
      newlines
      condition = expression unless kind == ';'
      expect(';')
      newlines
      update = expression unless kind == ')'
      expect(')')
      node(:for, token, first, condition, update, loop_body)
    end
  end

  def terminator
    return if kind == '}'
    raise AwkSyntaxError.new(current) unless [';', :nl].include?(kind)
    take
  end

  def simple_statement
    token = current
    case kind
    when 'print', 'printf' then output_statement
    when 'delete'
      take
      name = expect(:name)
      subscripts = nil
      if accept('[')
        subscripts = nested { expression_list }
        expect(']')
      end
      node(:delete, token, name, subscripts)
    when 'next', 'break', 'continue', 'return', 'exit'
      take
      invalid = token.kind == 'next' && [:BEGIN, :END].include?(@context)
      invalid ||= token.kind == 'return' && @context != :function
      invalid ||= ['break', 'continue'].include?(token.kind) && @loops.zero?
      raise AwkSyntaxError.new(token) if invalid
      value = expression if ['exit', 'return'].include?(token.kind) && ![';', :nl, '}'].include?(kind)
      node(token.kind.to_sym, token, value)
    else
      node(:expression, token, expression)
    end
  end

  def output_statement
    token = take
    arguments = []
    if kind == '('
      depth, index = 0, @at
      loop do
        break if index >= @tokens.length
        depth += 1 if @tokens[index].kind == '('
        depth -= 1 if @tokens[index].kind == ')'
        break if depth.zero?
        index += 1
      end
      enclosed = index < @tokens.length && [';', :nl, '}', '>', '>>', :eof].include?(@tokens[index + 1]&.kind)
    end
    if enclosed
      take
      arguments = nested { expression_list }
      expect(')')
    elsif ![';', :nl, '}', '>', '>>'].include?(kind)
      old, @stop_gt = @stop_gt, true
      arguments = expression_list
      @stop_gt = old
    end
    raise AwkSyntaxError.new(current) if token.text == 'printf' && arguments.empty?
    redirect = nil
    if ['>', '>>'].include?(kind)
      operator = take
      redirect = [operator, concat_expression]
    end
    node(:output, token, arguments, redirect)
  end

  def nested
    old, @stop_gt = @stop_gt, false
    result = yield
    @stop_gt = old
    result
  end

  def parenthesized
    expect('(')
    result = nested { expression }
    expect(')')
    result
  end

  def expression_list
    list = [expression]
    while accept(',')
      newlines
      list << expression
    end
    list
  end

  def lvalue?(n)
    [:variable, :array, :field].include?(n.kind)
  end

  def expression
    left = conditional
    if lvalue?(left) && ASSIGNMENTS.include?(kind)
      token = take
      left = node(:assign, token, left, expression)
    end
    left
  end

  def conditional
    condition = or_expression
    if (token = accept('?'))
      yes = conditional
      expect(':')
      node(:conditional, token, condition, yes, conditional)
    else
      condition
    end
  end

  def binary(method, operators, skip_newlines = false)
    left = send(method)
    while operators.include?(kind)
      token = take
      newlines if skip_newlines
      left = node(:binary, token, left, send(method))
    end
    left
  end

  def or_expression
    binary(:and_expression, ['||'], true)
  end

  def and_expression
    binary(:in_expression, ['&&'], true)
  end

  def in_expression
    left = comparison
    while (token = accept('in'))
      left = node(:in, token, [left], expect(:name))
    end
    left
  end

  def comparison
    operators = %w[< <= == != >=]
    operators << '>' unless @stop_gt
    binary(:concat_expression, operators)
  end

  def concat_expression
    left = additive
    while [:number, :string, :name, :funcname, :builtin, '$', '(', '++', '--'].include?(kind)
      token = current
      left = node(:concat, token, left, additive)
    end
    left
  end

  def additive
    binary(:multiplicative, ['+', '-'])
  end

  def multiplicative
    binary(:unary, ['*', '/', '%'])
  end

  def unary
    if ['!', '-', '+'].include?(kind)
      token = take
      node(:unary, token, unary)
    else
      left = postfix
      if (token = accept('^'))
        left = node(:binary, token, left, unary)
      end
      left
    end
  end

  def postfix
    return prefix if ['++', '--'].include?(kind)
    result = atom
    if lvalue?(result) && ['++', '--'].include?(kind)
      result = node(:increment, take, result, false)
    end
    result
  end

  def prefix
    token = take
    node(:increment, token, lvalue, true)
  end

  def lvalue
    if kind == :name
      token = take
      if accept('[')
        subscripts = nested { expression_list }
        expect(']')
        node(:array, token, subscripts)
      else
        node(:variable, token)
      end
    elsif kind == '$'
      token = take
      field = ['++', '--'].include?(kind) ? prefix : atom
      node(:field, token, field)
    else
      raise AwkSyntaxError.new(current)
    end
  end

  def atom
    token = current
    case kind
    when :number, :string
      take
      node(token.kind, token)
    when :name, '$' then lvalue
    when '('
      take
      expressions = nested { expression_list }
      expect(')')
      if expressions.length == 1
        node(:parentheses, token, expressions[0])
      else
        expect('in')
        node(:in, token, expressions, expect(:name))
      end
    when :funcname, :builtin
      take
      arguments = []
      if accept('(')
        arguments = nested { expression_list } unless kind == ')'
        expect(')')
      elsif token.kind != :builtin || token.text != 'length'
        raise AwkSyntaxError.new(current)
      end
      if token.kind == :builtin
        count = arguments.length
        valid = case token.text
                when 'length' then count <= 1
                when 'substr', 'split' then [2, 3].include?(count)
                when 'index' then count == 2
                when 'sprintf' then count >= 1
                else count == 1
                end
        valid &&= arguments[1]&.kind == :variable if token.text == 'split'
        raise AwkSyntaxError.new(token) unless valid
      end
      node(token.kind == :builtin ? :builtin : :call, token, arguments)
    when 'getline'
      take
      target = lvalue if [:name, '$'].include?(kind)
      file = atom if accept('<')
      node(:getline, token, target, file)
    else
      raise AwkSyntaxError.new(current)
    end
  end
end
