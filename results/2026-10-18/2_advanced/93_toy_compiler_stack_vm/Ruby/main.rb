require_relative 'lexer'
require_relative 'parser'
require_relative 'semantic'
require_relative 'codegen'
require_relative 'vm'

RULES = %w[const-jump not-compare not-jump invert-branch thread jump-next unreachable].freeze
PUSHING = %w[PUSH LOADG LOADL READ].freeze
POPPING = %w[POP STOREG STOREL JUMPF JUMPT RETV ADD SUB MUL DIV MOD LT LE GT GE EQ NE].freeze
REPORTS = %w[listing.txt output.txt diagnostics.txt stats.txt].freeze

def collect_warnings(analysis)
  warnings = analysis.variables.filter_map do |variable|
    role = variable.kind == 'parameter' ? 'parameter' : 'variable'
    [variable.name_position, "unused #{role} '#{variable.name}'"] if variable.read_accesses.zero?
  end
  analysis.functions.each do |function|
    pending = [function.body]
    until pending.empty?
      statement = pending.pop
      if statement.kind == 'block'
        statement.statements.each_cons(2) do |first, following|
          unless can_complete?(first)
            warnings << [following.position, 'unreachable statement']
            break
          end
        end
      end
      pending.concat(Tree.statement_children(statement))
    end
  end
  reachable, pending = Set.new, [analysis.globals.fetch('main')]
  until pending.empty?
    function = pending.pop
    next if reachable.include?(function)
    reachable << function
    pending.concat(function.calls.to_a)
  end
  analysis.functions.each do |function|
    warnings << [function.name_position, "function '#{function.name}' is never called"] unless reachable.include?(function)
  end
  [warnings.sort_by(&:first), reachable]
end

def recursive?(function)
  visited, pending = Set.new, function.calls.to_a
  until pending.empty?
    current = pending.pop
    return true if current.equal?(function)
    next if visited.include?(current)
    visited << current
    pending.concat(current.calls.to_a)
  end
  false
end

class Folder
  attr_reader :count
  def initialize = @count = 0
  def literal?(node, kind, value) = node.kind == kind && node.value == value
  def literal(node, value)
    @count += 1
    kind = node.type == 'bool' ? 'boolean' : 'integer'
    value = !value.zero? if kind == 'boolean' && value.is_a?(Integer)
    Node.new(kind, node.position, type: node.type, value: value)
  end
  def identity(node)
    @count += 1
    node
  end
  def as_integer(node) = node.kind == 'boolean' ? (node.value ? 1 : 0) : node.value
  def expression(node)
    folded, pending = {}, [[node, false]]
    until pending.empty?
      current, expanded = pending.pop
      unless expanded
        pending << [current, true]
        Tree.expression_children(current).reverse_each { |child| pending << [child, false] }
        next
      end
      case current.kind
      when 'unary' then current.operand = folded.fetch(current.operand)
      when 'binary' then current.left, current.right = folded.fetch(current.left), folded.fetch(current.right)
      when 'array' then current.index = folded.fetch(current.index)
      when 'call' then current.arguments = current.arguments.map { |argument| folded.fetch(argument) }
      end
      folded[current] = fold_expression(current)
    end
    folded.fetch(node)
  end
  def fold_expression(node)
    case node.kind
    when 'unary'
      if %w[integer boolean].include?(node.operand.kind)
        begin
          value = IntegerOperations.calculate(node.operator == '-' ? 'NEG' : 'NOT', as_integer(node.operand))
          return literal(node, value)
        rescue RuntimeFault
          return node
        end
      end
    when 'binary'
      left, right, operator = node.left, node.right, node.operator
      if %w[integer boolean].include?(left.kind) && %w[integer boolean].include?(right.kind)
        a, b = as_integer(left), as_integer(right)
        begin
          value = case operator
                  when '&&' then !a.zero? && !b.zero?
                  when '||' then !a.zero? || !b.zero?
                  else IntegerOperations.calculate(Bytecode::BINARY.fetch(operator), a, b)
                  end
          return literal(node, value)
        rescue RuntimeFault
          # An operation which would fail at runtime must remain in the code.
        end
      end
      return literal(node, false) if operator == '&&' && literal?(left, 'boolean', false)
      return literal(node, true) if operator == '||' && literal?(left, 'boolean', true)
      return identity(right) if operator == '&&' && literal?(left, 'boolean', true)
      return identity(right) if operator == '||' && literal?(left, 'boolean', false)
      return identity(right) if operator == '+' && literal?(left, 'integer', 0)
      return identity(right) if operator == '*' && literal?(left, 'integer', 1)
      return identity(left) if %w[+ -].include?(operator) && literal?(right, 'integer', 0)
      return identity(left) if %w[* /].include?(operator) && literal?(right, 'integer', 1)
      return identity(left) if operator == '&&' && literal?(right, 'boolean', true)
      return identity(left) if operator == '||' && literal?(right, 'boolean', false)
    end
    node
  end
  def statement(root)
    folded, pending = {}, [[:visit, root]]
    until pending.empty?
      action, node, selected = pending.pop
      if action == :replace
        folded[node] = selected ? folded.fetch(selected) : Node.new('empty', node.position)
        @count += 1
      elsif action == :condition
        node.condition = expression(node.condition) if node.condition
      elsif action == :finish
        case node.kind
        when 'block' then node.statements = node.statements.map { |child| folded.fetch(child) }
        when 'if'
          node.then_branch = folded.fetch(node.then_branch)
          node.otherwise = folded.fetch(node.otherwise) if node.otherwise
        when 'while' then node.body = folded.fetch(node.body)
        when 'for'
          node.initial = folded.fetch(node.initial) if node.initial
          node.update = folded.fetch(node.update) if node.update
          node.body = folded.fetch(node.body)
        end
        folded[node] = node
      else
        case node.kind
        when 'block'
          pending << [:finish, node]
          node.statements.reverse_each { |child| pending << [:visit, child] }
        when 'if'
          node.condition = expression(node.condition)
          if node.condition.kind == 'boolean'
            selected = node.condition.value ? node.then_branch : node.otherwise
            pending << [:replace, node, selected]
            pending << [:visit, selected] if selected
          else
            pending << [:finish, node]
            pending << [:visit, node.otherwise] if node.otherwise
            pending << [:visit, node.then_branch]
          end
        when 'while'
          node.condition = expression(node.condition)
          if literal?(node.condition, 'boolean', false)
            folded[node] = Node.new('empty', node.position)
            @count += 1
          else
            pending << [:finish, node]
            pending << [:visit, node.body]
          end
        when 'for'
          pending << [:finish, node]
          pending << [:visit, node.body]
          pending << [:visit, node.update] if node.update
          pending << [:condition, node]
          pending << [:visit, node.initial] if node.initial
        else
          fold_simple_statement(node)
          folded[node] = node
        end
      end
    end
    folded.fetch(root)
  end
  def fold_simple_statement(node)
    case node.kind
    when 'declaration' then node.initializer = expression(node.initializer) if node.initializer
    when 'assignment'
      node.index = expression(node.index) if node.index
      node.value = expression(node.value)
    when 'call_statement' then node.expression = expression(node.expression)
    when 'print' then node.arguments = node.arguments.map { |argument| expression(argument) }
    when 'return' then node.value = expression(node.value) if node.value
    end
  end
end

def jumps_on?(op, value) = value.zero? == (op == 'JUMPF')
def delete_instruction(code, position)
  code.delete_at(position)
  code.map! do |instruction|
    if Bytecode::JUMPS.include?(instruction.op) && instruction.args[0] > position
      Instruction.new(instruction.op, [instruction.args[0] - 1], instruction.position)
    else
      instruction
    end
  end
end
def rewrite_at(code, index, targets)
  first, second = code[index], code[index + 1]
  free = second && !targets.include?(index + 1)
  if free && first.op == 'PUSH' && Bytecode::CONDITIONAL.include?(second.op)
    if jumps_on?(second.op, first.args[0])
      code[index] = Instruction.new('JUMP', second.args, second.position)
      delete_instruction(code, index + 1)
    else
      delete_instruction(code, index + 1)
      delete_instruction(code, index)
    end
    return 1
  end
  if free && Bytecode::NEGATED.key?(first.op) && second.op == 'NOT'
    code[index] = Instruction.new(Bytecode::NEGATED.fetch(first.op), first.args, first.position)
    delete_instruction(code, index + 1)
    return 2
  end
  if free && first.op == 'NOT' && Bytecode::CONDITIONAL.include?(second.op)
    code[index] = Instruction.new(Bytecode::INVERSE.fetch(second.op), second.args, second.position)
    delete_instruction(code, index + 1)
    return 3
  end
  if free && Bytecode::CONDITIONAL.include?(first.op) && first.args[0] == index + 2 && second.op == 'JUMP'
    code[index] = Instruction.new(Bytecode::INVERSE.fetch(first.op), second.args, first.position)
    delete_instruction(code, index + 1)
    return 4
  end
  if Bytecode::JUMPS.include?(first.op)
    target = first.args[0]
    if target < code.length
      destination = code[target]
      new_target = nil
      if destination.op == 'JUMP'
        new_target = destination.args[0]
      elsif destination.op == 'PUSH' && target + 1 < code.length
        following = code[target + 1]
        if Bytecode::CONDITIONAL.include?(following.op)
          new_target = jumps_on?(following.op, destination.args[0]) ? following.args[0] : target + 2
        end
      end
      if new_target && new_target != target
        code[index] = Instruction.new(first.op, [new_target], first.position)
        return 5
      end
    end
    if target == index + 1
      if first.op == 'JUMP'
        delete_instruction(code, index)
      else
        code[index] = Instruction.new('POP', [], first.position)
      end
      return 6
    end
  end
  if free && Bytecode::TRANSFERS.include?(first.op)
    delete_instruction(code, index + 1)
    return 7
  end
  0
end
def optimize(original)
  code, counts = original.dup, Array.new(RULES.length, 0)
  loop do
    targets = code.filter_map { |instruction| instruction.args[0] if Bytecode::JUMPS.include?(instruction.op) }.to_set
    applied = false
    code.each_index do |index|
      rule = rewrite_at(code, index, targets)
      next if rule.zero?
      counts[rule - 1] += 1
      applied = true
      break
    end
    return [code, counts] unless applied
  end
end

def successors(code, index)
  instruction = code[index]
  result = []
  result << index + 1 if !Bytecode::TRANSFERS.include?(instruction.op) && index + 1 < code.length
  if Bytecode::JUMPS.include?(instruction.op)
    target = instruction.args[0]
    result << target if target < code.length && !result.include?(target)
  end
  result
end
def stack_effect(instruction, functions)
  op, args = instruction.op, instruction.args
  return 1 if PUSHING.include?(op)
  return -1 if POPPING.include?(op)
  return -2 if op == 'STOREA'
  return -args[1] + (functions.fetch(args[0]).type == 'void' ? 0 : 1) if op == 'CALL'
  return -args[0] if op == 'PRINT'
  0
end
def analyze_flow(unit, functions)
  code, leaders = unit.after, Set[0]
  code.each_with_index do |instruction, index|
    leaders << instruction.args[0] if Bytecode::JUMPS.include?(instruction.op) && instruction.args[0] < code.length
    if (Bytecode::JUMPS.include?(instruction.op) || Bytecode::TRANSFERS.include?(instruction.op)) && index + 1 < code.length
      leaders << index + 1
    end
  end
  starts = leaders.sort
  block_numbers = starts.each_with_index.to_h
  unit.blocks = starts.each_with_index.map do |start, number|
    ending = number + 1 < starts.length ? starts[number + 1] - 1 : code.length - 1
    [start, ending, successors(code, ending).map { |target| block_numbers.fetch(target) }]
  end
  depths, pending, maximum = { 0 => 0 }, [0], 0
  until pending.empty?
    index = pending.pop
    after = depths[index] + stack_effect(code[index], functions)
    maximum = [maximum, after].max
    successors(code, index).each do |target|
      next if depths.key?(target)
      depths[target] = after
      pending << target
    end
  end
  unit.depth = maximum
end
def link_units(units, version)
  addresses, offset = {}, 0
  units.each do |unit|
    addresses[unit.name] = offset
    unit.public_send("#{version}_start=", offset)
    offset += unit.public_send(version).length
  end
  code, owners = [], []
  units.each do |unit|
    unit.public_send(version).each do |instruction|
      args = instruction.args
      if Bytecode::JUMPS.include?(instruction.op)
        args = [addresses.fetch(unit.name) + args[0]]
      elsif instruction.op == 'CALL'
        args = [addresses.fetch(args[0]), args[1]]
      end
      code << Instruction.new(instruction.op, args, instruction.position)
      owners << unit.name
    end
  end
  [code, owners, addresses.invert]
end

class Program
  attr_accessor :inputs
  attr_reader :name, :lines, :source_text, :error, :warnings, :analysis, :globals, :units,
              :folds, :peephole, :before, :after, :owners, :execution, :comparison
  def initialize(name)
    @name, @lines, @inputs = name, [], []
    @error = nil
    @warnings, @folds, @peephole = [], 0, Array.new(RULES.length, 0)
  end
  def compile
    @source_text = @lines.to_h
    begin
      tokens = Lexer.tokenize(@lines)
      declarations = Parser.new(tokens).parse
      @analysis = Analyzer.new(declarations, tokens.last.position).analyze
    rescue CompileError => error
      @error = error
      return
    end
    @warnings, reachable = collect_warnings(@analysis)
    @globals = declarations.select { |node| node.kind == 'global' }
    functions = @analysis.functions.select { |function| reachable.include?(function) }
    folder = Folder.new
    @globals.each { |variable| variable.initializer = folder.expression(variable.initializer) if variable.initializer }
    functions.each { |function| function.body = folder.statement(function.body) }
    @folds = folder.count
    @units, global_size = Generator.generate(@globals, functions, @analysis.globals.fetch('main'))
    function_table = functions.to_h { |function| [function.name, function] }
    @units.each do |unit|
      unit.after, counts = optimize(unit.before)
      counts.each_with_index { |count, index| @peephole[index] += count }
      analyze_flow(unit, function_table)
      unit.recursive = unit.function && recursive?(unit.function)
    end
    @before, before_owners, before_starts = link_units(@units, 'before')
    @after, @owners, after_starts = link_units(@units, 'after')
    @execution = Execution.new(@after, @owners, after_starts, global_size, @inputs).run
    @comparison = Execution.new(@before, before_owners, before_starts, global_size, @inputs).run
  end
end

def spelling(instruction) = ([instruction.op] + instruction.args).join(' ')
def format_position(position) = position.join(':')
def position_display(program, position)
  line, column = position
  ['  ' + program.source_text.fetch(line), ' ' * (column + 1) + '^']
end
def listing(program)
  lines = []
  if program.globals.empty?
    lines << 'globals: none'
  else
    lines << 'globals:'
    program.globals.each do |variable|
      type = variable.size ? "int[#{variable.size}]" : variable.type
      lines << "  #{variable.address} #{variable.name} #{type}"
    end
  end
  lines << 'functions:'
  program.units.each do |unit|
    signature, callees = '', 'main'
    if unit.function
      signature = " #{unit.function.type}(#{unit.function.parameters.map(&:type).join(',')})"
      names = unit.function.calls.map(&:name).sort
      callees = names.empty? ? '-' : names.join(',')
    end
    line = "  #{unit.name}#{signature} address=#{unit.before_start}->#{unit.after_start}"
    line += " size=#{unit.before.length}->#{unit.after.length} slots=#{unit.slots.length}"
    line += " stack=#{unit.depth} blocks=#{unit.blocks.length} calls=#{callees}"
    line += ' recursive' if unit.recursive
    lines << line
    unit.slots.each_with_index { |slot, number| lines << "    slot #{number} #{slot.name} #{slot.type}" }
  end
  lines << 'references:'
  (program.globals + program.analysis.functions).each do |declaration|
    used = declaration.references.map(&:first).uniq.sort
    lines << "  #{declaration.name} defined #{declaration.name_position[0]} used #{used.empty? ? '-' : used.join(' ')}"
  end
  %w[before after].each do |version|
    code = program.public_send(version)
    lines << "#{version} peephole: #{code.length} instructions"
    program.units.each do |unit|
      lines << unit.name + ':'
      start = unit.public_send("#{version}_start")
      unit.public_send(version).length.times do |index|
        address = start + index
        lines << format('%5d  %s', address, spelling(code[address]))
      end
    end
  end
  lines << 'control flow:'
  program.units.each do |unit|
    lines << '  ' + unit.name
    unit.blocks.each_with_index do |(start, ending, following), number|
      line = "    B#{number} #{unit.after_start + start}-#{unit.after_start + ending}"
      line += ' -> ' + following.map { |target| "B#{target}" }.join(' ') unless following.empty?
      lines << line
    end
  end
  lines
end
def diagnostics(program)
  if program.error
    error = program.error
    return ["#{error.kind} error #{format_position(error.position)}: #{error.message}",
            *position_display(program, error.position), 'status: compile error']
  end
  lines = program.warnings.map { |position, message| "warning #{format_position(position)}: #{message}" }
  execution = program.execution
  unless execution.error
    return lines + ['status: ok']
  end
  instruction = program.after[execution.error_pc]
  owner = program.owners[execution.error_pc]
  lines << "runtime error #{format_position(instruction.position)}: #{execution.error} in #{owner}"
  lines.concat(position_display(program, instruction.position))
  callers = execution.frames.drop(1).reverse
  callers.first(5).each do |frame|
    address = frame.return_address - 1
    lines << "  called from #{program.owners[address]} at #{format_position(program.after[address].position)}"
  end
  lines << "  ... #{callers.length - 5} more" if callers.length > 5
  lines << 'status: runtime error'
end
def statistics(program)
  execution, comparison = program.execution, program.comparison
  same = execution.output == comparison.output && execution.error == comparison.error
  lines = ["code: #{program.before.length} -> #{program.after.length}", "folds: #{program.folds}", "peephole: #{program.peephole.sum}"]
  RULES.zip(program.peephole) { |rule, count| lines << "  #{rule} #{count}" }
  lines << "executed: #{execution.executed}"
  lines << "executed before peephole: #{comparison.executed}"
  lines << "behaviour: #{same ? 'same' : 'different'}"
  lines << "max call depth: #{execution.max_depth}"
  lines << "max stack: #{execution.max_stack}"
  opcodes, functions, source_lines = Hash.new(0), Hash.new(0), Hash.new(0)
  program.after.each_with_index do |instruction, address|
    count = execution.counts[address]
    opcodes[instruction.op] += count
    functions[program.owners[address]] += count
    source_lines[instruction.position[0]] += count
  end
  lines << 'opcodes:'
  opcodes.sort_by { |op, count| [-count, op] }.each { |op, count| lines << "  #{op} #{count}" if count.positive? }
  lines << 'functions:'
  names = program.units.select(&:function).map(&:name).sort_by { |name| [-functions[name], name] }
  names.each { |name| lines << "  #{name} calls=#{execution.calls[name]} executed=#{functions[name]}" }
  lines << 'calls:'
  execution.pairs.sort_by { |(caller, callee), count| [-count, caller, callee] }.each do |(caller, callee), count|
    lines << "  #{caller} -> #{callee} #{count}"
  end
  lines << 'hot lines:'
  executed_lines = source_lines.select { |_, count| count.positive? }.sort_by { |line, count| [-count, line] }
  executed_lines.first(5).each { |line, count| lines << "  line #{line}: #{count}" }
  lines << "coverage: #{executed_lines.length} of #{source_lines.length} lines"
  unexecuted = source_lines.select { |_, count| count.zero? }.keys.sort
  lines << 'not executed: ' + (unexecuted.empty? ? 'none' : unexecuted.join(' '))
  lines << 'hot spots:'
  hot_spots = execution.counts.each_with_index.filter_map { |count, address| [address, count] if count.positive? }
  hot_spots.sort_by { |address, count| [-count, address] }.first(5).each do |address, count|
    lines << "  pc=#{address} count=#{count} #{spelling(program.after[address])}"
  end
  lines
end
def summary(programs)
  compiled = programs.reject(&:error)
  errors = Hash.new(0)
  programs.each { |program| errors[program.error.kind] += 1 if program.error }
  peephole = RULES.each_index.map { |index| compiled.sum { |program| program.peephole[index] } }
  lines = ['== summary ==', "programs: #{programs.length}", "compiled: #{compiled.length}"]
  lines << "compile errors: lexical #{errors['lexical']} syntax #{errors['syntax']} semantic #{errors['semantic']}"
  lines << "runtime errors: #{compiled.count { |program| program.execution.error }}"
  lines << "folds: #{compiled.sum(&:folds)}"
  lines << "peephole: #{peephole.sum}"
  RULES.zip(peephole) { |rule, count| lines << "  #{rule} #{count}" }
  lines << "executed: #{compiled.sum { |program| program.execution.executed }}"
  rows = [%w[program status code executed output]]
  programs.each do |program|
    rows << if program.error
              [program.name, program.error.kind + ' error', '-', '-', '-']
            else
              execution = program.execution
              [program.name, execution.error ? 'runtime error' : 'ok', program.after.length.to_s,
               execution.executed.to_s, execution.output.length.to_s]
            end
  end
  widths = (0...5).map { |column| rows.map { |row| row[column].length }.max }
  rows.each do |row|
    fields = row.each_with_index.map { |value, index| index < 2 ? value.ljust(widths[index]) : value.rjust(widths[index]) }
    lines << '  ' + fields.join('  ')
  end
  lines
end
def read_programs
  programs = []
  File.foreach('input/program.src', encoding: 'ASCII').with_index(1) do |raw, number|
    line = raw.chomp
    if line.start_with?('#program ')
      programs << Program.new(line.delete_prefix('#program '))
    else
      programs.last.lines << [number, line]
    end
  end
  by_name = programs.to_h { |program| [program.name, program] }
  current = nil
  File.foreach('input/input.txt', encoding: 'ASCII') do |raw|
    line = raw.chomp
    if line.start_with?('#input ')
      current = by_name.fetch(line.delete_prefix('#input '))
    else
      current.inputs.concat(line.split(' ').map(&:to_i))
    end
  end
  programs
end
if $PROGRAM_NAME == __FILE__
  programs = read_programs
  reports = REPORTS.to_h { |name| [name, []] }
  programs.each do |program|
    program.compile
    reports.each_value { |lines| lines << "== program #{program.name} ==" }
    reports['diagnostics.txt'].concat(diagnostics(program))
    if program.error
      reports['listing.txt'] << 'not compiled'
      reports['stats.txt'] << 'not compiled'
    else
      reports['listing.txt'].concat(listing(program))
      reports['output.txt'].concat(program.execution.output)
      reports['stats.txt'].concat(statistics(program))
    end
  end
  reports['stats.txt'].concat(summary(programs))
  reports.each { |name, lines| File.write(File.join('output', name), lines.join("\n") + "\n") }
end
