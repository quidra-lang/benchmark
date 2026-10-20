require_relative 'lexer'
require_relative 'parser'
require_relative 'values_fields'
require_relative 'builtins'
require_relative 'streams'

class AwkInterpreter
  SPECIALS = %w[FILENAME FNR FS NF NR OFS ORS SUBSEP].freeze
  class Flow < StandardError
    attr_reader :kind, :value
    def initialize(kind, value = Value::UNSET)
      @kind, @value = kind, value
      super(kind.to_s)
    end
  end

  def initialize(program, arguments)
    @parser = Parser.new(Lexer.new(program).tokens).parse
    @rules, @functions = @parser.rules, @parser.functions
    @function_map = @functions.to_h { |function| [function[:name].text, function] }
    @references, @calls, @arrays = [], [], {}
    @functions.each { |function| analyze_node(function[:body], function) }
    @rules.each do |rule|
      [rule[:first], rule[:last], rule[:action]].each { |tree| analyze_node(tree, nil) }
    end
    @static_error = static_checks
    return if @static_error
    infer_arrays
    @globals = SPECIALS.to_h { |name| [name, Value::UNSET] }
    @references.each do |token, function, _|
      @globals[token.text] = Value::UNSET if scope_key(token.text, function)[0].nil?
    end
    @arrays.each_key { |scope, name| @globals[name] = {} if scope.nil? }
    @globals.merge!('FS' => Value.string(' '), 'OFS' => Value.string(' '), 'ORS' => Value.string("\n"),
                    'SUBSEP' => Value.string(28.chr), 'NR' => Value.number(0), 'FNR' => Value.number(0),
                    'FILENAME' => Value.string(''))
    @fields, @frames, @streams = Fields.new, [], Streams.new(arguments)
    @line_counts = @parser.statement_lines.dup
    @exit_status, @phase = 0, :BEGIN
  end

  def scope_key(name, function)
    local = function && function[:parameters].any? { |parameter| parameter.text == name }
    [local ? function[:name].text : nil, name]
  end

  def reference(token, function, array = false)
    @references << [token, function, array]
  end

  def analyze_node(tree, function)
    return unless tree.is_a?(Node)
    a = tree.args
    case tree.kind
    when :variable then reference(tree.token, function)
    when :array then reference(tree.token, function, true)
    when :in then reference(a[1], function, true)
    when :delete then reference(a[0], function, true)
    when :forin
      reference(a[0], function)
      reference(a[1], function, true)
    when :call then @calls << [tree, function]
    when :builtin
      reference(a[0][1].token, function, true) if tree.token.text == 'split'
    end
    visit = lambda do |value|
      if value.is_a?(Node)
        analyze_node(value, function)
      elsif value.is_a?(Array)
        value.each { |child| visit.call(child) }
      end
    end
    a.each { |value| visit.call(value) }
  end

  def static_checks
    errors, seen = [], {}
    add = ->(rank, token, message) { errors << [token.line, token.column, rank, token, message] }
    @functions.each do |function|
      name = function[:name]
      add.call(0, name, "function #{name.text} redefined") if seen[name.text]
      seen[name.text] = true
      parameters = {}
      function[:parameters].each do |parameter|
        add.call(1, parameter, "duplicate parameter #{parameter.text}") if parameters[parameter.text]
        parameters[parameter.text] = true
        add.call(2, parameter, "function #{parameter.text} used as variable") if @function_map.key?(parameter.text)
      end
    end
    @references.each do |token, _function, _array|
      add.call(2, token, "function #{token.text} used as variable") if @function_map.key?(token.text)
    end
    @calls.each do |tree, _|
      function = @function_map[tree.token.text]
      if !function
        add.call(3, tree.token, "undefined function #{tree.token.text}")
      elsif tree.args[0].length > function[:parameters].length
        add.call(4, tree.token, "too many arguments to #{tree.token.text}")
      end
    end
    first = errors.min_by { |line, column, rank, _token, _message| [line, column, rank] }
    first && "status: error at #{first[3].position}: #{first[4]}"
  end

  def infer_arrays
    @references.each { |token, function, array| @arrays[scope_key(token.text, function)] = true if array }
    links = []
    @calls.each do |tree, caller|
      function = @function_map.fetch(tree.token.text)
      tree.args[0].each_with_index do |argument, index|
        next unless argument.kind == :variable
        parameter = function[:parameters][index]
        links << [scope_key(argument.token.text, caller), scope_key(parameter.text, function)]
      end
    end
    loop do
      previous = @arrays.length
      links.each do |left, right|
        if @arrays[left] || @arrays[right]
          @arrays[left] = @arrays[right] = true
        end
      end
      break if previous == @arrays.length
    end
  end

  def environment(name)
    !@frames.empty? && @frames[-1].key?(name) ? @frames[-1] : @globals
  end

  def array(name)
    environment(name).fetch(name)
  end

  def global_string(name)
    @globals.fetch(name).string
  end

  def subscript(expressions)
    values = expressions.map { |expression| evaluate(expression).string }
    values.join(global_string('SUBSEP'))
  end

  def location(tree)
    case tree.kind
    when :variable then [:variable, environment(tree.token.text), tree.token.text]
    when :array
      target = array(tree.token.text)
      [:element, target, subscript(tree.args[0])]
    when :field
      index = evaluate(tree.args[0]).number
      raise AwkRuntimeError.new('negative field index', tree.token) if index.negative?
      [:field, index]
    end
  end

  def read(location)
    kind, container, key = location
    if kind == :field
      @fields.read(container)
    elsif kind == :variable && container.equal?(@globals) && key == 'NF'
      Value.number(@fields.fields.length)
    else
      container[key] = Value::UNSET unless container.key?(key)
      container[key]
    end
  end

  def store(location, value, token)
    kind, container, key = location
    if kind == :field
      @fields.assign(container, value, global_string('FS'), global_string('OFS'))
    elsif kind == :variable && container.equal?(@globals) && key == 'NF'
      n = value.number
      raise AwkRuntimeError.new('negative NF', token) if n.negative?
      @fields.resize(n, global_string('OFS'))
    else
      container[key] = value
    end
    read(location)
  end

  def boolean(truth)
    Value.number(truth ? 1 : 0)
  end

  def arithmetic(operator, left, right, token)
    a, b = left.number, right.number
    if ['/', '%'].include?(operator)
      raise AwkRuntimeError.new('division by zero', token) if b.zero?
      quotient = a.abs / b.abs
      quotient = -quotient if a.negative? != b.negative?
      return Value.number(operator == '/' ? quotient : a - quotient * b)
    end
    raise AwkRuntimeError.new('negative exponent', token) if operator == '^' && b.negative?
    Value.number(case operator
                 when '+' then a + b
                 when '-' then a - b
                 when '*' then a * b
                 when '^' then a**b
                 end)
  end

  def evaluate(tree)
    a, b, c = tree.args
    token = tree.token
    case tree.kind
    when :number then Value.number(token.value)
    when :string then Value.string(token.value)
    when :variable, :array, :field then read(location(tree))
    when :parentheses then evaluate(a)
    when :assign
      target = location(a)
      value = evaluate(b)
      value = arithmetic(token.text[0], read(target), value, token) unless token.text == '='
      store(target, value, token)
    when :increment
      target = location(a)
      old = read(target).number
      value = Value.number(old + (token.text == '++' ? 1 : -1))
      store(target, value, token)
      b ? value : Value.number(old)
    when :conditional then evaluate(evaluate(a).truth ? b : c)
    when :in
      key = subscript(a)
      boolean(array(b.text).key?(key))
    when :concat
      left = evaluate(a).string
      Value.string(left + evaluate(b).string)
    when :unary
      value = evaluate(a)
      case token.text
      when '!' then boolean(!value.truth)
      when '+' then Value.number(value.number)
      when '-' then Value.number(-value.number)
      end
    when :binary
      left = evaluate(a)
      if token.text == '||'
        boolean(left.truth || evaluate(b).truth)
      elsif token.text == '&&'
        boolean(left.truth && evaluate(b).truth)
      else
        right = evaluate(b)
        if %w[< <= == != >= >].include?(token.text)
          comparison = left.compare(right)
          boolean(case token.text
                  when '<' then comparison < 0
                  when '<=' then comparison <= 0
                  when '==' then comparison == 0
                  when '!=' then comparison != 0
                  when '>=' then comparison >= 0
                  when '>' then comparison > 0
                  end)
        else
          arithmetic(token.text, left, right, token)
        end
      end
    when :call then call_function(tree)
    when :builtin then call_builtin(tree)
    when :getline then getline(tree)
    end
  end

  def call_function(tree)
    function = @function_map.fetch(tree.token.text)
    arguments, frame = tree.args[0], {}
    function[:parameters].each_with_index do |parameter, index|
      argument = arguments[index]
      frame[parameter.text] = if @arrays[scope_key(parameter.text, function)]
                                argument ? array(argument.token.text) : {}
                              else
                                argument ? evaluate(argument) : Value::UNSET
                              end
    end
    @frames << frame
    function[:calls] += 1
    function[:active] += 1
    function[:depth] = [function[:depth], function[:active]].max
    begin
      execute(function[:body])
      Value::UNSET
    rescue Flow => flow
      raise unless flow.kind == :return
      flow.value
    ensure
      function[:active] -= 1
      @frames.pop
    end
  end

  def call_builtin(tree)
    arguments, token = tree.args[0], tree.token
    case token.text
    when 'length'
      if arguments.empty?
        Value.number(@fields.record.string.length)
      elsif arguments[0].kind == :variable && environment(arguments[0].token.text)[arguments[0].token.text].is_a?(Hash)
        Value.number(array(arguments[0].token.text).length)
      else
        Value.number(evaluate(arguments[0]).string.length)
      end
    when 'split'
      text = evaluate(arguments[0]).string
      separator = arguments[2] ? evaluate(arguments[2]).string : global_string('FS')
      target = array(arguments[1].token.text)
      target.clear
      pieces = Value.split(text, separator)
      pieces.each_with_index { |piece, index| target[(index + 1).to_s] = Value.input(piece) }
      Value.number(pieces.length)
    when 'close'
      Value.number(@streams.close(evaluate(arguments[0]).string))
    else
      values = arguments.map { |argument| evaluate(argument) }
      Builtins.call(token.text, values, token)
    end
  end

  def main_record
    return nil if @phase == :END
    record = @streams.read_main do |kind, name, value|
      if kind == :assignment
        @globals[name] = Value.input(value)
      else
        @globals['FILENAME'] = Value.string(name)
        @globals['FNR'] = Value.number(0)
      end
    end
    if record
      %w[NR FNR].each { |name| @globals[name] = Value.number(@globals[name].number + 1) }
    end
    record
  end

  def getline(tree)
    target, file = tree.args
    if file
      status, text = @streams.read_getline(evaluate(file).string)
    else
      text = main_record
      status = text ? 1 : 0
    end
    if status == 1
      if target
        store(location(target), Value.input(text), tree.token)
      else
        @fields.set(text, global_string('FS'))
      end
    end
    Value.number(status)
  end

  def output(tree)
    arguments, redirect = tree.args
    values = arguments.map { |argument| evaluate(argument) }
    text = if tree.token.text == 'print'
             values = [@fields.record] if values.empty?
             values.map(&:string).join(global_string('OFS')) + global_string('ORS')
           else
             Builtins.format_values(values, tree.token)
           end
    if redirect
      operator, expression = redirect
      @streams.write(text, evaluate(expression).string, operator.text, operator)
    else
      @streams.write(text)
    end
  end

  def loop_iteration(body)
    execute(body)
    :normal
  rescue Flow => flow
    raise unless [:break, :continue].include?(flow.kind)
    flow.kind
  end

  def execute(tree)
    return unless tree
    a, b, c, d = tree.args
    @line_counts[tree.token.line] += 1 unless [:block, :empty].include?(tree.kind)
    case tree.kind
    when :block then a.each { |statement| execute(statement) }
    when :empty then nil
    when :expression then evaluate(a)
    when :if then execute(evaluate(a).truth ? b : c)
    when :while
      while evaluate(a).truth
        break if loop_iteration(b) == :break
      end
    when :do
      loop do
        break if loop_iteration(b) == :break
        break unless evaluate(a).truth
      end
    when :for
      evaluate(a) if a
      while !b || evaluate(b).truth
        break if loop_iteration(d) == :break
        evaluate(c) if c
      end
    when :forin
      keys = Value.sorted_keys(array(b.text))
      keys.each do |key|
        store([:variable, environment(a.text), a.text], Value.input(key), a)
        break if loop_iteration(c) == :break
      end
    when :delete
      target = array(a.text)
      b ? target.delete(subscript(b)) : target.clear
    when :output then output(tree)
    when :next
      raise AwkRuntimeError.new('next used in BEGIN or END', tree.token) if [:BEGIN, :END].include?(@phase)
      raise Flow.new(:next)
    when :break, :continue then raise Flow.new(tree.kind)
    when :return then raise Flow.new(:return, a ? evaluate(a) : Value::UNSET)
    when :exit
      @exit_status = evaluate(a).number if a
      raise Flow.new(:exit)
    end
  end

  def execute_rule(rule)
    rule[:count] += 1
    if rule[:action]
      execute(rule[:action])
    else
      @streams.write(@fields.record.string + global_string('ORS'))
    end
  end

  def run_rules
    @rules.each do |rule|
      matches = case rule[:kind]
                when 'all' then true
                when 'pattern' then evaluate(rule[:first]).truth
                when 'range'
                  rule[:inside] = evaluate(rule[:first]).truth unless rule[:inside]
                  inside = rule[:inside]
                  rule[:inside] = false if inside && evaluate(rule[:last]).truth
                  inside
                else false
                end
      execute_rule(rule) if matches
    end
  rescue Flow => flow
    raise unless flow.kind == :next
  end

  def run
    if @static_error
      File.write('output/stdout.txt', '')
      File.write('output/stats.txt', @static_error + "\n")
      return
    end
    @streams.options.each { |name, value| @globals[name] = Value.input(value) }
    status = nil
    begin
      begin
        @rules.each { |rule| execute_rule(rule) if rule[:kind] == 'BEGIN' }
        if @rules.any? { |rule| rule[:kind] != 'BEGIN' }
          @phase = :record
          while (record = main_record)
            @fields.set(record, global_string('FS'))
            run_rules
          end
        end
      rescue Flow => flow
        raise unless flow.kind == :exit
      end
      @phase = :END
      begin
        @rules.each { |rule| execute_rule(rule) if rule[:kind] == 'END' }
      rescue Flow => flow
        raise unless flow.kind == :exit
      end
    rescue AwkRuntimeError => error
      status = "status: runtime error at #{error.token.position}: #{error.message}"
    end
    status ||= "status: exit #{@exit_status}"
    @streams.save
    File.write('output/stats.txt', statistics(status).join("\n") + "\n")
  end

  def statistics(status)
    lines = [status, '[inputs]']
    @streams.operands.each { |item| lines << "#{item[:name]} records=#{item[:records]}" if item[:kind] == :file }
    lines << '[getline]'
    @streams.getlines.each do |name, entry|
      lines << (entry[:opened] ? "#{name} reads=#{entry[:reads]}" : "#{name} missing")
    end
    lines << '[rules]'
    @rules.each { |rule| lines << "#{rule[:token].position} #{rule[:kind]} count=#{rule[:count]}" }
    lines << '[functions]'
    @functions.each { |function| lines << "#{function[:name].text} calls=#{function[:calls]} depth=#{function[:depth]}" }
    lines << '[outputs]'
    @streams.outputs.each { |name, entry| lines << "#{name} writes=#{entry[:writes]} bytes=#{entry[:text].length}" }
    lines << '[lines]'
    @line_counts.sort.each { |line, count| lines << "#{line} count=#{count}" }
    lines << '[globals]'
    @globals.keys.sort.each do |name|
      value = name == 'NF' ? Value.number(@fields.fields.length) : @globals[name]
      lines << "#{name} = #{value.is_a?(Hash) ? "array (#{value.length})" : value.display}"
    end
    lines
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    interpreter = AwkInterpreter.new(File.read('input/program.awk'), File.readlines('input/args.txt', chomp: true))
    interpreter.run
  rescue AwkSyntaxError => error
    File.write('output/stdout.txt', '')
    File.write('output/stats.txt', error.message + "\n")
  end
end
