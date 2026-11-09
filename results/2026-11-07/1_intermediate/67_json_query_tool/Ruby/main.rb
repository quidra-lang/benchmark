class JsonFault < StandardError
  attr_reader :position
  def initialize(message, position)
    super(message)
    @position = position
  end
end

class StrictJson
  attr_reader :position
  def initialize(text)
    @text = text
    @position = 0
  end
  def fail_at(reason, position = @position)
    raise JsonFault.new(reason, position)
  end
  def whitespace
    @position += 1 while [' ', "\n"].include?(@text[@position])
  end
  def string
    @position += 1
    output = +''
    loop do
      char = @text[@position]
      fail_at('unterminated string') if char.nil? || char == "\n"
      if char == '"'
        @position += 1
        return output
      end
      if char == '\\'
        start = @position
        escaped = @text[@position + 1]
        fail_at('unterminated string', start + 1) if escaped.nil? || escaped == "\n"
        if escaped == 'u'
          hex = @text[@position + 2, 4]
          fail_at('bad unicode escape', start) unless hex && hex.match?(/\A[0-9A-Fa-f]{4}\z/)
          fail_at('non-ascii escape', start) if hex.to_i(16) > 127
          output << hex.to_i(16).chr
          @position += 6
        else
          escapes = { '"' => '"', '\\' => '\\', '/' => '/', 'b' => "\b", 'f' => "\f", 'n' => "\n", 'r' => "\r", 't' => "\t" }
          fail_at("invalid escape '\\#{escaped}'", start) unless escapes.key?(escaped)
          output << escapes[escaped]
          @position += 2
        end
      else
        output << char
        @position += 1
      end
    end
  end
  def value
    whitespace
    char = @text[@position]
    fail_at('unexpected end of input') if char.nil?
    if char == '{' || char == '['
      object = char == '{'
      result = object ? {} : []
      ending = object ? '}' : ']'
      @position += 1
      whitespace
      if @text[@position] == ending
        @position += 1
        return result
      end
      loop do
        if object
          whitespace
          fail_at('unexpected end of input') if @text[@position].nil?
          fail_at('expected key') unless @text[@position] == '"'
          key_start = @position
          key = string
          fail_at('duplicate key ' + JsonTool.quote(key), key_start) if result.key?(key)
          whitespace
          fail_at('unexpected end of input') if @text[@position].nil?
          fail_at("expected ':'") unless @text[@position] == ':'
          @position += 1
          result[key] = value
        else
          result << value
        end
        whitespace
        if @text[@position] == ending
          @position += 1
          return result
        end
        fail_at('unexpected end of input') if @text[@position].nil?
        fail_at("expected ',' or '#{ending}'") unless @text[@position] == ','
        @position += 1
        whitespace
        fail_at('trailing comma') if @text[@position] == ending
      end
    elsif char == '"'
      string
    elsif char == '-' || char.match?(/[0-9]/)
      start = @position
      @position += 1 if char == '-'
      digits_start = @position
      @position += 1 while @text[@position]&.match?(/[0-9]/)
      digits = @text[digits_start...@position]
      fail_at('invalid number', start) if digits.empty?
      fail_at('leading zero', digits_start) if digits.length > 1 && digits[0] == '0'
      fail_at('fraction not allowed') if @text[@position] == '.'
      fail_at('exponent not allowed') if ['e', 'E'].include?(@text[@position])
      fail_at('number out of range', start) if digits.length >= 10
      @text[start...@position].to_i
    elsif char.match?(/[A-Za-z]/)
      start = @position
      @position += 1 while @text[@position]&.match?(/[A-Za-z]/)
      word = @text[start...@position]
      fail_at("invalid literal '#{word}'", start) unless %w[true false null].include?(word)
      { 'true' => true, 'false' => false, 'null' => nil }[word]
    else
      fail_at("unexpected character '#{char}'")
    end
  end
  def read
    result = value
    whitespace
    fail_at('trailing characters') if @position < @text.length
    result
  end
end

class JsonTool
  INTEGER = /\A(?:0|-?[1-9][0-9]{0,8})\z/
  IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  MISSING = Object.new.freeze
  COMMANDS = %w[LOAD GET COMPACT PRETTY TYPE LENGTH KEYS FLATTEN COUNT SUM MIN MAX AVG FILTER SET DELETE INSERT MERGE SORT RENAME UNDO].freeze
  def self.quote(text, delimiter = '"')
    escapes = { "\b" => '\\b', "\f" => '\\f', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t' }
    delimiter + text.each_char.map do |char|
      if char == delimiter || char == '\\'
        '\\' + char
      elsif escapes.key?(char)
        escapes[char]
      elsif char.ord < 32 || char.ord == 127
        format('\\u%04x', char.ord)
      else
        char
      end
    end.join + delimiter
  end
  def initialize
    @document = nil
    @history = []
  end
  def copy(value)
    Marshal.load(Marshal.dump(value))
  end
  def type(value)
    case value
    when Hash then 'object'
    when Array then 'array'
    when String then 'string'
    when Integer then 'number'
    when true, false then 'boolean'
    else 'null'
    end
  end
  def compact(value)
    case value
    when Hash then '{' + value.map { |key, item| self.class.quote(key) + ':' + compact(item) }.join(',') + '}'
    when Array then '[' + value.map { |item| compact(item) }.join(',') + ']'
    when String then self.class.quote(value)
    when nil then 'null'
    else value.to_s
    end
  end
  def pretty(value, indent = '')
    return compact(value) unless (value.is_a?(Hash) || value.is_a?(Array)) && !value.empty?
    next_indent = indent + '  '
    if value.is_a?(Hash)
      items = value.map { |key, item| next_indent + self.class.quote(key) + ': ' + pretty(item, next_indent) }
      "{\n" + items.join(",\n") + "\n#{indent}}"
    else
      "[\n" + value.map { |item| next_indent + pretty(item, next_indent) }.join(",\n") + "\n#{indent}]"
    end
  end
  def quoted_key(text, position)
    raise 'bad' unless text[position] == "'"
    position += 1
    output = +''
    while position < text.length
      char = text[position]
      return [output, position + 1] if char == "'"
      if char == '\\'
        escaped = text[position + 1]
        if escaped == 'u'
          hex = text[position + 2, 4]
          raise 'bad' unless hex && hex.match?(/\A[0-9a-fA-F]{4}\z/) && hex.to_i(16) <= 127
          output << hex.to_i(16).chr
          position += 6
        else
          escapes = { "'" => "'", '\\' => '\\', '/' => '/', 'b' => "\b", 'f' => "\f", 'n' => "\n", 'r' => "\r", 't' => "\t" }
          raise 'bad' unless escapes.key?(escaped)
          output << escapes[escaped]
          position += 2
        end
      else
        output << char
        position += 1
      end
    end
    raise 'bad'
  end
  def path(text, field = false)
    begin
      raise 'bad' unless text && text[0] == (field ? '@' : '$')
      position = 1
      selectors = []
      while position < text.length
        descendant = false
        if text[position, 2] == '..' && !field
          descendant = true
          position += 2
        elsif text[position] == '.'
          position += 1
          match = /\A(?:[A-Za-z_][A-Za-z0-9_]*|\*)/.match(text[position..])
          raise 'bad' unless match && (!field || match[0] != '*')
          word = match[0]
          selectors << [false, word == '*' ? :all : :key, word]
          position += word.length
          next
        elsif text[position] != '['
          raise 'bad'
        end
        if text[position] == '['
          position += 1
          if text[position] == "'"
            key, position = quoted_key(text, position)
            kind = :key
          else
            finish = text.index(']', position)
            raise 'bad' unless finish
            word = text[position...finish]
            position = finish
            if INTEGER.match?(word)
              kind = :index
              key = word.to_i
            elsif word == '*' && !field
              kind = :all
              key = nil
            elsif !field && word.count(':') == 1 && word.split(':', -1).all? { |part| part.empty? || INTEGER.match?(part) }
              kind = :slice
              key = word.split(':', -1).map { |part| part.empty? ? nil : part.to_i }
            else
              raise 'bad'
            end
          end
          raise 'bad' unless text[position] == ']'
          position += 1
        elsif descendant
          match = /\A(?:[A-Za-z_][A-Za-z0-9_]*|\*)/.match(text[position..])
          raise 'bad' unless match
          key = match[0]
          kind = key == '*' ? :all : :key
          position += key.length
        else
          raise 'bad'
        end
        selectors << [descendant, kind, key]
      end
      selectors
    rescue RuntimeError
      raise(field ? 'ERROR bad field' : 'ERROR bad path')
    end
  end
  def location(steps)
    '$' + steps.map { |step| step.is_a?(Integer) ? "[#{step}]" : (IDENTIFIER.match?(step) ? '.' + step : '[' + self.class.quote(step, "'") + ']') }.join
  end
  def children(match)
    value, steps, positions = match
    if value.is_a?(Hash)
      value.each_with_index.map { |(key, item), index| [item, steps + [key], positions + [index]] }
    elsif value.is_a?(Array)
      value.each_with_index.map { |item, index| [item, steps + [index], positions + [index]] }
    else
      []
    end
  end
  def preorder(match)
    [match] + children(match).flat_map { |child| preorder(child) }
  end
  def select(match, selector)
    _, kind, key = selector
    value = match[0]
    all = children(match)
    case kind
    when :key then value.is_a?(Hash) ? all.select { |item| item[1].last == key } : []
    when :all then all
    when :index
      return [] unless value.is_a?(Array)
      index = key < 0 ? value.length + key : key
      index.between?(0, value.length - 1) ? [all[index]] : []
    when :slice
      return [] unless value.is_a?(Array)
      bounds = [key[0] || 0, key[1] || value.length].map { |n| [[n < 0 ? n + value.length : n, 0].max, value.length].min }
      bounds[0] < bounds[1] ? all[bounds[0]...bounds[1]] : []
    end
  end
  def evaluate(selectors, initial = [[@document, [], []]])
    selectors.reduce(initial) do |matches, selector|
      matches.flat_map { |match| (selector[0] ? preorder(match) : [match]).flat_map { |item| select(item, selector) } }
    end
  end
  def field(value, selectors)
    result = evaluate(selectors, [[value, [], []]])
    result.empty? ? MISSING : result[0][0]
  end
  def at(steps)
    steps.reduce(@document) { |value, step| value[step] }
  end
  def assign(steps, value)
    if steps.empty?
      @document = value
    else
      at(steps[0...-1])[steps[-1]] = value
    end
  end
  def merge(target, source)
    source.each do |key, value|
      if target[key].is_a?(Hash) && value.is_a?(Hash)
        merge(target[key], value)
      else
        target[key] = copy(value)
      end
    end
  end
  def parse(text)
    StrictJson.new(text).read
  rescue JsonFault => error
    raise "PARSE ERROR col #{error.position + 1}: #{error.message}"
  end
  def ensure_kind(matches, wanted, message)
    bad = matches.find { |item| !wanted.include?(type(item[0])) }
    raise "ERROR #{message} at #{location(bad[1])}" if bad
  end
  def command(line)
    command, argument = line.split(' ', 2)
    raise "ERROR unknown command '#{command}'" unless COMMANDS.include?(command)
    count = { 'SET' => 2, 'MERGE' => 2, 'INSERT' => 3, 'FILTER' => 4 }[command]
    args = argument ? argument.split(/ /, count || -1) : []
    if %w[SET MERGE INSERT].include?(command)
      raise 'ERROR bad arguments' unless args.length == count
    elsif command == 'FILTER'
      raise 'ERROR bad arguments' unless args.length >= 3 && (args[2] == 'EXISTS' ? args.length == 3 : args.length == 4)
    elsif command == 'SORT'
      raise 'ERROR bad arguments' unless args.length.between?(1, 3) && (args.length < 3 || (args[1] != 'DESC' && args[2] == 'DESC'))
    else
      expected = %w[COMPACT PRETTY FLATTEN].include?(command) ? [0, 1] : (command == 'UNDO' ? [0] : command == 'RENAME' ? [2] : [1])
      raise 'ERROR bad arguments' unless expected.include?(args.length)
    end
    if command == 'UNDO'
      raise 'ERROR nothing to undo' if @history.empty?
      @document = @history.pop
      puts "UNDO #{@history.length}"
      return
    end
    selectors = path(args[0] || '$')
    field_selectors = nil
    if command == 'FILTER'
      field_selectors = path(args[1], true)
      raise 'ERROR bad operator' unless %w[== != < <= > >= EXISTS].include?(args[2])
    elsif command == 'SORT'
      field_selectors = path(args.length >= 2 && args[1] != 'DESC' ? args[1] : '@', true)
    elsif command == 'INSERT'
      raise 'ERROR bad index' unless INTEGER.match?(args[1])
    elsif command == 'RENAME'
      begin
        if IDENTIFIER.match?(args[1])
          new_key = args[1]
        else
          new_key, ending = quoted_key(args[1], 0)
          raise 'bad' unless ending == args[1].length
        end
      rescue RuntimeError
        raise 'ERROR bad key'
      end
    elsif command == 'DELETE'
      raise 'ERROR cannot delete root' if selectors.empty?
    end
    replacement = parse(args[-1]) if %w[SET MERGE INSERT].include?(command) || (command == 'FILTER' && args[2] != 'EXISTS')
    raise 'ERROR merge value is not an object' if command == 'MERGE' && !replacement.is_a?(Hash)
    matches = evaluate(selectors)
    case command
    when 'LENGTH' then ensure_kind(matches, %w[object array string], 'no length')
    when 'KEYS', 'MERGE' then ensure_kind(matches, ['object'], 'not an object')
    when 'FILTER', 'INSERT', 'SORT' then ensure_kind(matches, ['array'], 'not an array')
    when 'RENAME'
      bad = matches.find { |item| item[1].empty? || !item[1].last.is_a?(String) }
      raise "ERROR not a member at #{location(bad[1])}" if bad
    end
    if command == 'INSERT'
      index = args[1].to_i
      bad = matches.find { |item| !index.between?(-item[0].length - 1, item[0].length) }
      raise "ERROR index out of range at #{location(bad[1])}" if bad
    end
    if %w[SET DELETE INSERT MERGE SORT RENAME].include?(command)
      if command == 'SET' && !selectors.empty? && selectors[-1][0] == false && selectors[-1][1] == :key
        key = selectors[-1][2]
        matches = evaluate(selectors[0...-1]).filter_map do |parent|
          next unless parent[0].is_a?(Hash)
          index = parent[0].keys.index(key) || parent[0].length
          [parent[0][key], parent[1] + [key], parent[2] + [index]]
        end
      end
      targets = matches.uniq { |item| item[1] }.sort { |a, b| b[2] <=> a[2] }
      original = copy(@document)
      begin
        targets.each do |_, steps, _|
          value = at(steps) unless command == 'SET'
          case command
          when 'SET' then assign(steps, copy(replacement))
          when 'DELETE'
            parent = at(steps[0...-1])
            parent.is_a?(Array) ? parent.delete_at(steps[-1]) : parent.delete(steps[-1])
          when 'INSERT' then value.insert(index < 0 ? value.length + 1 + index : index, copy(replacement))
          when 'MERGE' then merge(value, replacement)
          when 'SORT'
            descending = args[-1] == 'DESC'
            decorated = value.each_with_index.map { |item, i| [field(item, field_selectors), i, item] }
            decorated.sort! do |a, b|
              key = lambda do |v|
                case v
                when nil then [0, 0]
                when Integer then [1, v]
                when String then [2, v]
                else [3, 0]
                end
              end
              comparison = key.call(a[0]) <=> key.call(b[0])
              comparison = -comparison if descending
              comparison == 0 ? a[1] <=> b[1] : comparison
            end
            value.replace(decorated.map { |item| item[2] })
          when 'RENAME'
            parent = at(steps[0...-1])
            key = steps[-1]
            raise "ERROR key exists at #{location(steps)}" if key != new_key && parent.key?(new_key)
            assign(steps[0...-1], parent.to_h { |name, item| [name == key ? new_key : name, item] })
          end
        end
      rescue RuntimeError
        @document = original
        raise
      end
      @history << original
      puts "#{command} #{targets.length}"
    elsif %w[COUNT SUM MIN MAX AVG].include?(command)
      numbers = matches.map(&:first).select { |value| value.is_a?(Integer) }
      if command == 'COUNT'
        puts "COUNT #{matches.length}"
      elsif command == 'AVG'
        if numbers.empty?
          puts 'AVG null'
        else
          sum = numbers.sum
          rounded = (sum.abs * 200 + numbers.length) / (2 * numbers.length)
          puts format('AVG %s%d.%02d', sum < 0 && rounded > 0 ? '-' : '', rounded / 100, rounded % 100)
        end
      else
        result = command == 'SUM' ? numbers.sum : numbers.public_send(command.downcase)
        puts "#{command} #{result.nil? ? 'null' : result}"
      end
    else
      output = []
      matches.each do |match|
        value, steps, = match
        case command
        when 'GET' then output << "#{location(steps)} = #{compact(value)}"
        when 'COMPACT' then output << compact(value)
        when 'PRETTY' then output << pretty(value)
        when 'TYPE' then output << "#{location(steps)} #{type(value)}"
        when 'LENGTH' then output << "#{location(steps)} #{value.length}"
        when 'KEYS' then output << "#{location(steps)} #{compact(value.keys)}"
        when 'FLATTEN'
          preorder(match).each { |item| output << "#{location(item[1])} = #{compact(item[0])}" if children(item).empty? }
        when 'FILTER'
          children(match).each do |item|
            f = field(item[0], field_selectors)
            operator = args[2]
            equal = !f.equal?(MISSING) && type(f) == type(replacement) && f == replacement
            pass = if operator == 'EXISTS'
                     !f.equal?(MISSING)
                   elsif operator == '==' then equal
                   elsif operator == '!=' then !equal
                   elsif (f.is_a?(Integer) && replacement.is_a?(Integer)) || (f.is_a?(String) && replacement.is_a?(String))
                     f.public_send(operator, replacement)
                   else false
                   end
            output << "#{location(item[1])} = #{compact(item[0])}" if pass
          end
        end
      end
      puts(output.empty? ? ['no match'] : output)
    end
  rescue RuntimeError => error
    puts error.message
  end
  def load_document(lines)
    text = lines.join("\n")
    begin
      value = StrictJson.new(text).read
      @history << copy(@document)
      @document = value
      stats = lambda do |item|
        children = item.is_a?(Hash) ? item.values : item.is_a?(Array) ? item : []
        nested = children.map { |child| stats.call(child) }
        [1 + nested.sum(&:first), 1 + (nested.map(&:last).max || 0)]
      end
      count, depth = stats.call(value)
      puts "LOADED nodes=#{count} depth=#{depth}"
    rescue JsonFault => error
      prefix = text[0...error.position]
      number = prefix.count("\n") + 1
      column = error.position - (prefix.rindex("\n") || -1)
      puts "PARSE ERROR line #{number} col #{column}: #{error.message}"
    end
  end
  def run
    input = STDIN.each_line.map { |line| line.chomp("\n").delete_suffix("\r") }
    position = 0
    loop do
      block = []
      while input[position] != '%%'
        block << input[position]
        position += 1
      end
      position += 1
      load_document(block)
      while input[position] != 'LOAD' && input[position] != 'END'
        command(input[position])
        position += 1
      end
      break if input[position] == 'END'
      position += 1
    end
  end
end

JsonTool.new.run
