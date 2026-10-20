Instruction = Struct.new(:op, :args, :position)
Label = Struct.new(:position)
Unit = Struct.new(:name, :function, :slots, :before, :after, :blocks, :depth, :recursive, :before_start, :after_start)
module Bytecode
  BINARY = { '+' => 'ADD', '-' => 'SUB', '*' => 'MUL', '/' => 'DIV', '%' => 'MOD',
             '<' => 'LT', '<=' => 'LE', '>' => 'GT', '>=' => 'GE', '==' => 'EQ', '!=' => 'NE' }.freeze
  JUMPS = %w[JUMP JUMPF JUMPT].freeze
  CONDITIONAL = %w[JUMPF JUMPT].freeze
  TRANSFERS = %w[JUMP RET RETV HALT].freeze
  NEGATED = { 'LT' => 'GE', 'LE' => 'GT', 'GT' => 'LE', 'GE' => 'LT', 'EQ' => 'NE', 'NE' => 'EQ' }.freeze
  INVERSE = { 'JUMPF' => 'JUMPT', 'JUMPT' => 'JUMPF' }.freeze
end
class Generator
  include Bytecode
  def initialize
    @code, @loops = [], []
  end
  def emit(op, position, *args) = @code << Instruction.new(op, args, position)
  def mark(label) = label.position = @code.length
  def finish
    @code.map do |instruction|
      args = JUMPS.include?(instruction.op) ? [instruction.args[0].position] : instruction.args
      Instruction.new(instruction.op, args, instruction.position)
    end
  end
  def expression(node) = generate_tree(:expression, node)
  def statement(node) = generate_tree(:statement, node)
  def instruction(op, position, *args) = [:emit, op, position, *args]
  def generate_tree(kind, root)
    pending = [[kind, root]]
    until pending.empty?
      action, *arguments = pending.pop
      case action
      when :emit then emit(*arguments)
      when :mark then mark(arguments[0])
      when :loop then @loops << arguments
      when :end_loop then @loops.pop
      else
        tasks = action == :expression ? expression_tasks(arguments[0]) : statement_tasks(arguments[0])
        pending.concat(tasks.reverse)
      end
    end
  end
  def expression_tasks(node)
    position = node.position
    case node.kind
    when 'integer' then [instruction('PUSH', position, node.value)]
    when 'boolean' then [instruction('PUSH', position, node.value ? 1 : 0)]
    when 'variable'
      referent = node.referent
      [instruction(referent.kind == 'global' ? 'LOADG' : 'LOADL', position, referent.kind == 'global' ? referent.address : referent.slot)]
    when 'array'
      [[:expression, node.index], instruction('LOADA', position, node.referent.address, node.referent.size)]
    when 'read' then [instruction('READ', position)]
    when 'call'
      node.arguments.map { |argument| [:expression, argument] } + [instruction('CALL', position, node.referent.name, node.arguments.length)]
    when 'unary'
      [[:expression, node.operand], instruction(node.operator == '-' ? 'NEG' : 'NOT', position)]
    when 'binary'
      if %w[&& ||].include?(node.operator)
        shortcut, ending = Label.new, Label.new
        [[:expression, node.left], instruction(node.operator == '&&' ? 'JUMPF' : 'JUMPT', position, shortcut),
         [:expression, node.right], instruction('JUMP', position, ending), [:mark, shortcut],
         instruction('PUSH', position, node.operator == '||' ? 1 : 0), [:mark, ending]]
      else
        [[:expression, node.left], [:expression, node.right], instruction(BINARY.fetch(node.operator), position)]
      end
    end
  end
  def statement_tasks(node)
    position = node.position
    case node.kind
    when 'declaration'
      [node.initializer ? [:expression, node.initializer] : instruction('PUSH', node.name_position, 0),
       instruction('STOREL', node.name_position, node.slot)]
    when 'assignment'
      tasks = node.index ? [[:expression, node.index]] : []
      tasks << [:expression, node.value]
      referent = node.referent
      if node.index
        tasks << instruction('STOREA', position, referent.address, referent.size)
      elsif referent.kind == 'global'
        tasks << instruction('STOREG', position, referent.address)
      else
        tasks << instruction('STOREL', position, referent.slot)
      end
      tasks
    when 'call_statement'
      tasks = [[:expression, node.expression]]
      tasks << instruction('POP', position) unless node.expression.type == 'void'
      tasks
    when 'print'
      node.arguments.map { |argument| [:expression, argument] } + [instruction('PRINT', position, node.arguments.length)]
    when 'if'
      alternative, ending = Label.new, Label.new
      tasks = [[:expression, node.condition], instruction('JUMPF', position, alternative), [:statement, node.then_branch]]
      if node.otherwise
        tasks.concat([instruction('JUMP', position, ending), [:mark, alternative], [:statement, node.otherwise], [:mark, ending]])
      else
        tasks << [:mark, alternative]
      end
      tasks
    when 'while'
      start, ending = Label.new, Label.new
      [[:mark, start], [:expression, node.condition], instruction('JUMPF', position, ending),
       [:loop, ending, start], [:statement, node.body], [:end_loop], instruction('JUMP', position, start), [:mark, ending]]
    when 'for'
      start, update, ending = Label.new, Label.new, Label.new
      tasks = node.initial ? [[:statement, node.initial]] : []
      tasks << [:mark, start]
      if node.condition
        tasks.concat([[:expression, node.condition], instruction('JUMPF', position, ending)])
      end
      tasks.concat([[:loop, ending, update], [:statement, node.body], [:end_loop], [:mark, update]])
      tasks << [:statement, node.update] if node.update
      tasks.concat([instruction('JUMP', position, start), [:mark, ending]])
    when 'break', 'continue' then [instruction('JUMP', position, @loops.last[node.kind == 'continue' ? 1 : 0])]
    when 'return'
      tasks = node.value ? [[:expression, node.value]] : []
      tasks << instruction(node.value ? 'RETV' : 'RET', position)
    when 'block' then node.statements.map { |child| [:statement, child] }
    else []
    end
  end
  def self.assign_slots(function)
    declarations, pending = [], [function.body]
    until pending.empty?
      node = pending.pop
      declarations << node if node.kind == 'declaration'
      pending.concat(Tree.statement_children(node))
    end
    slots = function.parameters + declarations.sort_by(&:name_position)
    slots.each_with_index { |declaration, index| declaration.slot = index }
    slots
  end
  def self.generate(globals, functions, main)
    address = 0
    globals.each do |variable|
      variable.address = address
      address += variable.size || 1
    end
    initialization = new
    globals.each do |variable|
      next unless variable.initializer
      initialization.expression(variable.initializer)
      initialization.emit('STOREG', variable.name_position, variable.address)
    end
    initialization.emit('CALL', main.name_position, 'main', 0)
    initialization.emit('HALT', main.name_position)
    units = [Unit.new('<init>', nil, [], initialization.finish)]
    functions.each do |function|
      slots = assign_slots(function)
      generator = new
      generator.emit('ENTER', function.name_position, slots.length)
      generator.statement(function.body)
      generator.emit('RET', function.body.end_position) if function.type == 'void'
      units << Unit.new(function.name, function, slots, generator.finish)
    end
    [units, address]
  end
end
