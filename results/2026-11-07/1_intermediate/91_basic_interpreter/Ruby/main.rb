class SyntaxFault < StandardError
end

class RuntimeFault < StandardError
end

Token = Data.define(:kind, :text, :value)
Expr = Data.define(:kind, :type, :value, :args)
Clause = Data.define(:line, :body)
PrintItem = Data.define(:kind, :expr)
BasicArray = Data.define(:bounds, :values)
Address = Data.define(:name, :index)
Frame = Data.define(:kind, :position, :name, :final, :step)
SIGNATURES = {
  "ABS" => %w[I],
  "SGN" => %w[I],
  "INT" => %w[I],
  "SQR" => %w[I],
  "RND" => %w[I],
  "LEN" => %w[S],
  "ASC" => %w[S],
  "VAL" => %w[S],
  "CHR$" => %w[I],
  "STR$" => %w[I],
  "LEFT$" => %w[SI],
  "RIGHT$" => %w[SI],
  "MID$" => %w[SI SII],
  "INSTR" => %w[SS]
}.freeze
ERROR_CODES = {
  "NEXT WITHOUT FOR" => 1,
  "RETURN WITHOUT GOSUB" => 3,
  "OUT OF DATA" => 4,
  "ILLEGAL FUNCTION CALL" => 5,
  "OVERFLOW" => 6,
  "OUT OF MEMORY" => 7,
  "UNDEFINED LINE NUMBER" => 8,
  "SUBSCRIPT OUT OF RANGE" => 9,
  "DUPLICATE DEFINITION" => 10,
  "DIVISION BY ZERO" => 11,
  "TYPE MISMATCH" => 13,
  "STRING TOO LONG" => 15,
  "RESUME WITHOUT ERROR" => 20,
  "FOR WITHOUT NEXT" => 26,
  "WHILE WITHOUT WEND" => 29,
  "WEND WITHOUT WHILE" => 30,
  "INPUT PAST END" => 62
}.freeze
OPERATORS = [%w[OR], %w[AND], [], %w[= <> < > <= >=], %w[+ -], %w[* / MOD], [], %w[^]].freeze
def syntax! = raise SyntaxFault, "SYNTAX ERROR"
def fault!(message) = raise RuntimeFault, message
def variable?(name) = /\A[A-Z][0-9]?\$?\z/.match?(name)
def name_type(name) = name.end_with?("$") ? "S" : "I"
def value_type(value) = value.is_a?(String) ? "S" : "I"
def expr(kind, type, value = "", args = []) = Expr.new(kind, type, value, args)

class Statement
  attr_accessor(
    :kind,
    :line,
    :next,
    :expr,
    :target,
    :targets,
    :expressions,
    :values,
    :numbers,
    :name,
    :mode,
    :clauses,
    :items
  )
  def initialize(kind)
    @kind = kind
    @line = 0
    @next = nil
    @expr = nil
    @target = nil
    @targets = []
    @expressions = []
    @values = []
    @numbers = []
    @name = ""
    @mode = ""
    @clauses = []
    @items = []
  end
end

def tokenize(text)
  tokens = []
  p = 0
  while p < text.length
    ch = text[p]
    if ch == " "
      p += 1
    elsif ch == "\""
      ending = text.index("\"", p + 1)
      syntax! unless ending
      tokens << Token.new("S", text[p..ending], text[p + 1...ending])
      p = ending + 1
    elsif /[0-9]/.match?(ch)
      start = p
      p += 1 while p < text.length && /[0-9]/.match?(text[p])
      word = text[start...p]
      value = word.to_i
      syntax! if value > 32767
      tokens << Token.new("I", word, value)
    elsif /[A-Z]/.match?(ch)
      if text[p, 3] == "REM"
        tokens << Token.new("W", "REM", "REM")
        break
      end

      start = p
      p += 1 while p < text.length && /[A-Z0-9]/.match?(text[p])
      p += 1 if text[p] == "$"
      word = text[start...p]
      tokens << Token.new("W", word, word)
    else
      word = text[p, 2]
      word = ch unless %w[<> <= >=].include?(word)
      syntax! unless "+-*/^=<>() ,;:".include?(ch)
      tokens << Token.new("P", word, word)
      p += word.length
    end
  end

  tokens << Token.new("E", "", "")
end

class Parser
  def initialize(tokens)
    @tokens = tokens
    @position = 0
  end

  def current = @tokens[@position]
  def at?(word) = %w[P W].include?(current.kind) && current.text == word
  def take(word)
    return false unless at?(word)
    @position += 1
    true
  end

  def expect(word)
    syntax! unless take(word)
  end

  def integer
    e = expression
    syntax! unless e.type == "I"
    e
  end

  def integer_at(level)
    e = expression(level)
    syntax! unless e.type == "I"
    e
  end

  def number
    token = current
    syntax! unless token.kind == "I"
    @position += 1
    token.value
  end

  def target
    token = current
    syntax! unless token.kind == "W" && variable?(token.text)
    @position += 1
    args = []
    if take("(")
      args << integer
      args << integer if take(",")
      expect(")")
    end

    expr(args.empty? ? "variable" : "array", name_type(token.text), token.text, args)
  end

  def expression(level = 0)
    return expr("unary", "I", "NOT", [integer_at(2)]) if level == 2 && take("NOT")
    return expr("unary", "I", "-", [integer_at(6)]) if level == 6 && take("-")
    return primary if level == 8
    left = expression(level + 1)
    while OPERATORS[level].any? { |op| at?(op) }
      op = current.text
      @position += 1
      right = expression(level == 7 ? 6 : level + 1)
      syntax! if left.type != right.type || (left.type == "S" && level != 3 && op != "+")
      left = expr("binary", level == 3 ? "I" : left.type, op, [left, right])
      break if level == 7
    end

    left
  end

  def primary
    token = current
    if %w[I S].include?(token.kind)
      @position += 1
      return expr("constant", token.kind, token.value)
    end

    if take("(")
      e = expression
      expect(")")
      return e
    end

    return target if token.kind == "W" && variable?(token.text)
    return expr("builtin", "I", "ERR") if take("ERR")
    return expr("builtin", "I", "ERL") if take("ERL")
    if token.kind == "W" && SIGNATURES.key?(token.text)
      @position += 1
      expect("(")
      args = [expression]
      args << expression while take(",")
      expect(")")
      syntax! unless SIGNATURES[token.text].include?(args.map(&:type).join)
      return expr("call", name_type(token.text), token.text, args)
    end

    syntax!
  end

  def clause
    current.kind == "I" ? Clause.new(number, []) : Clause.new(nil, list(true))
  end

  def list(in_clause = false)
    statements = [statement(in_clause)]
    statements << statement(in_clause) while take(":")
    statements
  end

  def statement(in_clause)
    word = current.text
    syntax! if in_clause && %w[IF FOR NEXT WHILE WEND DATA].include?(word)
    s = Statement.new(word)
    if %w[REM RETURN WEND END STOP].any? { |name| take(name) }
      return s
    end

    if take("PRINT")
      expression_last = false
      while current.kind != "E" && !at?(":") && !at?("ELSE")
        if take(";")
          s.items << PrintItem.new(";", nil)
          expression_last = false
        elsif take(",")
          s.items << PrintItem.new(",", nil)
          expression_last = false
        else
          kind = at?("TAB") ? "TAB" : at?("SPC") ? "SPC" : "value"
          syntax! if kind == "value" && expression_last
          if kind == "value"
            e = expression
          else
            @position += 1
            expect("(")
            e = integer
            expect(")")
          end

          s.items << PrintItem.new(kind, e)
          expression_last = kind == "value"
        end
      end

      return s
    end

    if take("INPUT") || take("READ") || take("DIM")
      loop do
        t = target
        syntax! if word == "DIM" && t.kind != "array"
        s.targets << t
        break unless take(",")
      end

      return s
    end

    if take("DATA")
      loop do
        negative = take("-")
        token = current
        syntax! unless token.kind == "I" || (token.kind == "S" && !negative)
        @position += 1
        s.values << (negative ? -token.value : token.value)
        break unless take(",")
      end

      return s
    end

    if take("IF")
      s.expr = integer
      expect("THEN")
      s.clauses << clause
      s.clauses << clause if take("ELSE")
      syntax! unless current.kind == "E"
      return s
    end

    if take("GOTO") || take("GOSUB")
      s.numbers << number
      return s
    end

    if take("ON")
      if take("ERROR")
        s.kind = "handler"
        expect("GOTO")
        s.numbers << number
      else
        s.expr = integer
        if take("GOTO")
          s.mode = "GOTO"
        else
          expect("GOSUB")
          s.mode = "GOSUB"
        end

        s.numbers << number
        s.numbers << number while take(",")
      end

      return s
    end

    if take("RESUME")
      if take("NEXT")
        s.mode = "NEXT"
      elsif current.kind == "I"
        s.mode = "line"
        s.numbers << number
      end

      return s
    end

    if take("FOR")
      token = current
      syntax! unless token.kind == "W" && variable?(token.text) && name_type(token.text) == "I"
      s.name = token.text
      @position += 1
      expect("=")
      s.expressions << integer
      expect("TO")
      s.expressions << integer
      s.expressions << (take("STEP") ? integer : expr("constant", "I", 1))
      return s
    end

    if take("NEXT")
      if current.kind == "W" && variable?(current.text) && name_type(current.text) == "I"
        s.name = current.text
        @position += 1
      end

      return s
    end

    if take("WHILE") || take("RANDOMIZE")
      s.expr = integer
      return s
    end

    if take("RESTORE")
      s.numbers << number if current.kind == "I"
      return s
    end

    take("LET")
    s.kind = "assign"
    s.target = target
    expect("=")
    s.expr = expression
    syntax! unless s.expr.type == s.target.type
    s
  end

  def parse
    result = list
    syntax! unless current.kind == "E"
    result
  end
end

class Machine
  def initialize(inputs)
    @inputs = inputs
    @variables = {}
    @arrays = {}
    @stack = []
    @entries = {}
    @sequence = []
    @data = []
    @data_position = 0
    @input_position = 0
    @random = 1
    @handler = 0
    @handling = false
    @remembered = nil
    @err = 0
    @erl = 0
    @buffer = ""
    @output = []
  end

  def end_line
    @output << @buffer.sub(/ +\z/, "")
    @buffer = ""
  end

  def message(text)
    end_line unless @buffer.empty?
    @output << text
  end

  def checked(n)
    fault!("OVERFLOW") unless n.between?(-32768, 32767)
    n
  end

  def get(name) = @variables.fetch(name) { name_type(name) == "S" ? "" : 0 }
  def declare(name, bounds)
    @arrays[name] = BasicArray.new(
      bounds,
      Array.new(bounds.map { |b| b + 1 }.inject(1, :*), name_type(name) == "S" ? "" : 0)
    )
  end

  def address(target)
    name = target.value
    return Address.new(name, nil) if target.kind == "variable"
    indices = target.args.map { |e| evaluate(e) }
    declare(name, Array.new(indices.length, 10)) unless @arrays.key?(name)
    array = @arrays[name]
    if indices.length != array.bounds.length || indices.each_with_index.any? { |n, i| n < 0 || n > array.bounds[i] }
      fault!("SUBSCRIPT OUT OF RANGE")
    end

    index = 0
    indices.each_with_index { |n, i| index = index * (array.bounds[i] + 1) + n }
    Address.new(name, index)
  end

  def load(address) = address.index.nil? ? get(address.name) : @arrays[address.name].values[address.index]
  def store(address, value)
    if address.index.nil?
      @variables[address.name] = value
    else
      @arrays[address.name].values[address.index] = value
    end
  end

  def quotient(a, b) = (a < 0) != (b < 0) ? -(a.abs / b.abs) : a.abs / b.abs
  def evaluate(e)
    op = e.value
    return op if e.kind == "constant"
    return load(address(e)) if %w[variable array].include?(e.kind)
    return op == "ERR" ? @err : @erl if e.kind == "builtin"
    if e.kind == "unary"
      a = evaluate(e.args[0])
      return op == "NOT" ? ~a : checked(-a)
    end

    args = e.args.map { |a| evaluate(a) }
    return call(op, args) if e.kind == "call"
    a, b = args
    if %w[= <> < > <= >=].include?(op)
      order = a <=> b
      return {
        "=" => order.zero?,
        "<>" => !order.zero?,
        "<" => order < 0,
        ">" => order > 0,
        "<=" => order <= 0,
        ">=" => order >= 0
      }[op] ? -1 : 0
    end

    if e.type == "S"
      text = a + b
      fault!("STRING TOO LONG") if text.length > 255
      return text
    end

    case op
    when "+"
      checked(a + b)
    when "-"
      checked(a - b)
    when "*"
      checked(a * b)
    when "/"
      fault!("DIVISION BY ZERO") if b.zero?
      checked(quotient(a, b))
    when "MOD"
      fault!("DIVISION BY ZERO") if b.zero?
      a - b * quotient(a, b)
    when "^"
      fault!("ILLEGAL FUNCTION CALL") if b < 0
      fault!("OVERFLOW") if a.abs > 1 && b > 15
      checked(a ** b)
    when "AND"
      a & b
    when "OR"
      a | b
    end
  end

  def call(name, args)
    a, b, c = args
    case name
    when "ABS"
      checked(a.abs)
    when "SGN"
      a <=> 0
    when "INT"
      a
    when "SQR"
      fault!("ILLEGAL FUNCTION CALL") if a < 0
      Integer.sqrt(a)
    when "RND"
      fault!("ILLEGAL FUNCTION CALL") if a < 1
      @random = 48271 * @random % 2147483647
      @random % a + 1
    when "LEN"
      a.length
    when "ASC"
      fault!("ILLEGAL FUNCTION CALL") if a.empty?
      a.ord
    when "VAL"
      match = /\A *([+-]?[0-9]+)/.match(a)
      checked(match ? match[1].to_i : 0)
    when "CHR$"
      fault!("ILLEGAL FUNCTION CALL") unless a.between?(32, 126)
      a.chr
    when "STR$"
      a.to_s
    when "LEFT$"
      fault!("ILLEGAL FUNCTION CALL") if b < 0
      a[0, b]
    when "RIGHT$"
      fault!("ILLEGAL FUNCTION CALL") if b < 0
      count = [b, a.length].min
      a[-count, count]
    when "MID$"
      fault!("ILLEGAL FUNCTION CALL") if b < 1 || (args.length == 3 && c < 0)
      text = a[b - 1..] || ""
      args.length == 3 ? text[0, c] : text
    when "INSTR"
      (a.index(b) || -1) + 1
    end
  end

  def line(number) = @entries[number] || fault!("UNDEFINED LINE NUMBER")
  def push(frame)
    fault!("OUT OF MEMORY") if @stack.length == 100
    @stack << frame
  end

  def search(kind, name = "")
    (@stack.length - 1).downto(0) do |i|
      f = @stack[i]
      break if f.kind == "GOSUB"
      return i if f.kind == kind && (name.empty? || f.name == name)
    end

    -1
  end

  def matching(s, opening, closing)
    depth = 0
    @sequence.drop(@sequence.index(s) + 1).each do |t|
      if t.kind == opening
        depth += 1
      elsif t.kind == closing
        return t.next if depth.zero?
        depth -= 1
      end
    end

    fault!(opening + " WITHOUT " + closing)
  end

  def subroutine(number, after)
    target = line(number)
    push(Frame.new("GOSUB", after, nil, nil, nil))
    target
  end

  def execute(s)
    following = s.next
    case s.kind
    when "assign"
      place = address(s.target)
      store(place, evaluate(s.expr))
    when "PRINT"
      s.items.each do |item|
        if item.kind == ","
          @buffer += " " * (10 - @buffer.length % 10)
        elsif item.kind != ";"
          value = evaluate(item.expr)
          if item.kind == "value"
            @buffer += value.to_s
          else
            fault!("ILLEGAL FUNCTION CALL") if value < 0
            @buffer += " " * (item.kind == "SPC" ? value : [0, value - @buffer.length].max)
          end
        end
      end

      end_line if s.items.empty? || ![";", ","].include?(s.items.last.kind)
    when "INPUT", "READ"
      s.targets.each do |target|
        place = address(target)
        if s.kind == "READ"
          fault!("OUT OF DATA") if @data_position == @data.length
          value = @data[@data_position][1]
          @data_position += 1
          fault!("TYPE MISMATCH") unless value_type(value) == target.type
        else
          loop do
            fault!("INPUT PAST END") if @input_position == @inputs.length
            text = @inputs[@input_position]
            @input_position += 1
            if target.type == "S"
              value = text
              break
            end

            n = text.to_i
            if /\A-?[0-9]+\z/.match?(text) && n.between?(-32768, 32767)
              value = n
              break
            end

            message("?REDO FROM START")
          end
        end

        store(place, value)
      end

    when "RESTORE"
      if s.numbers.empty?
        @data_position = 0
      else
        line(s.numbers[0])
        @data_position = @data.index { |number, _| number >= s.numbers[0] } || @data.length
      end

    when "IF"
      chosen = s.clauses[evaluate(s.expr).zero? ? 1 : 0]
      following = chosen.line ? line(chosen.line) : chosen.body[0] if chosen
    when "GOTO"
      following = line(s.numbers[0])
    when "GOSUB"
      following = subroutine(s.numbers[0], following)
    when "ON"
      n = evaluate(s.expr)
      fault!("ILLEGAL FUNCTION CALL") if n < 0
      if n.between?(1, s.numbers.length)
        following = s.mode == "GOTO" ? line(s.numbers[n - 1]) : subroutine(s.numbers[n - 1], following)
      end

    when "RETURN"
      index = @stack.rindex { |f| f.kind == "GOSUB" }
      fault!("RETURN WITHOUT GOSUB") unless index
      following = @stack[index].position
      @stack = @stack.first(index)
    when "FOR"
      start, final, step = s.expressions.map { |e| evaluate(e) }
      fault!("ILLEGAL FUNCTION CALL") if step.zero?
      index = search("FOR", s.name)
      @stack = @stack.first(index) if index >= 0
      @variables[s.name] = start
      if step > 0 ? start > final : start < final
        following = matching(s, "FOR", "NEXT")
      else
        push(Frame.new("FOR", following, s.name, final, step))
      end

    when "NEXT"
      index = search("FOR", s.name)
      fault!("NEXT WITHOUT FOR") if index < 0
      @stack = @stack.first(index + 1)
      f = @stack[index]
      value = checked(get(f.name) + f.step)
      @variables[f.name] = value
      if f.step > 0 ? value > f.final : value < f.final
        @stack.pop
      else
        following = f.position
      end

    when "WHILE"
      if evaluate(s.expr).zero?
        following = matching(s, "WHILE", "WEND")
      else
        push(Frame.new("WHILE", s, nil, nil, nil))
      end

    when "WEND"
      index = search("WHILE")
      fault!("WEND WITHOUT WHILE") if index < 0
      following = @stack[index].position
      @stack = @stack.first(index)
    when "DIM"
      s.targets.each do |target|
        name = target.value
        bounds = target.args.map { |e| evaluate(e) }
        fault!("DUPLICATE DEFINITION") if @arrays.key?(name)
        fault!("ILLEGAL FUNCTION CALL") if bounds.any?(&:negative?)
        fault!("OUT OF MEMORY") if bounds.map { |n| n + 1 }.inject(1, :*) > 10000
        declare(name, bounds)
      end

    when "RANDOMIZE"
      n = evaluate(s.expr)
      fault!("ILLEGAL FUNCTION CALL") if n < 1
      @random = n
    when "handler"
      line(s.numbers[0]) unless s.numbers[0].zero?
      @handler = s.numbers[0]
    when "RESUME"
      fault!("RESUME WITHOUT ERROR") unless @handling
      following = s.mode == "line" ? line(s.numbers[0]) : s.mode == "NEXT" ? @remembered.next : @remembered
      @handling = false
    when "STOP"
      message("BREAK IN LINE #{s.line}")
      return nil
    when "END"
      return nil
    end

    following
  end

  def connect(body, after, number)
    following = after
    body.reverse_each do |s|
      s.line = number
      s.next = following
      s.clauses.each { |c| connect(c.body, following, number) }
      following = s
    end
  end

  def run(source)
    parsed = []
    source.keys.sort.each do |number|
      begin
        parsed << [number, Parser.new(tokenize(source[number])).parse]
      rescue SyntaxFault
        message("ERROR IN LINE #{number}: SYNTAX ERROR")
        return finish
      end
    end

    after = nil
    parsed.reverse_each do |number, body|
      connect(body, after, number)
      @entries[number] = body[0]
      after = body[0]
    end

    @sequence = parsed.flat_map(&:last)
    @sequence.each { |s| s.values.each { |v| @data << [s.line, v] } if s.kind == "DATA" }
    position = after
    while position
      statement = position
      begin
        position = execute(statement)
      rescue RuntimeFault => failure
        if @handler != 0 && !@handling
          @err = ERROR_CODES[failure.message]
          @erl = statement.line
          @remembered = statement
          @handling = true
          position = line(@handler)
        else
          message("ERROR IN LINE #{statement.line}: #{failure.message}")
          position = nil
        end
      end
    end

    finish
  end

  def finish
    end_line unless @buffer.empty?
    @output << "READY"
    @output
  end
end

lines = $stdin.each_line.map(&:chomp)
cursor = 1
output = []
lines[0].to_i.times do
  source = {}
  while lines[cursor] != "RUN"
    match = /\A([0-9]+)(?: +(.*))?\z/.match(lines[cursor])
    cursor += 1
    number = match[1].to_i
    match[2] ? source[number] = match[2] : source.delete(number)
  end

  cursor += 1
  data = []
  while lines[cursor] != "END"
    data << lines[cursor]
    cursor += 1
  end

  cursor += 1
  output.concat(Machine.new(data).run(source))
end

$stdout.write(output.join("\n") + "\n")
