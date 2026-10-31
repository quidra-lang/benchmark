class ForthError < StandardError
  attr_reader :word, :reason, :code

  def initialize(word, reason, code = nil)
    @word = word
    @reason = reason
    @code = code
    super(reason)
  end
end

class ForthWord
  attr_accessor :name, :kind, :value, :here, :code, :local_count, :does_word,
                :does_start, :xt

  def initialize(name, kind, value = nil, here = 0)
    @name = name
    @kind = kind
    @value = value
    @here = here
    @code = []
    @local_count = 0
    @xt = nil
    @does_word = nil
    @does_start = 0
  end
end

class Forth
  COMPILE_ONLY = %w[IF ELSE THEN DO ?DO LOOP +LOOP LEAVE UNLOOP I J BEGIN
                    UNTIL WHILE REPEAT AGAIN CASE OF ENDOF ENDCASE EXIT RECURSE
                    DOES> ; >R R> R@ ABORT" ['] {:].freeze
  INTERPRET_ONLY = %w[: :NONAME FORGET].freeze
  SPECIAL = (COMPILE_ONLY + INTERPRET_ONLY + ['."', '(', '\\', 'TO', 'IS']).freeze
  BUILTINS = %w[+ - * / MOD /MOD */ */MOD NEGATE ABS MIN MAX 1+ 1- 2* 2/
                = <> < > 0= 0<> 0< 0> WITHIN TRUE FALSE AND OR XOR INVERT
                DUP ?DUP DROP SWAP OVER ROT -ROT NIP TUCK 2DUP 2DROP 2SWAP
                2OVER DEPTH PICK ROLL . .R .S ? CR EMIT SPACE SPACES BL ! @
                +! , ALLOT HERE CELLS CELL+ BASE HEX DECIMAL CREATE VARIABLE
                CONSTANT VALUE DEFER ' EXECUTE CATCH THROW ABORT WORDS].freeze
  ERROR_CODES = {
    'aborted' => -1, 'stack overflow' => -3, 'stack underflow' => -4,
    'return stack overflow' => -5, 'return stack underflow' => -6,
    'nesting too deep' => -7, 'invalid address' => -9, 'division by zero' => -10,
    'undefined word' => -13, 'missing name' => -16, 'invalid name' => -19,
    'deferred word not set' => -21, 'invalid argument' => -24,
    'no CREATE word' => -31, 'invalid base' => -40
  }.freeze

  def initialize
    @stack = []
    @returns = []
    @memory = [10]
    @dictionary = []
    @builtins = BUILTINS.to_h { |name| [name, ForthWord.new(name, :builtin)] }
    @tokens = []
    @pending = ''
    @compiling = nil
    @depth = 0
  end

  def error(word, reason, code = ERROR_CODES[reason])
    raise ForthError.new(word, reason, code)
  end

  def read_word
    @position += 1 while @position < @line.length && @line[@position] == ' '
    return nil if @position == @line.length

    start = @position
    @position += 1 while @position < @line.length && @line[@position] != ' '
    @line[start...@position]
  end

  def read_name(source)
    read_word || error(source, 'missing name')
  end

  def number(text, base = @memory[0])
    return text[1].ord if text.length == 3 && text[0] == "'" && text[2] == "'"

    if %w[$ # %].include?(text[0])
      base = { '$' => 16, '#' => 10, '%' => 2 }[text[0]]
      text = text[1..]
    elsif !(2..36).cover?(base)
      error(text, 'invalid base')
    end
    sign = text.start_with?('-') ? -1 : 1
    digits = sign == -1 ? text[1..] : text
    return nil if digits.empty?

    result = 0
    digits.upcase.each_byte do |c|
      d = if (48..57).cover?(c)
            c - 48
          elsif (65..90).cover?(c)
            c - 55
          else
            return nil
          end
      return nil if d >= base

      result = result * base + d
    end
    sign * result
  end

  def check_name(name)
    error(name, 'invalid name') if SPECIAL.include?(name.upcase) || !number(name, 10).nil?
    name.upcase
  end

  def lookup(name)
    key = name.upcase
    @dictionary.reverse_each.find { |word| word.name == key } || @builtins[key]
  end

  def token(word)
    unless word.xt
      @tokens << word
      word.xt = @tokens.length
    end
    word.xt
  end

  def valid_token?(value)
    value >= 1 && value <= @tokens.length
  end

  def take(count, source)
    error(source, 'stack underflow') if @stack.length < count
    @stack.pop(count)
  end

  def push(value, source)
    @stack << value
    error(source, 'stack overflow') if @stack.length > 1000
  end

  def push_all(values, source)
    values.each { |value| push(value, source) }
  end

  def return_need(count, source)
    error(source, 'return stack underflow') if @returns.length < count
  end

  def return_push(value, source)
    @returns << value
    error(source, 'return stack overflow') if @returns.length > 1000
  end

  def address(value, source)
    error(source, 'invalid address') if value.negative? || value % 8 != 0 || value >= @memory.length * 8
    value / 8
  end

  def output_number(value, source)
    base = @memory[0]
    error(source, 'invalid base') unless (2..36).cover?(base)
    value.to_s(base).upcase
  end

  def flush
    puts @pending.sub(/ +\z/, '')
    @pending = ''
  end

  def emit(op, source, *args)
    @compiling.code << [op, source, *args]
    @compiling.code.length - 1
  end

  def mismatch(source, kinds)
    error(source, 'control structure mismatch') if @control.empty? || !kinds.include?(@control[-1][:kind])
  end

  def compile(source)
    key = source.upcase
    case key
    when 'IF'
      @control << { kind: 'IF', at: emit(:zero_jump, source, nil) }
    when 'ELSE'
      mismatch(source, ['IF'])
      old = @control.pop
      index = emit(:jump, source, nil)
      @compiling.code[old[:at]][2] = @compiling.code.length
      @control << { kind: 'ELSE', at: index }
    when 'THEN'
      mismatch(source, %w[IF ELSE])
      @compiling.code[@control.pop[:at]][2] = @compiling.code.length
    when 'BEGIN'
      @control << { kind: 'BEGIN', begin: @compiling.code.length }
    when 'UNTIL', 'AGAIN'
      mismatch(source, ['BEGIN'])
      record = @control.pop
      emit(key == 'UNTIL' ? :zero_jump : :jump, source, record[:begin])
    when 'WHILE'
      mismatch(source, ['BEGIN'])
      record = @control.pop
      @control << { kind: 'WHILE', begin: record[:begin], at: emit(:zero_jump, source, nil) }
    when 'REPEAT'
      mismatch(source, ['WHILE'])
      record = @control.pop
      emit(:jump, source, record[:begin])
      @compiling.code[record[:at]][2] = @compiling.code.length
    when 'DO', '?DO'
      @control << { kind: key, at: emit(:do, source, nil, key == '?DO'), leaves: [] }
    when 'LOOP', '+LOOP'
      mismatch(source, %w[DO ?DO])
      record = @control.pop
      emit(:loop, source, record[:at] + 1, key == '+LOOP')
      finish = @compiling.code.length
      @compiling.code[record[:at]][2] = finish
      record[:leaves].each { |at| @compiling.code[at][2] = finish }
    when 'LEAVE'
      record = @control.reverse.find { |item| %w[DO ?DO].include?(item[:kind]) }
      error(source, 'control structure mismatch') unless record
      record[:leaves] << emit(:leave, source, nil)
    when 'CASE'
      @control << { kind: 'CASE', ends: [] }
    when 'OF'
      mismatch(source, ['CASE'])
      @control << { kind: 'OF', at: emit(:of, source, nil) }
    when 'ENDOF'
      mismatch(source, ['OF'])
      record = @control.pop
      @control[-1][:ends] << emit(:jump, source, nil)
      @compiling.code[record[:at]][2] = @compiling.code.length
    when 'ENDCASE'
      mismatch(source, ['CASE'])
      record = @control.pop
      emit(:drop, source)
      record[:ends].each { |at| @compiling.code[at][2] = @compiling.code.length }
    when 'EXIT'
      emit(:exit, source)
    when 'RECURSE'
      emit(:call, source, @compiling)
    when 'DOES>'
      error(source, 'control structure mismatch') unless @control.empty?
      emit(:does, source, @compiling, @compiling.code.length + 1)
    when ';'
      unless @control.empty?
        kind = @control[-1][:kind]
        kind = 'IF' if kind == 'ELSE'
        kind = 'BEGIN' if kind == 'WHILE'
        error(source, "unclosed #{kind}")
      end
      word = @compiling
      @compiling = nil
      if @anonymous
        push(token(word), source)
      else
        @dictionary << word
      end
    when "[']"
      name = read_name(source)
      word = lookup(name) || error(name, 'undefined word')
      emit(:literal, source, token(word))
    when '{:'
      names = []
      loop do
        name = read_word
        error(source, 'unterminated locals') unless name
        break if name.upcase == ':}'
        names << name
      end
      names = names.take_while { |name| name != '--' }
      slots = names.map do |name|
        key_name = check_name(name)
        index = @compiling.local_count
        @compiling.local_count += 1
        @locals[key_name] = index
        index
      end
      emit(:locals, source, slots)
    when '>R', 'R>', 'R@', 'I', 'J', 'UNLOOP'
      emit(:return_stack, source, key)
    else
      if @locals.key?(key)
        emit(:local, source, @locals[key])
      elsif (word = lookup(source))
        emit(:call, source, word)
      elsif !(value = number(source)).nil?
        emit(:literal, source, value)
      else
        error(source, 'undefined word')
      end
    end
  end

  def process(source)
    key = source.upcase
    case key
    when '\\'
      @position = @line.length
      return
    when '('
      finish = @line.index(')', @position)
      error(source, 'unterminated comment') unless finish
      @position = finish + 1
      return
    end
    error(source, 'compile only') if !@compiling && COMPILE_ONLY.include?(key)
    error(source, 'interpret only') if @compiling && INTERPRET_ONLY.include?(key)
    case key
    when '."', 'ABORT"'
      start = @position + 1
      finish = @line.index('"', start)
      error(source, 'unterminated string') unless @position < @line.length && finish
      string = @line[start...finish]
      @position = finish + 1
      if @compiling
        emit(key == '."' ? :write : :abort_string, source, string)
      else
        @pending << string
      end
    when 'TO', 'IS'
      name = read_name(source)
      if key == 'TO' && @compiling && @locals.key?(name.upcase)
        emit(:set_local, source, @locals[name.upcase])
        return
      end
      word = lookup(name) || error(name, 'undefined word')
      error(name, key == 'TO' ? 'not a value' : 'not deferred') unless word.kind == (key == 'TO' ? :value : :defer)
      if @compiling
        emit(key == 'TO' ? :to : :is, source, word)
      else
        assign(word, source, key == 'IS')
      end
    when ':', ':NONAME'
      name = key == ':' ? read_name(source) : source
      check_name(name) if key == ':'
      @compiling = ForthWord.new(name.upcase, :colon, nil, @memory.length * 8)
      @definition_name = name
      @anonymous = key == ':NONAME'
      @control = []
      @locals = {}
    when 'FORGET'
      name = read_name(source)
      index = @dictionary.rindex { |word| word.name == name.upcase }
      error(name, 'undefined word') unless index
      @memory = @memory.take(@dictionary[index].here / 8)
      @dictionary = @dictionary.take(index)
    else
      if @compiling
        compile(source)
      elsif (word = lookup(source))
        execute(word, source)
      elsif !(value = number(source)).nil?
        push(value, source)
      else
        error(source, 'undefined word')
      end
    end
  end

  def assign(word, source, deferred)
    value = take(1, source)[0]
    if deferred
      error(source, 'invalid argument') unless valid_token?(value)
      word.value = value
    else
      @memory[word.value / 8] = value
    end
  end

  def return_operation(key, source)
    case key
    when '>R'
      return_push(take(1, source)[0], source)
    when 'R>'
      return_need(1, source)
      push(@returns.pop, source)
    when 'R@', 'I'
      return_need(1, source)
      push(@returns[-1], source)
    when 'J'
      return_need(3, source)
      push(@returns[-3], source)
    when 'UNLOOP'
      return_need(2, source)
      @returns.pop(2)
    end
  end

  def execute_definition(word, start, source)
    error(source, 'nesting too deep') if @depth == 100
    @depth += 1
    return_size = @returns.length
    locals = Array.new(word.local_count, 0)
    pc = start
    while pc < word.code.length
      op, spelling, a, b = word.code[pc]
      pc += 1
      case op
      when :literal
        push(a, spelling)
      when :call
        execute(a, spelling)
      when :write
        @pending << a
      when :local
        push(locals[a], spelling)
      when :set_local
        locals[a] = take(1, spelling)[0]
      when :locals
        values = take(a.length, spelling)
        a.each_with_index { |slot, i| locals[slot] = values[i] }
      when :to, :is
        assign(a, spelling, op == :is)
      when :exit
        break
      when :does
        created = @dictionary[-1]
        error(spelling, 'no CREATE word') unless created && created.kind == :create
        created.does_word = a
        created.does_start = b
        break
      when :jump
        pc = a
      when :zero_jump
        pc = a if take(1, spelling)[0] == 0
      when :do
        limit, index = take(2, spelling)
        if b && limit == index
          pc = a
        else
          return_push(limit, spelling)
          return_push(index, spelling)
        end
      when :loop
        step = b ? take(1, spelling)[0] : 1
        return_need(2, spelling)
        index = @returns[-1]
        limit = @returns[-2]
        next_index = index + step
        if (index - limit).negative? != (next_index - limit).negative?
          @returns.pop(2)
        else
          @returns[-1] = next_index
          pc = a
        end
      when :leave
        return_need(2, spelling)
        @returns.pop(2)
        pc = a
      when :of
        x, y = take(2, spelling)
        if x != y
          push(x, spelling)
          pc = a
        end
      when :drop
        take(1, spelling)
      when :return_stack
        return_operation(a, spelling)
      when :abort_string
        error(spelling, a, -2) if take(1, spelling)[0] != 0
      end
    end
    @returns.slice!(return_size..-1) if @returns.length > return_size
    @depth -= 1
  end

  def execute_token(value, source)
    error(source, 'invalid argument') unless valid_token?(value)
    word = @tokens[value - 1]
    execute(word, word.name)
  end

  def execute(word, source)
    while word.kind == :defer
      error(source, 'deferred word not set') unless word.value
      error(source, 'invalid argument') unless valid_token?(word.value)
      word = @tokens[word.value - 1]
      source = word.name
    end
    case word.kind
    when :colon
      execute_definition(word, 0, source)
    when :create, :variable
      push(word.value, source)
      execute_definition(word.does_word, word.does_start, source) if word.does_word
    when :constant
      push(word.value, source)
    when :value
      push(@memory[word.value / 8], source)
    when :builtin
      builtin(word.name, source)
    end
  end

  def builtin(key, source)
    case key
    when '+', '-', '*', '/', 'MOD', '/MOD', 'MIN', 'MAX', '=', '<>', '<', '>', 'AND', 'OR', 'XOR'
      a, b = take(2, source)
      case key
      when '+' then push(a + b, source)
      when '-' then push(a - b, source)
      when '*' then push(a * b, source)
      when '/', 'MOD', '/MOD'
        error(source, 'division by zero') if b == 0
        q, r = a.divmod(b)
        push_all(key == '/' ? [q] : key == 'MOD' ? [r] : [r, q], source)
      when 'MIN' then push([a, b].min, source)
      when 'MAX' then push([a, b].max, source)
      when '=' then push(a == b ? -1 : 0, source)
      when '<>' then push(a != b ? -1 : 0, source)
      when '<' then push(a < b ? -1 : 0, source)
      when '>' then push(a > b ? -1 : 0, source)
      when 'AND' then push(a & b, source)
      when 'OR' then push(a | b, source)
      when 'XOR' then push(a ^ b, source)
      end
    when '*/', '*/MOD'
      a, b, c = take(3, source)
      error(source, 'division by zero') if c == 0
      q, r = (a * b).divmod(c)
      push_all(key == '*/' ? [q] : [r, q], source)
    when 'NEGATE', 'ABS', '1+', '1-', '2*', '2/', '0=', '0<>', '0<', '0>', 'INVERT', 'CELLS', 'CELL+'
      a = take(1, source)[0]
      value = case key
              when 'NEGATE' then -a
              when 'ABS' then a.abs
              when '1+' then a + 1
              when '1-' then a - 1
              when '2*' then a * 2
              when '2/' then a.div(2)
              when '0=' then a == 0 ? -1 : 0
              when '0<>' then a != 0 ? -1 : 0
              when '0<' then a < 0 ? -1 : 0
              when '0>' then a > 0 ? -1 : 0
              when 'INVERT' then -a - 1
              when 'CELLS' then a * 8
              when 'CELL+' then a + 8
              end
      push(value, source)
    when 'WITHIN'
      n, lo, hi = take(3, source)
      push(lo <= n && n < hi ? -1 : 0, source)
    when 'TRUE', 'FALSE', 'BL', 'BASE', 'HERE'
      push({ 'TRUE' => -1, 'FALSE' => 0, 'BL' => 32, 'BASE' => 0, 'HERE' => @memory.length * 8 }[key], source)
    when 'DUP', '?DUP', 'DROP', 'SWAP', 'OVER', 'ROT', '-ROT', 'NIP', 'TUCK', '2DUP', '2DROP', '2SWAP', '2OVER'
      count = { 'DUP' => 1, '?DUP' => 1, 'DROP' => 1, 'SWAP' => 2, 'OVER' => 2,
                'ROT' => 3, '-ROT' => 3, 'NIP' => 2, 'TUCK' => 2, '2DUP' => 2,
                '2DROP' => 2, '2SWAP' => 4, '2OVER' => 4 }[key]
      values = take(count, source)
      a, b, c, d = values
      result = case key
               when 'DUP' then [a, a]
               when '?DUP' then a == 0 ? [a] : [a, a]
               when 'DROP', '2DROP' then []
               when 'SWAP' then [b, a]
               when 'OVER' then [a, b, a]
               when 'ROT' then [b, c, a]
               when '-ROT' then [c, a, b]
               when 'NIP' then [b]
               when 'TUCK' then [b, a, b]
               when '2DUP' then [a, b, a, b]
               when '2SWAP' then [c, d, a, b]
               when '2OVER' then [a, b, c, d, a, b]
               end
      push_all(result, source)
    when 'DEPTH'
      push(@stack.length, source)
    when 'PICK', 'ROLL'
      u = take(1, source)[0]
      error(source, 'invalid argument') if u.negative?
      error(source, 'stack underflow') if @stack.length <= u
      value = key == 'PICK' ? @stack[-1 - u] : @stack.delete_at(@stack.length - 1 - u)
      push(value, source)
    when '.', '.R', '?'
      values = take(key == '.R' ? 2 : 1, source)
      n = key == '?' ? @memory[address(values[0], source)] : values[0]
      text = output_number(n, source)
      @pending << (key == '.R' ? text.rjust([values[1], 0].max) : text + ' ')
    when '.S'
      output_number(0, source)
      @pending << '<' + output_number(@stack.length, source) + '> '
      @stack.each { |value| @pending << output_number(value, source) + ' ' }
    when 'CR'
      flush
    when 'EMIT'
      c = take(1, source)[0]
      error(source, 'invalid argument') unless (32..126).cover?(c)
      @pending << c.chr
    when 'SPACE'
      @pending << ' '
    when 'SPACES'
      @pending << ' ' * [take(1, source)[0], 0].max
    when '!', '+!'
      n, a = take(2, source)
      index = address(a, source)
      @memory[index] = key == '!' ? n : @memory[index] + n
    when '@'
      push(@memory[address(take(1, source)[0], source)], source)
    when ','
      @memory << take(1, source)[0]
    when 'ALLOT'
      n = take(1, source)[0]
      error(source, 'invalid argument') if n.negative? || n % 8 != 0
      @memory.concat(Array.new(n / 8, 0))
    when 'HEX', 'DECIMAL'
      @memory[0] = key == 'HEX' ? 16 : 10
    when 'CREATE', 'VARIABLE', 'CONSTANT', 'VALUE', 'DEFER'
      name = check_name(read_name(source))
      value = %w[CONSTANT VALUE].include?(key) ? take(1, source)[0] : nil
      here = @memory.length * 8
      stored = %w[CREATE VARIABLE VALUE].include?(key) ? here : value
      @dictionary << ForthWord.new(name, key.downcase.to_sym, stored, here)
      @memory << (key == 'VARIABLE' ? 0 : value) if %w[VARIABLE VALUE].include?(key)
    when "'"
      name = read_name(source)
      word = lookup(name) || error(name, 'undefined word')
      push(token(word), source)
    when 'EXECUTE'
      execute_token(take(1, source)[0], source)
    when 'CATCH'
      xt = take(1, source)[0]
      error(source, 'invalid argument') unless valid_token?(xt)
      saved = @stack.dup
      saved_returns = @returns.length
      saved_depth = @depth
      begin
        execute_token(xt, source)
      rescue ForthError => exception
        raise if exception.code.nil?
        @stack = saved
        @returns.slice!(saved_returns..-1) if @returns.length > saved_returns
        @depth = saved_depth
        push(exception.code, source)
      else
        push(0, source)
      end
    when 'THROW'
      n = take(1, source)[0]
      error(source, "exception #{n}", n) unless n == 0
    when 'ABORT'
      error(source, 'aborted')
    when 'WORDS'
      @dictionary.reverse_each { |word| @pending << word.name + ' ' }
    end
  end

  def run
    STDIN.each_line do |input|
      @line = input.delete_suffix("\n")
      if @line == 'BYE'
        puts "ERROR #{@definition_name}: unterminated definition" if @compiling
        break
      end
      @position = 0
      begin
        while (source = read_word)
          process(source)
        end
      rescue ForthError => exception
        flush unless @pending.empty?
        puts "ERROR #{exception.word}: #{exception.reason}"
        @stack.clear
        @returns.clear
        @depth = 0
        @compiling = nil
      end
      flush unless @pending.empty?
    end
  end
end

Forth.new.run
