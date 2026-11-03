class TemplateError < StandardError
  attr_accessor :line

  def initialize(message, line = nil)
    super(message)
    @line = line
  end
end

class TemplateEngine
  IDENTIFIER = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  NAME = /\A(?:\.|@(?:index|number|first|last)|(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*)(?:\.(?:[A-Za-z_][A-Za-z0-9_]*|0|[1-9][0-9]*))*)\z/
  NO_ARGUMENTS = %w[upper lower title trim length first last reverse items comma sum min max].freeze
  FILTERS = (NO_ARGUMENTS + %w[default eq pad lpad truncate replace join sort pluck add sub mul div mod gt lt]).freeze

  def initialize
    @root = {}
    @partials = {}
    @templates = {}
    @strict = false
  end

  def strip_spaces(text)
    text.gsub(/\A +| +\z/, '')
  end

  def fail_with(reason, line = nil)
    raise TemplateError.new(reason, line)
  end

  def parse_key(key)
    return nil unless key.match?(/\A[A-Za-z_][A-Za-z0-9_]*(?:(?:\.[A-Za-z_][A-Za-z0-9_]*)|(?:\[(?:0|[1-9][0-9]*)\]))*\z/)

    parts = []
    key.scan(/[A-Za-z_][A-Za-z0-9_]*|\[(0|[1-9][0-9]*)\]/) do
      match = Regexp.last_match
      parts << [match[1] ? match[1].to_i : match[0], key[0...match.end(0)]]
    end
    parts
  end

  def scalar(text, offset)
    if text[offset] == '"'
      result = +''
      pos = offset + 1
      while pos < text.length
        char = text[pos]
        return [result, pos + 1] if char == '"'
        if char == '\\'
          pos += 1
          char = { '"' => '"', '\\' => '\\', 'n' => "\n" }[text[pos]]
          raise ArgumentError if char.nil?
        end
        result << char
        pos += 1
      end
      raise ArgumentError
    end
    match = /\A(?:0|-?[1-9][0-9]*|true|false)/.match(text[offset..])
    raise ArgumentError unless match

    word = match[0]
    value = case word
            when 'true' then true
            when 'false' then false
            else word.to_i
            end
    [value, offset + word.length]
  end

  def parse_value(text)
    return [] if text == '[]'
    return {} if text == '{}'
    if text.start_with?('[')
      result = []
      pos = 1
      loop do
        value, pos = scalar(text, pos)
        result << value
        return result if text[pos] == ']' && pos == text.length - 1
        raise ArgumentError unless text[pos, 2] == ', '

        pos += 2
      end
    else
      value, pos = scalar(text, 0)
      raise ArgumentError unless pos == text.length

      value
    end
  end

  def has_part?(value, part)
    (part.is_a?(String) && value.is_a?(Hash) && value.key?(part)) ||
      (part.is_a?(Integer) && value.is_a?(Array) && part < value.length)
  end

  def set_value(container, parts, value, index = 0)
    part, prefix = parts[index]
    fail_with("index gap at '#{prefix}'") if part.is_a?(Integer) && part > container.length
    if index == parts.length - 1
      container[part] = value
      return
    end
    required = parts[index + 1][0].is_a?(Integer) ? Array : Hash
    if has_part?(container, part)
      fail_with("type conflict at '#{prefix}'") unless container[part].is_a?(required)
    else
      container[part] = required.new
    end
    set_value(container[part], parts, value, index + 1)
  end

  def unset_value(container, parts, key, index = 0)
    part = parts[index][0]
    fail_with("no value at '#{key}'") unless has_part?(container, part)
    if index == parts.length - 1
      container.is_a?(Array) ? container.delete_at(part) : container.delete(part)
    else
      unset_value(container[part], parts, key, index + 1)
    end
  end

  def data(body)
    counts = { set: 0, unset: 0 }
    errors = []
    body.each do |text, line|
      next if text.empty? || text.start_with?('#')
      begin
        deleting = text.start_with?('UNSET ')
        if deleting
          key = text[6..]
        else
          fail_with('bad line') unless text.include?(' = ')
          key, notation = text.split(' = ', 2)
        end
        parts = parse_key(key)
        fail_with("bad key '#{key}'") unless parts
        unless deleting
          begin
            value = parse_value(notation)
          rescue ArgumentError
            fail_with("bad value '#{notation}'")
          end
        end
        changed = Marshal.load(Marshal.dump(@root))
        if deleting
          unset_value(changed, parts, key)
        else
          set_value(changed, parts, value)
        end
        @root = changed
        counts[deleting ? :unset : :set] += 1
      rescue TemplateError => error
        errors << "ERROR line #{line}: #{error.message}"
      end
    end
    puts "DATA set=#{counts[:set]} unset=#{counts[:unset]} errors=#{errors.length}"
    puts errors
  end

  def split_quoted(text, separator)
    result = []
    start = 0
    quoted = false
    text.each_char.with_index do |char, index|
      quoted = !quoted if char == "'"
      if char == separator && !quoted
        result << text[start...index]
        start = index + 1
      end
    end
    result << text[start..]
    result
  end

  def expression(text, line)
    pieces = split_quoted(text, '|').map { |part| strip_spaces(part) }
    name = pieces.shift
    fail_with("invalid name '#{name}'", line) unless NAME.match?(name)
    filters = pieces.map do |piece|
      filter, *arguments = split_quoted(piece, ':')
      fail_with("unknown filter '#{filter}'", line) unless FILTERS.include?(filter)
      valid = true
      args = arguments.map do |argument|
        if argument.match?(/\A'[^']*'\z/)
          argument[1...-1]
        elsif argument.match?(/\A-?[0-9]{1,9}\z/)
          argument.to_i
        else
          valid = false
          nil
        end
      end
      integers = args.all? { |arg| arg.is_a?(Integer) }
      strings = args.all? { |arg| arg.is_a?(String) }
      valid &&= if NO_ARGUMENTS.include?(filter)
                  args.empty?
                elsif %w[default eq].include?(filter)
                  args.length == 1
                elsif %w[pad lpad].include?(filter)
                  [1, 2].include?(args.length) && args[0].is_a?(Integer) && args[0] >= 0 &&
                    (args.length == 1 || (args[1].is_a?(String) && args[1].length == 1))
                elsif filter == 'truncate'
                  args.length == 1 && integers && args[0] >= 0
                elsif filter == 'replace'
                  args.length == 2 && strings && !args[0].empty?
                elsif %w[join pluck].include?(filter)
                  args.length == 1 && strings
                elsif filter == 'sort'
                  args.length <= 1 && strings
                else
                  args.length == 1 && integers && (!%w[div mod].include?(filter) || args[0] != 0)
                end
      fail_with("bad arguments for '#{filter}'", line) unless valid
      [filter, args]
    end
    [name, filters]
  end

  def analyze(body)
    opening = '{{'
    closing = '}}'
    tokens = []
    sections = []
    body.each do |text, line|
      local = []
      pos = 0
      loop do
        start = text.index(opening, pos)
        unless start
          local << { kind: :text, text: text[pos..], line: line }
          break
        end
        local << { kind: :text, text: text[pos...start], line: line }
        content_start = start + opening.length
        triple = text[content_start] == '{'
        content_start += 1 if triple
        finish_delimiter = triple ? '}' + closing : closing
        finish = text.index(finish_delimiter, content_start)
        fail_with('unclosed tag', line) unless finish
        content = strip_spaces(text[content_start...finish])
        pos = finish + finish_delimiter.length
        marker = triple ? '&' : content[0]
        kinds = { '#' => :section, '^' => :inverted, '/' => :close, '!' => :comment,
                  '>' => :partial, '&' => :raw, '=' => :delimiter }
        kind = triple ? :raw : kinds.fetch(marker, :variable)
        argument = triple || kind == :variable ? content : strip_spaces(content[1..])
        token = { kind: kind, line: line, text: argument, indent: '' }
        case kind
        when :variable, :raw, :section, :inverted
          token[:expression] = expression(argument, line)
          if [:section, :inverted].include?(kind)
            token[:name] = token[:expression][0]
            sections << token
          end
        when :close
          fail_with("invalid name '#{argument}'", line) unless NAME.match?(argument)
          fail_with("unexpected closing '#{argument}'", line) if sections.empty?
          expected = sections.last[:name]
          fail_with("mismatched closing '#{argument}', expected '#{expected}'", line) unless expected == argument
          sections.pop
        when :partial
          fail_with("invalid name '#{argument}'", line) unless IDENTIFIER.match?(argument)
        when :delimiter
          delimiters = content.length >= 2 && content.end_with?('=') ? content[1...-1].split(' ') : []
          fail_with('invalid delimiters', line) unless delimiters.length == 2 && delimiters.none? { |item| item.include?('=') }
          opening, closing = delimiters
        end
        local << token
      end
      tags = local.reject { |token| token[:kind] == :text }
      standalone = tags.length == 1 && [:section, :inverted, :close, :comment, :partial, :delimiter].include?(tags[0][:kind]) &&
                   local.select { |token| token[:kind] == :text }.all? { |token| token[:text].match?(/\A *\z/) }
      if standalone
        tags[0][:indent] = local[0][:text] if tags[0][:kind] == :partial
        tokens.concat(tags)
      else
        tokens.concat(local)
        tokens << { kind: :text, text: "\n", line: line }
      end
    end
    unless sections.empty?
      token = sections.last
      fail_with("unclosed section '#{token[:name]}'", token[:line])
    end
    root = []
    stack = [root]
    tokens.each do |token|
      if token[:kind] == :close
        stack.pop
      else
        stack.last << token
        if [:section, :inverted].include?(token[:kind])
          token[:children] = []
          stack << token[:children]
        end
      end
    end
    root
  end

  def stringify(value)
    case value
    when nil then ''
    when String then value
    when Integer then value.to_s
    when true then 'true'
    when false then 'false'
    when Array then value.map { |item| stringify(item) }.join(', ')
    else fail_with('cannot render map')
    end
  end

  def truthy?(value)
    !(value.nil? || value == false || value == 0 || (value.respond_to?(:empty?) && value.empty?))
  end

  def number(value, filter)
    return 0 if value.nil?
    return value if value.is_a?(Integer)
    return value.to_i if value.is_a?(String) && value.match?(/\A-?[0-9]{1,9}\z/)

    fail_with("not a number for '#{filter}'")
  end

  def sort_key(value)
    case value
    when nil then [0, 0]
    when Integer then [1, value]
    when String then [2, value]
    when true, false then [3, value ? 1 : 0]
    else [4, 0]
    end
  end

  def filter_value(value, filter, args)
    case filter
    when 'upper' then stringify(value).upcase
    when 'lower' then stringify(value).downcase
    when 'title'
      stringify(value).downcase.gsub(/\A.|(?<= )./) { |char| char.upcase }
    when 'trim' then strip_spaces(stringify(value))
    when 'length' then value.is_a?(Array) || value.is_a?(Hash) ? value.length : stringify(value).length
    when 'first' then value.is_a?(Array) ? value.first : value
    when 'last' then value.is_a?(Array) ? value.last : value
    when 'reverse' then value.is_a?(Array) || value.is_a?(String) ? value.reverse : value
    when 'items' then value.is_a?(Hash) ? value.keys.sort.map { |key| { 'key' => key, 'value' => value[key] } } : value
    when 'comma'
      n = number(value, filter)
      (n < 0 ? '-' : '') + n.abs.to_s.reverse.scan(/.{1,3}/).join(',').reverse
    when 'sum', 'min', 'max'
      if value.is_a?(Array)
        values = value.map { |item| number(item, filter) }
        filter == 'sum' ? values.sum : values.public_send(filter)
      else
        number(value, filter)
      end
    when 'default' then truthy?(value) ? value : args[0]
    when 'eq' then stringify(value) == stringify(args[0])
    when 'pad' then stringify(value).ljust(args[0], args.fetch(1, ' '))
    when 'lpad' then stringify(value).rjust(args[0], args.fetch(1, ' '))
    when 'truncate'
      text = stringify(value)
      text.length > args[0] ? text[0, args[0]] + '...' : text
    when 'replace' then stringify(value).gsub(args[0]) { args[1] }
    when 'join' then value.is_a?(Array) ? value.map { |item| stringify(item) }.join(args[0]) : stringify(value)
    when 'sort'
      return value unless value.is_a?(Array)
      value.each_with_index.sort_by do |item, index|
        key = args.empty? ? item : (item.is_a?(Hash) ? item[args[0]] : nil)
        sort_key(key) + [index]
      end.map(&:first)
    when 'pluck' then value.is_a?(Array) ? value.map { |item| item.is_a?(Hash) ? item[args[0]] : nil } : value
    when 'add' then number(value, filter) + args[0]
    when 'sub' then number(value, filter) - args[0]
    when 'mul' then number(value, filter) * args[0]
    when 'div' then number(value, filter).div(args[0])
    when 'mod' then number(value, filter) % args[0]
    when 'gt' then number(value, filter) > args[0]
    when 'lt' then number(value, filter) < args[0]
    end
  end

  def resolve(name, contexts, loops)
    return [true, contexts.last] if name == '.'
    if name.start_with?('@')
      return [false, nil] if loops.empty?
      index, count = loops.last
      return [true, { '@index' => index, '@number' => index + 1, '@first' => index == 0, '@last' => index == count - 1 }[name]]
    end
    parts = name.split('.').map { |part| part.match?(/\A[0-9]+\z/) ? part.to_i : part }
    context = contexts.reverse.find { |item| has_part?(item, parts[0]) }
    return [false, nil] if context.nil?
    parts.each do |part|
      return [false, nil] unless has_part?(context, part)
      context = context[part]
    end
    [true, context]
  end

  def evaluate(token, contexts, loops)
    name, filters = token[:expression]
    found, value = resolve(name, contexts, loops)
    if @strict && [:variable, :raw].include?(token[:kind]) && !found
      fail_with("missing '#{name}'")
    end
    filters.each { |filter, args| value = filter_value(value, filter, args) }
    value
  end

  def html(text)
    text.gsub(/[&<>"']/) { |char| { '&' => '&amp;', '<' => '&lt;', '>' => '&gt;', '"' => '&quot;', "'" => '&#39;' }[char] }
  end

  def render(nodes, contexts, loops, depth)
    output = +''
    nodes.each do |token|
      begin
        case token[:kind]
        when :text then output << token[:text]
        when :variable, :raw
          text = stringify(evaluate(token, contexts, loops))
          output << (token[:kind] == :variable ? html(text) : text)
        when :section
          value = evaluate(token, contexts, loops)
          if value.is_a?(Array)
            value.each_with_index do |item, index|
              output << render(token[:children], contexts + [item], loops + [[index, value.length]], depth)
            end
          elsif truthy?(value)
            output << render(token[:children], contexts + [value], loops, depth)
          end
        when :inverted
          output << render(token[:children], contexts, loops, depth) unless truthy?(evaluate(token, contexts, loops))
        when :partial
          name = token[:text]
          fail_with("unknown partial '#{name}'") unless @partials.key?(name)
          fail_with("partial depth exceeded at '#{name}'") if depth == 8
          body = @partials[name].map { |text, line| [text.empty? ? text : token[:indent] + text, line] }
          output << render(analyze(body), contexts, loops, depth + 1)
        end
      rescue TemplateError => error
        error.line ||= token[:line]
        raise
      end
    end
    output
  end

  def render_template(name, line)
    unless @templates.key?(name)
      puts "TEMPLATE #{name} ERROR line #{line}: unknown template '#{name}'"
      return
    end
    begin
      result = render(analyze(@templates[name]), [@root], [], 0)
      count = result.empty? ? 0 : result.count("\n") + (result.end_with?("\n") ? 0 : 1)
      puts "TEMPLATE #{name} OK lines=#{count} chars=#{result.length}"
      print result
      print "\n" unless result.empty? || result.end_with?("\n")
    rescue TemplateError => error
      puts "TEMPLATE #{name} ERROR line #{error.line}: #{error.message}"
    end
  end

  def dump_leaves(value, path, output)
    if value.is_a?(Hash) && !value.empty?
      value.keys.sort.each { |key| dump_leaves(value[key], path.empty? ? key : "#{path}.#{key}", output) }
    elsif value.is_a?(Array) && !value.empty?
      value.each_with_index { |item, index| dump_leaves(item, "#{path}[#{index}]", output) }
    elsif !path.empty?
      notation = case value
                 when String then '"' + value.gsub(/[\\"\n]/) { |char| { '\\' => '\\\\', '"' => '\\"', "\n" => '\\n' }[char] } + '"'
                 when Hash then '{}'
                 when Array then '[]'
                 else stringify(value)
                 end
      output << "#{path} = #{notation}"
    end
  end

  def run
    input = STDIN.each_line.map { |line| line.chomp("\n").delete_suffix("\r") }
    index = 0
    while index < input.length
      command = input[index]
      line = index + 1
      index += 1
      break if command == 'END'
      kind, name = command.split(' ', 2)
      if %w[DATA PARTIAL TEMPLATE].include?(kind)
        body = []
        ending = { 'DATA' => 'ENDDATA', 'PARTIAL' => 'ENDPARTIAL', 'TEMPLATE' => 'ENDTEMPLATE' }[kind]
        while input[index] != ending
          body << [input[index], index + 1]
          index += 1
        end
        index += 1
        if kind == 'DATA'
          data(body)
        elsif kind == 'PARTIAL'
          begin
            analyze(body)
            action = @partials.key?(name) ? 'REPLACED' : 'DEFINED'
            @partials[name] = body
            puts "PARTIAL #{name} #{action} lines=#{body.length}"
          rescue TemplateError => error
            puts "PARTIAL #{name} ERROR line #{error.line}: #{error.message}"
          end
        else
          @templates[name] = body
          render_template(name, line)
        end
      elsif kind == 'RENDER'
        render_template(name, line)
      elsif kind == 'DUMP'
        leaves = []
        dump_leaves(@root, '', leaves)
        puts "DUMP leaves=#{leaves.length}"
        puts leaves
      elsif kind == 'STRICT'
        @strict = name == 'ON'
        puts command
      elsif kind == 'RESET'
        @root = {}
        @partials = {}
        @templates = {}
        puts 'RESET'
      end
    end
  end
end

TemplateEngine.new.run
