Token = Struct.new(:kind, :text, :line, :sign)
Procedure = Struct.new(:name, :parameters, :line, :tokens, :body)

class LogoError < StandardError
  attr_reader :line, :calls

  def initialize(line, reason, calls = [])
    super(reason)
    @line, @calls = line, calls
  end
end

class LogoReturn < StandardError
  attr_reader :value

  def initialize(value)
    @value = value
  end
end

module Language
  COMMANDS = {
    'FD' => ['FD', 'E'], 'FORWARD' => ['FD', 'E'], 'BK' => ['BK', 'E'], 'BACK' => ['BK', 'E'],
    'RT' => ['RT', 'E'], 'RIGHT' => ['RT', 'E'], 'LT' => ['LT', 'E'], 'LEFT' => ['LT', 'E'],
    'SETH' => ['SETH', 'E'], 'SETHEADING' => ['SETH', 'E'],
    'PU' => ['PU', ''], 'PENUP' => ['PU', ''], 'PD' => ['PD', ''], 'PENDOWN' => ['PD', ''],
    'PE' => ['PE', ''], 'PENERASE' => ['PE', ''], 'SETPEN' => ['SETPEN', 'E'],
    'SETXY' => ['SETXY', 'EE'], 'SETX' => ['SETX', 'E'], 'SETY' => ['SETY', 'E'],
    'HOME' => ['HOME', ''], 'CS' => ['CS', ''], 'CLEARSCREEN' => ['CS', ''],
    'CLEAN' => ['CLEAN', ''], 'FILL' => ['FILL', ''], 'LABEL' => ['LABEL', 'P'],
    'SNAPSHOT' => ['SNAPSHOT', ''], 'REPEAT' => ['REPEAT', 'EL'], 'FOR' => ['FOR', 'QEEL'],
    'WHILE' => ['WHILE', 'EL'], 'IF' => ['IF', 'EL'], 'IFELSE' => ['IFELSE', 'ELL'],
    'TEST' => ['TEST', 'E'], 'IFTRUE' => ['IFTRUE', 'L'], 'IFT' => ['IFTRUE', 'L'],
    'IFFALSE' => ['IFFALSE', 'L'], 'IFF' => ['IFFALSE', 'L'], 'STOP' => ['STOP', ''],
    'OUTPUT' => ['OUTPUT', 'E'], 'OP' => ['OUTPUT', 'E'], 'MAKE' => ['MAKE', 'QE'],
    'LOCAL' => ['LOCAL', 'Q'], 'LOCALMAKE' => ['LOCALMAKE', 'QE'],
    'TRACE' => ['TRACE', 'Q'], 'UNTRACE' => ['UNTRACE', 'Q'], 'SEED' => ['SEED', 'E'],
    'PRINT' => ['PRINT', 'P'], 'PR' => ['PRINT', 'P']
  }.freeze
  FUNCTIONS = { 'XCOR' => 0, 'YCOR' => 0, 'HEADING' => 0, 'REPCOUNT' => 0, 'RANDOM' => 1,
                'ABS' => 1, 'NOT' => 1, 'AND' => 2, 'OR' => 2, 'MAX' => 2, 'MIN' => 2 }.freeze

  def self.primitive?(name)
    COMMANDS.key?(name) || FUNCTIONS.key?(name) || %w[TO END MOD].include?(name)
  end

  def self.lex(line, number)
    text = (line.split(';', 2).first || '').upcase
    tokens = []
    i = 0
    while i < text.length
      char = text[i]
      if char == ' '
        i += 1
      elsif '[]()+*/=-<>'.include?(char)
        spelling = char
        spelling += text[i + 1] if (char == '<' && %w[= >].include?(text[i + 1])) || (char == '>' && text[i + 1] == '=')
        sign = char == '-' && (i.zero? || [' ', '[', '('].include?(text[i - 1])) && i + 1 < text.length && text[i + 1] != ' '
        tokens << Token.new(:symbol, spelling, number, sign)
        i += spelling.length
      else
        start = i
        i += 1 while i < text.length && !' []()+-*/=<>'.include?(text[i])
        spelling = text[start...i]
        kind = if /\A[0-9]+\z/.match?(spelling)
                 :number
               elsif /\A:[A-Z][A-Z0-9_]*\z/.match?(spelling)
                 :variable
               elsif /\A"[A-Z][A-Z0-9_]*\z/.match?(spelling)
                 :quote
               elsif /\A[A-Z][A-Z0-9_]*\z/.match?(spelling)
                 :word
               end
        raise LogoError.new(number, "bad token '#{spelling}'") unless kind
        tokens << Token.new(kind, spelling, number, false)
      end
    end
    tokens
  end
end

class Parser
  def initialize(tokens, procedures, top)
    @tokens, @procedures, @top, @index = tokens, procedures, top, 0
  end

  def peek
    @tokens[@index]
  end

  def read
    token = peek
    @index += 1
    token
  end

  def error(token, reason)
    raise LogoError.new(token.line, reason)
  end

  def unknown?(token)
    token.kind == :word && !Language.primitive?(token.text) && !@procedures.key?(token.text)
  end

  def need(owner)
    token = peek
    error(owner, "not enough inputs to #{owner.text}") if token.nil? || [']', ')'].include?(token.text)
    error(token, "I don't know how to #{token.text}") if unknown?(token)
    token
  end

  def input(kind, owner)
    token = need(owner)
    if kind == 'L'
      error(token, "#{owner.text} doesn't like #{token.text} as input") unless token.text == '['
      opening = read
      result = []
      loop do
        error(opening, 'missing ]') unless peek
        break if peek.text == ']'
        result << command
      end
      read
      result
    elsif kind == 'Q'
      error(token, "#{owner.text} doesn't like #{token.text} as input") unless token.kind == :quote
      read
    elsif kind == 'P' && token.kind == :quote
      { kind: :quote, value: read.text[1..] }
    else
      expression(owner)
    end
  end

  def sequence
    result = []
    result << command while peek
    result
  end

  def command
    token = read
    error(token, 'unexpected ]') if token.text == ']'
    if token.text == '(' && peek && %w[PRINT PR].include?(peek.text)
      owner = read
      args = []
      loop do
        error(token, 'missing )') if peek.nil? || peek.text == ']'
        break if peek.text == ')'
        args << input('P', owner)
      end
      read
      return { name: 'MULTIPRINT', token: owner, args: args }
    end
    error(token, "misplaced #{token.text}") if token.kind == :word && %w[TO END].include?(token.text)
    if token.kind == :word && Language::COMMANDS.key?(token.text)
      name, kinds = Language::COMMANDS[token.text]
      if @top && %w[STOP OUTPUT OP LOCAL LOCALMAKE].include?(token.text)
        error(token, "can only use #{token.text} inside a procedure")
      end
      args = kinds.each_char.map { |kind| input(kind, token) }
      if %w[TRACE UNTRACE].include?(name) && !@procedures.key?(args[0].text[1..])
        error(args[0], "I don't know how to #{args[0].text[1..]}")
      end
      { name: name, token: token, args: args }
    elsif token.kind == :word && @procedures.key?(token.text)
      args = Array.new(@procedures[token.text].parameters.length) { expression(token) }
      { name: :call, token: token, args: args }
    elsif unknown?(token)
      error(token, "I don't know how to #{token.text}")
    else
      error(token, "you don't say what to do with #{token.text}")
    end
  end

  def expression(owner)
    binary(owner, :sum, %w[= <> < > <= >=])
  end

  def sum(owner)
    binary(owner, :product, %w[+ -])
  end

  def product(owner)
    binary(owner, :term, %w[* / MOD])
  end

  def binary(owner, lower, operators)
    left = send(lower, owner)
    while peek && operators.include?(peek.text) && !(peek.text == '-' && peek.sign)
      operator = read
      right = send(lower, operator)
      left = { kind: :binary, token: operator, left: left, right: right }
    end
    left
  end

  def term(owner)
    token = need(owner)
    read
    case token.kind
    when :number
      return { kind: :number, value: token.text.to_i }
    when :variable
      return { kind: :variable, token: token }
    end
    if token.text == '-'
      { kind: :unary, value: term(token) }
    elsif token.text == '('
      value = expression(token)
      error(token, 'missing )') unless peek && peek.text == ')'
      read
      value
    elsif token.kind == :word && Language::FUNCTIONS.key?(token.text)
      { kind: :function, token: token, args: Array.new(Language::FUNCTIONS[token.text]) { expression(token) } }
    elsif token.kind == :word && @procedures.key?(token.text)
      { kind: :call, token: token, args: Array.new(@procedures[token.text].parameters.length) { expression(token) } }
    else
      error(token, "#{owner.text} doesn't like #{token.text} as input")
    end
  end
end

class Turtle
  DIRECTIONS = [[0, 1], [1, 1], [1, 0], [1, -1], [0, -1], [-1, -1], [-1, 0], [-1, 1]].freeze

  def initialize(procedures)
    @procedures = procedures
    @x = @y = @heading = 0
    @pen = 'DOWN'
    @character = '*'
    @canvas = {}
    @environments = [{ variables: {}, test: nil }]
    @calls = []
    @repetitions = []
    @traced = {}
    @random = 1
  end

  def error(token, reason)
    raise LogoError.new(token.line, reason, @calls.dup)
  end

  def quotient(a, b)
    value = a.abs / b.abs
    (a.negative? != b.negative?) ? -value : value
  end

  def value(node)
    case node[:kind]
    when :number, :quote
      node[:value]
    when :variable
      name = node[:token].text[1..]
      environment = @environments.reverse.find { |e| e[:variables].key?(name) }
      error(node[:token], "#{name} has no value") unless environment
      environment[:variables][name]
    when :unary
      -value(node[:value])
    when :binary
      a = value(node[:left])
      b = value(node[:right])
      operator = node[:token].text
      error(node[:token], "#{operator} doesn't like 0 as input") if %w[/ MOD].include?(operator) && b.zero?
      case operator
      when '+' then a + b
      when '-' then a - b
      when '*' then a * b
      when '/' then quotient(a, b)
      when 'MOD' then a - b * quotient(a, b)
      when '=' then a == b ? 1 : 0
      when '<>' then a != b ? 1 : 0
      when '<' then a < b ? 1 : 0
      when '>' then a > b ? 1 : 0
      when '<=' then a <= b ? 1 : 0
      when '>=' then a >= b ? 1 : 0
      end
    when :call
      result = call(node[:token], node[:args])
      error(node[:token], "#{node[:token].text} did not output") if result.nil?
      result
    when :function
      args = node[:args].map { |arg| value(arg) }
      token = node[:token]
      a, b = args
      case token.text
      when 'XCOR' then @x
      when 'YCOR' then @y
      when 'HEADING' then @heading
      when 'REPCOUNT'
        error(token, 'REPCOUNT outside REPEAT') if @repetitions.empty?
        @repetitions.last
      when 'RANDOM'
        error(token, "RANDOM doesn't like #{a} as input") unless a.positive?
        @random = 48_271 * @random % 2_147_483_647
        @random % a
      when 'ABS' then a.abs
      when 'NOT' then a.zero? ? 1 : 0
      when 'AND' then !a.zero? && !b.zero? ? 1 : 0
      when 'OR' then !a.zero? || !b.zero? ? 1 : 0
      when 'MAX' then [a, b].max
      when 'MIN' then [a, b].min
      end
    end
  end

  def call(token, arguments)
    inputs = arguments.map { |arg| value(arg) }
    error(token, 'recursion too deep') if @calls.length == 100
    procedure = @procedures[token.text]
    traced = @traced[token.text]
    indent = '  ' * @calls.length
    puts indent + '( ' + ([token.text] + inputs.map(&:to_s)).join(' ') + ' )' if traced
    @calls << token.text
    @environments << { variables: procedure.parameters.zip(inputs).to_h, test: nil }
    result = nil
    begin
      execute(procedure.body)
    rescue LogoReturn => signal
      result = signal.value
    ensure
      @environments.pop
      @calls.pop
    end
    puts indent + token.text + (result.nil? ? ' stops' : " outputs #{result}") if traced
    result
  end

  def make(name, number)
    environment = @environments.drop(1).reverse.find { |e| e[:variables].key?(name) } || @environments.first
    environment[:variables][name] = number
  end

  def apply(x, y)
    if @pen == 'DOWN'
      @canvas[[x, y]] = @character
    elsif @pen == 'ERASE'
      @canvas.delete([x, y])
    end
  end

  def move(number)
    dx, dy = DIRECTIONS[@heading / 45]
    if number.negative?
      dx = -dx
      dy = -dy
    end
    apply(@x, @y)
    number.abs.times do
      @x += dx
      @y += dy
      apply(@x, @y)
    end
  end

  def move_to(x, y)
    dx, dy = x - @x, y - @y
    steps = [dx.abs, dy.abs].max
    if steps.zero?
      apply(@x, @y)
    else
      (0..steps).each { |i| apply(@x + (2 * i * dx + steps).div(2 * steps), @y + (2 * i * dy + steps).div(2 * steps)) }
    end
    @x, @y = x, y
  end

  def fill
    return if @canvas.empty? || @canvas.key?([@x, @y])
    xs, ys = @canvas.keys.transpose
    x1, x2 = xs.minmax
    y1, y2 = ys.minmax
    return unless (x1..x2).cover?(@x) && (y1..y2).cover?(@y)
    queue = [[@x, @y]]
    @canvas[[@x, @y]] = @character
    head = 0
    while head < queue.length
      x, y = queue[head]
      head += 1
      [[x - 1, y], [x + 1, y], [x, y - 1], [x, y + 1]].each do |point|
        a, b = point
        next if a < x1 || a > x2 || b < y1 || b > y2 || @canvas.key?(point)
        @canvas[point] = @character
        queue << point
      end
    end
  end

  def snapshot
    if @canvas.empty?
      puts 'CANVAS 0 0 0'
      return
    end
    xs, ys = @canvas.keys.transpose
    x1, x2 = xs.minmax
    y1, y2 = ys.minmax
    puts "CANVAS #{x2 - x1 + 1} #{y2 - y1 + 1} #{@canvas.length}"
    y2.downto(y1) { |y| puts (x1..x2).map { |x| @canvas[[x, y]] || ' ' }.join.sub(/ +\z/, '') }
  end

  def execute(commands)
    commands.each do |command|
      token = command[:token]
      args = command[:args]
      name = command[:name]
      if name == :call
        result = call(token, args)
        error(token, "you don't say what to do with #{result}") unless result.nil?
        next
      end
      if name == 'WHILE'
        until value(args[0]).zero?
          execute(args[1])
        end
        next
      end
      values = args.map { |arg| arg.is_a?(Array) ? arg : arg.is_a?(Token) ? arg.text[1..] : value(arg) }
      a, b, c, d = values
      case name
      when 'FD' then move(a)
      when 'BK' then move(-a)
      when 'RT', 'LT', 'SETH'
        error(token, "#{token.text} doesn't like #{a} as input") unless (a % 45).zero?
        @heading = (name == 'SETH' ? a : @heading + (name == 'LT' ? -a : a)) % 360
      when 'PU' then @pen = 'UP'
      when 'PD' then @pen = 'DOWN'
      when 'PE' then @pen = 'ERASE'
      when 'SETPEN'
        error(token, "SETPEN doesn't like #{a} as input") unless (33..126).cover?(a)
        @character = a.chr
      when 'SETXY' then move_to(a, b)
      when 'SETX' then move_to(a, @y)
      when 'SETY' then move_to(@x, a)
      when 'HOME'
        move_to(0, 0)
        @heading = 0
      when 'CS'
        @canvas.clear
        @x = @y = @heading = 0
      when 'CLEAN' then @canvas.clear
      when 'FILL' then fill
      when 'LABEL'
        dx, dy = DIRECTIONS[@heading / 45]
        a.to_s.each_char.with_index { |char, i| @canvas[[@x + i * dx, @y + i * dy]] = char }
      when 'SNAPSHOT' then snapshot
      when 'REPEAT'
        next if b.empty?
        a.times do |i|
          @repetitions << i + 1
          begin
            execute(b)
          ensure
            @repetitions.pop
          end
        end
      when 'FOR'
        if d.empty?
          make(a, c)
          next
        end
        step = b <= c ? 1 : -1
        b.step(c, step) do |number|
          make(a, number)
          execute(d)
        end
      when 'IF' then execute(b) unless a.zero?
      when 'IFELSE' then execute(a.zero? ? c : b)
      when 'TEST' then @environments.last[:test] = !a.zero?
      when 'IFTRUE', 'IFFALSE'
        test = @environments.last[:test]
        error(token, "#{token.text} without TEST") if test.nil?
        execute(a) if test == (name == 'IFTRUE')
      when 'STOP' then raise LogoReturn.new(nil)
      when 'OUTPUT' then raise LogoReturn.new(a)
      when 'MAKE' then make(a, b)
      when 'LOCAL' then @environments.last[:variables][a] = 0
      when 'LOCALMAKE' then @environments.last[:variables][a] = b
      when 'TRACE' then @traced[a] = true
      when 'UNTRACE' then @traced.delete(a)
      when 'SEED'
        error(token, "SEED doesn't like #{a} as input") unless a.positive?
        @random = a
      when 'PRINT' then puts a.to_s
      when 'MULTIPRINT' then puts values.map(&:to_s).join(' ')
      end
    end
  end

  def finish
    puts "TURTLE #{@x} #{@y} #{@heading} #{@pen} #{@character}"
    snapshot
  end
end

def run_program(name, source)
  puts "PROGRAM #{name}"
  procedures = {}
  top = []
  current = nil
  source.each do |line, number|
    tokens = Language.lex(line, number)
    next if tokens.empty?
    if tokens[0].kind == :word && tokens[0].text == 'TO'
      raise LogoError.new(number, "TO inside definition of #{current.name}") if current
      raise LogoError.new(number, 'bad procedure header') unless tokens[1]&.kind == :word
      procedure_name = tokens[1].text
      raise LogoError.new(number, "#{procedure_name} is a primitive") if Language.primitive?(procedure_name)
      raise LogoError.new(number, "#{procedure_name} is already defined") if procedures.key?(procedure_name)
      parameters = []
      tokens.drop(2).each do |token|
        raise LogoError.new(number, 'bad procedure header') unless token.kind == :variable
        parameter = token.text[1..]
        raise LogoError.new(number, "duplicate input #{token.text}") if parameters.include?(parameter)
        parameters << parameter
      end
      current = Procedure.new(procedure_name, parameters, number, [], nil)
      procedures[procedure_name] = current
    elsif tokens.length == 1 && tokens[0].kind == :word && tokens[0].text == 'END'
      raise LogoError.new(number, 'END without TO') unless current
      current = nil
    else
      (current ? current.tokens : top).concat(tokens)
    end
  end
  raise LogoError.new(current.line, "missing END for #{current.name}") if current
  procedures.each_value { |procedure| procedure.body = Parser.new(procedure.tokens, procedures, false).sequence }
  body = Parser.new(top, procedures, true).sequence
  turtle = Turtle.new(procedures)
  turtle.execute(body)
  turtle.finish
rescue LogoError => error
  puts "ERROR line #{error.line}: #{error.message}"
  groups = error.calls.reverse.chunk(&:itself)
  groups.each { |procedure, calls| puts "  in #{procedure}#{calls.length > 1 ? ' x' + calls.length.to_s : ''}" }
end

programs = []
current = nil
STDIN.each_line.with_index(1) do |line, number|
  line = line.chomp
  break if line == '#EOF'
  if line.start_with?('#PROGRAM ')
    current = [line[9..], []]
    programs << current
  else
    current[1] << [line, number]
  end
end
programs.each { |name, source| run_program(name, source) }
