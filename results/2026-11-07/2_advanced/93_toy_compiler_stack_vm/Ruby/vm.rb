class RuntimeFault < StandardError; end
Frame = Struct.new(:locals, :return_address)
module IntegerOperations
  BINARY = %w[ADD SUB MUL DIV MOD LT LE GT GE EQ NE].freeze
  module_function
  def trunc_div(a, b)
    quotient = a.abs / b.abs
    a.negative? != b.negative? ? -quotient : quotient
  end
  def calculate(op, a, b = nil)
    raise RuntimeFault, 'division by zero' if %w[DIV MOD].include?(op) && b.zero?
    result = case op
             when 'ADD' then a + b
             when 'SUB' then a - b
             when 'MUL' then a * b
             when 'DIV' then trunc_div(a, b)
             when 'MOD' then a - trunc_div(a, b) * b
             when 'NEG' then -a
             when 'NOT' then a.zero? ? 1 : 0
             when 'LT' then a < b ? 1 : 0
             when 'LE' then a <= b ? 1 : 0
             when 'GT' then a > b ? 1 : 0
             when 'GE' then a >= b ? 1 : 0
             when 'EQ' then a == b ? 1 : 0
             when 'NE' then a != b ? 1 : 0
             end
    raise RuntimeFault, 'integer overflow' unless (-2_147_483_648..2_147_483_647).cover?(result)
    result
  end
end

class Execution
  attr_reader :executed, :counts, :calls, :pairs, :max_stack, :max_depth, :output, :error, :error_pc, :frames
  def initialize(code, owners, starts, global_size, inputs)
    @code, @owners, @starts, @inputs = code, owners, starts, inputs
    @globals = Array.new(global_size, 0)
    @stack, @frames, @output = [], [], []
    @read_position = @pc = @executed = @max_stack = @max_depth = 0
    @counts = Array.new(code.length, 0)
    @calls, @pairs = Hash.new(0), Hash.new(0)
    @error = @error_pc = nil
  end
  def step
    instruction = @code[@pc]
    op, args = instruction.op, instruction.args
    next_pc = @pc + 1
    case op
    when 'PUSH' then @stack << args[0]
    when 'POP' then @stack.pop
    when 'LOADG' then @stack << @globals[args[0]]
    when 'STOREG' then @globals[args[0]] = @stack.pop
    when 'LOADL' then @stack << @frames.last.locals[args[0]]
    when 'STOREL' then @frames.last.locals[args[0]] = @stack.pop
    when 'LOADA', 'STOREA'
      value = @stack.pop if op == 'STOREA'
      index = @stack.pop
      address, size = args
      if index.negative? || index >= size
        raise RuntimeFault, "index #{index} out of bounds for array of size #{size}"
      end
      if op == 'LOADA'
        @stack << @globals[address + index]
      else
        @globals[address + index] = value
      end
    when *IntegerOperations::BINARY
      b, a = @stack.pop, @stack.pop
      @stack << IntegerOperations.calculate(op, a, b)
    when 'NEG', 'NOT' then @stack << IntegerOperations.calculate(op, @stack.pop)
    when 'JUMP' then next_pc = args[0]
    when 'JUMPF', 'JUMPT'
      next_pc = args[0] if @stack.pop.zero? == (op == 'JUMPF')
    when 'CALL'
      raise RuntimeFault, 'call depth limit exceeded' if @frames.length == 100
      target, count = args
      @frames << Frame.new(@stack.pop(count), next_pc)
      callee = @starts.fetch(target)
      @calls[callee] += 1
      @pairs[[@owners[@pc], callee]] += 1
      next_pc = target
    when 'ENTER'
      locals = @frames.last.locals
      locals.concat(Array.new(args[0] - locals.length, 0))
    when 'RET', 'RETV' then next_pc = @frames.pop.return_address
    when 'READ'
      raise RuntimeFault, 'read past end of input' if @read_position == @inputs.length
      @stack << @inputs[@read_position]
      @read_position += 1
    when 'PRINT' then @output << @stack.pop(args[0]).join(' ')
    end
    @max_stack = [@max_stack, @stack.length].max
    @max_depth = [@max_depth, @frames.length].max
    @pc = next_pc
    op != 'HALT'
  end
  def run
    loop do
      if @executed == 100_000
        @error, @error_pc = 'instruction limit exceeded', @pc
        break
      end
      @executed += 1
      @counts[@pc] += 1
      begin
        break unless step
      rescue RuntimeFault => error
        @error, @error_pc = error.message, @pc
        break
      end
    end
    self
  end
end
