require_relative 'lexer'

Node = Struct.new(:kind, :children, :value, :column) do
  def initialize(kind, children = [], value = nil, column = 0)
    super(kind, children, value, column)
  end
end

class Parser
  ATOMS = %w[identifier number symbol command text].freeze
  TERMINATORS = ['}', '&', 'newline', 'right', 'end', 'eof'].freeze
  ARGUMENTS = (ATOMS + ['eqref', '{', 'frac', 'binom', 'overset', 'underset', 'sqrt', 'accent']).freeze
  UNEXPECTED = { 'right' => 'unexpected \\right', 'end' => 'unexpected \\end',
                 '&' => 'misplaced &', 'newline' => 'misplaced \\\\' }.freeze
  attr_reader :tag, :label

  def self.check_braces(tokens)
    stack = []
    tokens.each do |token|
      if token.kind == '{'
        stack << token.column
      elsif token.kind == '}'
        raise Lexer::FormulaError.new(token.column, 'unmatched }') if stack.empty?
        stack.pop
      end
    end
    raise Lexer::FormulaError.new(stack[-1], 'unclosed {') unless stack.empty?
  end

  def initialize(tokens)
    @tokens, @position = tokens, 0
  end

  def peek
    @tokens[@position]
  end

  def take
    token = peek
    @position += 1 unless token.kind == 'eof'
    token
  end

  def fail_at(column, message)
    raise Lexer::FormulaError.new(column, message)
  end

  def unexpected
    fail_at(peek.column, UNEXPECTED.fetch(peek.kind))
  end

  def collapse(nodes)
    nodes.size == 1 ? nodes[0] : Node.new('row', nodes)
  end

  def parse
    nodes = element_list(top: true)
    unexpected unless peek.kind == 'eof'
    nodes
  end

  def element_list(top: false, index: false)
    nodes = []
    loop do
      token = peek
      return nodes if TERMINATORS.include?(token.kind) || (index && token.kind == 'symbol' && token.value == ']')
      if %w[tag label].include?(token.kind)
        fail_at(token.column, 'misplaced \\' + token.kind) unless top
        fail_at(token.column, 'duplicate \\' + token.kind) if instance_variable_get('@' + token.kind)
        instance_variable_set('@' + token.kind, take)
      else
        nodes << element
      end
    end
  end

  def element
    base = %w[^ _].include?(peek.kind) ? Node.new('row') : nucleus
    sub = sup = nil
    while %w[^ _].include?(peek.kind)
      token = take
      if token.kind == '^'
        fail_at(token.column, 'double superscript') if sup
        sup = argument('^')
      else
        fail_at(token.column, 'double subscript') if sub
        sub = argument('_')
      end
    end
    (sub || sup) ? Node.new('script', [base, sub, sup]) : base
  end

  def argument(name)
    fail_at(peek.column, 'missing argument for ' + name) unless ARGUMENTS.include?(peek.kind)
    nucleus
  end

  def delimiter
    token = take
    return token.value if token.kind == 'symbol' && ['(', ')', '[', ']', '|', '.'].include?(token.value)
    return token.value if token.kind == 'command' && ['\\{', '\\}'].include?(token.value)
    fail_at(token.column, 'invalid delimiter')
  end

  def nucleus
    token = take
    kind = token.kind
    return Node.new(kind, [], token.value, token.column) if ATOMS.include?(kind)
    case kind
    when 'eqref'
      Node.new('reference', [], token.value, token.column)
    when '{'
      nodes = element_list
      unexpected unless peek.kind == '}'
      take
      collapse(nodes)
    when 'frac', 'binom', 'overset', 'underset'
      first = argument('\\' + kind)
      second = argument('\\' + kind)
      Node.new(kind, [first, second])
    when 'sqrt'
      index = nil
      if peek.kind == 'symbol' && peek.value == '['
        opening = take
        nodes = element_list(index: true)
        fail_at(opening.column, 'missing ]') unless peek.kind == 'symbol' && peek.value == ']'
        take
        index = collapse(nodes)
      end
      body = argument('\\sqrt')
      index ? Node.new('root', [index, body]) : Node.new('sqrt', [body])
    when 'accent'
      Node.new('accent', [argument('\\' + token.value)], token.value)
    when 'left'
      left = delimiter
      nodes = element_list
      fail_at(token.column, 'missing \\right') unless peek.kind == 'right'
      closing = take
      right = delimiter
      Node.new('delim', [collapse(nodes)], [left, right], closing.column)
    when 'begin'
      matrix(token.value, token.column)
    end
  end

  def matrix(environment, column)
    rows = [[]]
    loop do
      rows[-1] << collapse(element_list)
      token = take
      next if token.kind == '&'
      if token.kind == 'newline'
        rows << []
        next
      end
      fail_at(column, 'missing \\end') unless token.kind == 'end'
      fail_at(token.column, 'mismatched \\end') unless token.value == environment
      break
    end
    last = rows[-1]
    rows.pop if rows.size >= 2 && last.size == 1 && last[0].kind == 'row' && last[0].children.empty?
    columns = rows.map(&:size).max
    rows.each { |row| row << Node.new('row') while row.size < columns }
    Node.new('matrix', rows, environment)
  end
end
