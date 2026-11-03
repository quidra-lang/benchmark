class Node
  attr_accessor :kind, :position, :type, :name, :name_position, :parameters, :body,
                :size, :size_position, :initializer, :statements, :end_position,
                :condition, :then_branch, :otherwise, :initial, :update, :value,
                :arguments, :expression, :index, :operator, :operand, :left, :right,
                :referent, :references, :read_accesses, :calls, :slot, :address, :completes
  def initialize(kind, position, **fields)
    @kind, @position = kind, position
    fields.each { |name, value| public_send("#{name}=", value) }
  end
end
module Tree
  module_function
  def expression_children(node)
    case node.kind
    when 'binary' then [node.left, node.right]
    when 'unary' then [node.operand]
    when 'array' then [node.index]
    when 'call' then node.arguments
    else []
    end
  end
  def statement_children(node)
    case node.kind
    when 'block' then node.statements
    when 'if' then [node.then_branch, node.otherwise].compact
    when 'while' then [node.body]
    when 'for' then [node.initial, node.update, node.body].compact
    else []
    end
  end
end
class Parser
  TYPES = %w[int bool void].freeze
  OPERATORS = [%w[||], %w[&&], %w[== !=], %w[< <= > >=], %w[+ -], %w[* / %]].freeze
  def initialize(tokens)
    @tokens, @index = tokens, 0
  end
  def peek = @tokens[@index]
  def fail_parse
    message = peek.kind == 'end' ? 'unexpected end of program' : "unexpected '#{peek.spelling}'"
    raise CompileError.new('syntax', peek.position, message)
  end
  def take
    token = peek
    @index += 1
    token
  end
  def accept(spelling) = peek.spelling == spelling ? take : nil
  def expect(spelling)
    fail_parse unless peek.spelling == spelling
    take
  end
  def identifier
    fail_parse unless peek.kind == 'identifier'
    take
  end
  def declaration_head
    fail_parse unless TYPES.include?(peek.spelling)
    type = take
    name = identifier
    [type.position, { type: type.spelling, name: name.spelling, name_position: name.position }]
  end
  def parse
    @jobs, @values = [], []
    descend(:program, [])
    @jobs.pop.call until @jobs.empty?
    @values.pop
  end
  # Each recursive-descent call and its return continuation live on the heap.
  # A job schedules further work; it never invokes another grammar rule directly.
  def descend(rule, *arguments, &continuation)
    @jobs << -> { continuation.call(@values.pop) } if continuation
    @jobs << -> { public_send(rule, *arguments) }
  end
  def finish(value) = @values << value
  def program(declarations)
    return finish(declarations) if peek.kind == 'end'
    descend(:top_declaration) do |node|
      declarations << node
      descend(:program, declarations)
    end
  end
  def top_declaration
    position, fields = declaration_head
    if accept('(')
      parameters = []
      unless peek.spelling == ')'
        loop do
          parameter_position, parameter_fields = declaration_head
          parameters << Node.new('parameter', parameter_position, **parameter_fields)
          break unless accept(',')
        end
      end
      expect(')')
      descend(:block) { |body| finish(Node.new('function', position, **fields, parameters: parameters, body: body)) }
    elsif accept('[')
      fail_parse unless peek.kind == 'integer'
      token = take
      expect(']')
      expect(';')
      finish(Node.new('global', position, **fields, size: token.spelling.to_i, size_position: token.position))
    elsif accept('=')
      descend(:expression) do |initializer|
        expect(';')
        finish(Node.new('global', position, **fields, initializer: initializer))
      end
    else
      expect(';')
      finish(Node.new('global', position, **fields))
    end
  end
  def declaration(for_initial = false)
    position, fields = declaration_head
    initialized = for_initial ? expect('=') : accept('=')
    if initialized
      descend(:expression) do |initializer|
        expect(';') unless for_initial
        finish(Node.new('declaration', position, **fields, initializer: initializer))
      end
    else
      expect(';')
      finish(Node.new('declaration', position, **fields))
    end
  end
  def block
    opening = expect('{')
    descend(:block_contents, opening.position, [])
  end
  def block_contents(position, statements)
    if (closing = accept('}'))
      return finish(Node.new('block', position, statements: statements, end_position: closing.position))
    end
    descend(TYPES.include?(peek.spelling) ? :declaration : :statement) do |node|
      statements << node
      descend(:block_contents, position, statements)
    end
  end
  def statement
    token = peek
    case token.spelling
    when '{' then descend(:block)
    when 'if', 'while'
      take
      expect('(')
      descend(:expression) do |condition|
        expect(')')
        descend(:statement) do |body|
          if token.spelling == 'while'
            finish(Node.new('while', token.position, condition: condition, body: body))
          elsif accept('else')
            descend(:statement) do |otherwise|
              finish(Node.new('if', token.position, condition: condition, then_branch: body, otherwise: otherwise))
            end
          else
            finish(Node.new('if', token.position, condition: condition, then_branch: body))
          end
        end
      end
    when 'for'
      take
      expect('(')
      if TYPES.include?(peek.spelling)
        descend(:declaration, true) { |initial| descend(:for_condition, token.position, initial) }
      elsif peek.spelling != ';'
        descend(:simple) { |initial| descend(:for_condition, token.position, initial) }
      else
        descend(:for_condition, token.position, nil)
      end
    when 'break', 'continue'
      take
      expect(';')
      finish(Node.new(token.spelling, token.position))
    when 'return'
      take
      if accept(';')
        finish(Node.new('return', token.position))
      else
        descend(:expression) do |value|
          expect(';')
          finish(Node.new('return', token.position, value: value))
        end
      end
    when 'print'
      take
      expect('(')
      descend(:arguments, [], false) do |arguments|
        expect(';')
        finish(Node.new('print', token.position, arguments: arguments))
      end
    else
      fail_parse unless token.kind == 'identifier' || token.spelling == 'read'
      descend(:simple) do |result|
        expect(';')
        finish(result)
      end
    end
  end
  def for_condition(position, initial)
    expect(';')
    if peek.spelling == ';'
      descend(:for_update, position, initial, nil)
    else
      descend(:expression) { |condition| descend(:for_update, position, initial, condition) }
    end
  end
  def for_update(position, initial, condition)
    expect(';')
    if peek.spelling == ')'
      descend(:for_body, position, initial, condition, nil)
    else
      descend(:simple) { |update| descend(:for_body, position, initial, condition, update) }
    end
  end
  def for_body(position, initial, condition, update)
    expect(')')
    descend(:statement) { |body| finish(Node.new('for', position, initial: initial, condition: condition, update: update, body: body)) }
  end
  def simple
    fail_parse unless peek.kind == 'identifier' || peek.spelling == 'read'
    descend(:primary) do |value|
      if %w[call read].include?(value.kind)
        finish(Node.new('call_statement', value.position, expression: value))
      else
        expect('=')
        descend(:expression) do |right|
          finish(Node.new('assignment', value.position, name: value.name, index: value.index, value: right))
        end
      end
    end
  end
  def expression(level = 0)
    if level == OPERATORS.length
      if %w[- !].include?(peek.spelling)
        operator = take
        return descend(:expression, level) { |operand| finish(Node.new('unary', operator.position, operator: operator.spelling, operand: operand)) }
      end
      return descend(:primary)
    end
    descend(:expression, level + 1) { |result| descend(:binary_tail, level, result) }
  end
  def binary_tail(level, left)
    return finish(left) unless OPERATORS[level].include?(peek.spelling)
    operator = take
    descend(:expression, level + 1) do |right|
      descend(:binary_tail, level, Node.new('binary', operator.position, operator: operator.spelling, left: left, right: right))
    end
  end
  def primary
    token = peek
    if token.kind == 'integer'
      take
      return finish(Node.new('integer', token.position, value: token.spelling.to_i))
    elsif %w[true false].include?(token.spelling)
      take
      return finish(Node.new('boolean', token.position, value: token.spelling == 'true'))
    elsif accept('read')
      expect('(')
      expect(')')
      return finish(Node.new('read', token.position))
    elsif accept('(')
      return descend(:expression) do |result|
        expect(')')
        finish(result)
      end
    elsif token.kind == 'identifier'
      take
      if accept('(')
        return descend(:arguments, [], true) { |arguments| finish(Node.new('call', token.position, name: token.spelling, arguments: arguments)) }
      elsif accept('[')
        return descend(:expression) do |index|
          expect(']')
          finish(Node.new('array', token.position, name: token.spelling, index: index))
        end
      end
      return finish(Node.new('variable', token.position, name: token.spelling))
    end
    fail_parse
  end
  def arguments(values, allow_empty)
    if allow_empty && accept(')')
      return finish(values)
    end
    descend(:expression) do |value|
      values << value
      if accept(',')
        descend(:arguments, values, false)
      else
        expect(')')
        finish(values)
      end
    end
  end
end
