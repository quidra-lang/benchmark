require 'base64'

WIRE_TYPES = {
  'uint32' => 0, 'uint64' => 0, 'sint32' => 0, 'sint64' => 0, 'bool' => 0,
  'fixed32' => 5, 'sfixed32' => 5, 'fixed64' => 1, 'string' => 2, 'bytes' => 2
}.freeze
INTEGER_RANGES = {
  'uint32' => 0..4_294_967_295, 'uint64' => 0..9_007_199_254_740_991,
  'sint32' => -2_147_483_648..2_147_483_647,
  'sint64' => -4_503_599_627_370_496..4_503_599_627_370_495,
  'fixed32' => 0..4_294_967_295, 'sfixed32' => -2_147_483_648..2_147_483_647,
  'fixed64' => 0..9_007_199_254_740_991
}.freeze
WIRE_NAMES = { 0 => 'varint', 1 => 'i64', 2 => 'len', 5 => 'i32' }.freeze
WORD_COUNTS = {
  'VARINT' => 2, 'ZIGZAG' => 2, 'SCHEMA' => 2, 'ENCODE' => 3, 'SIZE' => 3,
  'DECODE' => 3, 'LITERAL' => 3, 'JSON' => 3, 'CANON' => 3, 'EXPLAIN' => 3,
  'GET' => 4, 'PATCH' => 5, 'CLEAR' => 4, 'MERGE' => 4, 'DIFF' => 4
}.freeze
TEXT_POSITIONS = { 'ENCODE' => 2, 'SIZE' => 2, 'PATCH' => 4 }.freeze
HEX_ARGUMENTS = {
  'DECODE' => 1, 'LITERAL' => 1, 'JSON' => 1, 'CANON' => 1, 'EXPLAIN' => 1,
  'GET' => 1, 'PATCH' => 1, 'CLEAR' => 1, 'MERGE' => 2, 'DIFF' => 2
}.freeze
REQUIRED_SHAPES = {
  'integer' => 'integer', 'bool' => 'boolean', 'enum' => 'name',
  'string' => 'string', 'bytes' => 'bytes', 'message' => 'message'
}.freeze

class CommandError < StandardError; end

def byte_error(reason, offset)
  CommandError.new("#{reason} at byte #{offset}")
end

def column_error(reason, column)
  CommandError.new("#{reason} at column #{column}")
end

def zigzag(number)
  number >= 0 ? 2 * number : -2 * number - 1
end

def varint_bytes(number)
  bytes = []
  while number >= 128
    bytes << (number % 128 + 128)
    number /= 128
  end
  (bytes << number).pack('C*')
end

def hex_text(data)
  data.empty? ? '-' : data.unpack1('H*')
end

def parse_hex(text)
  return ''.b if text == '-'
  raise CommandError, 'invalid hex' unless /\A(?:[0-9a-f]{2})+\z/.match?(text)

  [text].pack('H*')
end

def quoted(data, escape_prefix)
  escapes = { 34 => '\\"', 92 => '\\\\', 10 => '\\n', 9 => '\\t' }
  parts = data.bytes.map do |byte|
    escapes[byte] || (byte.between?(32, 126) ? byte.chr : format('%s%02x', escape_prefix, byte))
  end
  '"' + parts.join + '"'
end

class EnumType
  attr_reader :name, :numbers, :names

  def initialize(name)
    @name = name
    @numbers = {}
    @names = {}
  end

  def add(name, number)
    @numbers[name] = number
    @names[number] = name
  end
end

class Field
  attr_reader :number, :type_name, :name, :required, :repeated, :packed, :group,
              :kind, :wire, :enum_type, :message_type

  def initialize(number, type_name, name, options)
    @number = number
    @type_name = type_name
    @name = name
    @required = options == ['REQUIRED']
    @repeated = options.first == 'REPEATED'
    @packed = options == %w[REPEATED PACKED]
    @group = options[1] if options.first == 'ONEOF'
  end

  def resolve(enums, messages)
    if WIRE_TYPES.key?(@type_name)
      @wire = WIRE_TYPES[@type_name]
      @kind = INTEGER_RANGES.key?(@type_name) ? 'integer' : @type_name
    elsif enums.key?(@type_name)
      @wire = 0
      @kind = 'enum'
      @enum_type = enums[@type_name]
    else
      @wire = 2
      @kind = 'message'
      @message_type = messages[@type_name]
    end
  end

  def kind_word
    return 'required ' if @required
    return 'repeated packed ' if @packed
    return 'repeated ' if @repeated
    return "oneof #{@group} " if @group

    ''
  end
end

class MessageType
  attr_reader :name, :fields, :by_name, :by_number

  def initialize(name)
    @name = name
    @fields = []
    @by_name = {}
    @by_number = {}
  end

  def add(field)
    @fields << field
    @by_name[field.name] = field
    @by_number[field.number] = field
  end
end

def read_schema(stream)
  enums = {}
  messages = {}
  current = nil
  while (line = stream.gets)
    words = line.chomp.split(' ')
    break if words == ['END', 'SCHEMA']

    case words[0]
    when 'ENUM'
      current = EnumType.new(words[1])
      enums[current.name] = current
    when 'MESSAGE'
      current = MessageType.new(words[1])
      messages[current.name] = current
    when 'VALUE'
      current.add(words[1], words[2].to_i)
    when 'FIELD'
      current.add(Field.new(words[1].to_i, words[2], words[3], words.drop(4)))
    end
  end
  messages.each_value do |type|
    type.fields.sort_by!(&:number)
    type.fields.each { |field| field.resolve(enums, messages) }
  end
  messages
end

UnknownField = Struct.new(:number, :wire, :raw) do
  def notation
    wire.zero? ? raw.to_s : "<#{raw.unpack1('H*')}>"
  end

  def encode
    tag = varint_bytes(number * 8 + wire)
    case wire
    when 0 then tag + varint_bytes(raw)
    when 2 then tag + varint_bytes(raw.bytesize) + raw
    else tag + raw
    end
  end
end

class Message
  attr_reader :type, :unknown

  def initialize(type)
    @type = type
    @values = {}
    @unknown = []
  end

  def has?(field)
    @values.key?(field.number)
  end

  def get(field)
    @values[field.number]
  end

  def items(field)
    return [] unless has?(field)

    field.repeated ? get(field) : [get(field)]
  end

  def set(field, value)
    @values[field.number] = value
  end

  def set_items(field, values)
    values.empty? ? remove(field) : set(field, values.dup)
  end

  def remove(field)
    @values.delete(field.number)
  end

  def remove_group(field)
    return unless field.group

    @type.fields.each do |other|
      remove(other) if other != field && other.group == field.group
    end
  end

  def present_fields
    @type.fields.select { |field| has?(field) }
  end
end

def apply_values(message, field, values)
  message.remove_group(field)
  if field.repeated
    message.set_items(field, message.items(field) + values)
  elsif field.kind == 'message' && message.has?(field)
    merge_message(message.get(field), values.first)
  else
    message.set(field, values.first)
  end
end

def merge_message(target, source)
  source.present_fields.each { |field| apply_values(target, field, source.items(field)) }
  target.unknown.concat(source.unknown)
end

def check_required(message, prefix = '')
  message.type.fields.each do |field|
    if field.required && !message.has?(field)
      raise CommandError, "missing required field #{prefix}#{field.name}"
    end
    next unless field.kind == 'message'

    message.items(field).each_with_index do |value, index|
      suffix = field.repeated ? "[#{index}]" : ''
      check_required(value, "#{prefix}#{field.name}#{suffix}.")
    end
  end
end

def element_bytes(field, value)
  case field.wire
  when 2
    payload = field.kind == 'message' ? encode_message(value) : value
    varint_bytes(payload.bytesize) + payload
  when 5
    [value % 4_294_967_296].pack('V')
  when 1
    [value].pack('Q<')
  else
    number = if field.kind == 'bool'
               value ? 1 : 0
             elsif %w[sint32 sint64].include?(field.type_name)
               zigzag(value)
             else
               value
             end
    varint_bytes(number)
  end
end

def field_records(field, values)
  if field.packed
    payload = values.map { |value| element_bytes(field, value) }.join.b
    varint_bytes(field.number * 8 + 2) + varint_bytes(payload.bytesize) + payload
  else
    tag = varint_bytes(field.number * 8 + field.wire)
    values.map { |value| tag + element_bytes(field, value) }.join.b
  end
end

def encode_message(message)
  records = message.present_fields.map { |field| field_records(field, message.items(field)) }
  records.concat(message.unknown.map(&:encode)).join.b
end

def scalar_value(field, number, position)
  if field.kind == 'bool'
    raise byte_error('value out of range', position) if number > 1

    return number == 1
  end
  if field.kind == 'enum'
    raise byte_error('unknown enum number', position) unless field.enum_type.names.key?(number)

    return number
  end
  value = if %w[sint32 sint64].include?(field.type_name)
            number.even? ? number / 2 : -(number + 1) / 2
          elsif field.type_name == 'sfixed32' && number >= 2_147_483_648
            number - 4_294_967_296
          else
            number
          end
  raise byte_error('value out of range', position) unless INTEGER_RANGES[field.type_name].cover?(value)

  value
end

class Reader
  attr_reader :lines

  def initialize(data, explaining = false)
    @data = data
    @explaining = explaining
    @lines = []
  end

  def note(line)
    @lines << line if @explaining
  end

  def varint(start, finish)
    value = 0
    8.times do |index|
      position = start + index
      raise byte_error('truncated varint', start) if position >= finish

      byte = @data.getbyte(position)
      value |= (byte & 127) << (7 * index)
      if byte < 128
        raise byte_error('varint too large', start) if value >= 9_007_199_254_740_992

        return [value, position + 1]
      end
      raise byte_error('varint too long', start) if index == 7
    end
  end

  def fixed(start, finish, wire)
    size = wire == 1 ? 8 : 4
    raise byte_error("truncated #{WIRE_NAMES[wire]}", start) if finish - start < size

    [@data.byteslice(start, size), start + size]
  end

  def read_message(type, start, finish, depth = 0)
    message = Message.new(type)
    position = start
    position = read_record(message, position, finish, depth) while position < finish
    message
  end

  def read_record(message, start, finish, depth)
    tag, position = varint(start, finish)
    number, wire = tag.divmod(8)
    raise byte_error('invalid field number', start) if number.zero?
    raise byte_error('invalid wire type', start) unless WIRE_NAMES.key?(wire)

    field = message.type.by_number[number]
    packed = field && field.repeated && field.wire != 2 && wire == 2
    if field && wire != field.wire && !packed
      raise byte_error('wire type mismatch', start)
    end
    value_start = position
    case wire
    when 0
      raw, position = varint(position, finish)
    when 2
      length, value_start = varint(position, finish)
      raise byte_error('length past end', position) if value_start + length > finish

      raw = @data.byteslice(value_start, length)
      position = value_start + length
    else
      raw, position = fixed(position, finish, wire)
    end
    header = "#{'  ' * depth}#{start} #{number} #{field ? field.name : '?'} #{WIRE_NAMES[wire]}"
    header += " #{raw.bytesize}" if wire == 2
    unless field
      unknown = UnknownField.new(number, wire, raw)
      message.unknown << unknown
      note("#{header} #{unknown.notation}")
      return position
    end
    if field.kind == 'message'
      note(header)
      values = [read_message(field.message_type, value_start, position, depth + 1)]
    elsif packed
      values = packed_values(field, value_start, position)
      note(header + ' packed' + values.map { |value| " #{value_notation(field, value)}" }.join)
    else
      values = [convert(field, raw, value_start)]
      note("#{header} #{value_notation(field, values.first)}")
    end
    apply_values(message, field, values) unless @explaining
    position
  end

  def packed_values(field, start, finish)
    values = []
    position = start
    while position < finish
      element_start = position
      if field.wire.zero?
        number, position = varint(position, finish)
      else
        raw, position = fixed(position, finish, field.wire)
        number = raw.unpack1(field.wire == 1 ? 'Q<' : 'V')
      end
      values << scalar_value(field, number, element_start)
    end
    values
  end

  def convert(field, raw, position)
    if field.kind == 'string'
      raw.each_byte.with_index do |byte, index|
        raise byte_error('invalid string', position + index) if byte >= 128
      end
      return raw
    end
    return raw if field.kind == 'bytes'

    number = field.wire.zero? ? raw : raw.unpack1(field.wire == 1 ? 'Q<' : 'V')
    scalar_value(field, number, position)
  end
end

def decode_message(type, data)
  message = Reader.new(data).read_message(type, 0, data.bytesize)
  check_required(message)
  message
end

def value_notation(field, value)
  case field.kind
  when 'message' then message_notation(value)
  when 'enum' then field.enum_type.names[value]
  when 'bool' then value ? 'true' : 'false'
  when 'string' then quoted(value, '\\x')
  when 'bytes' then "<#{value.unpack1('H*')}>"
  else value.to_s
  end
end

def list_notation(field, values)
  '[' + values.map { |value| value_notation(field, value) }.join(', ') + ']'
end

def message_notation(message)
  items = message.present_fields.map do |field|
    text = field.repeated ? list_notation(field, message.items(field)) : value_notation(field, message.get(field))
    "#{field.name}: #{text}"
  end
  '{' + items.join(', ') + '}'
end

def json_value(field, value)
  case field.kind
  when 'message' then json_message(value)
  when 'enum' then '"' + field.enum_type.names[value] + '"'
  when 'bool' then value ? 'true' : 'false'
  when 'string' then quoted(value, '\\u00')
  when 'bytes' then '"' + Base64.strict_encode64(value) + '"'
  else
    %w[uint64 sint64 fixed64].include?(field.type_name) ? "\"#{value}\"" : value.to_s
  end
end

def json_message(message)
  items = message.present_fields.map do |field|
    values = message.items(field).map { |value| json_value(field, value) }
    text = field.repeated ? '[' + values.join(',') + ']' : values.first
    key = field.name.gsub(/_([a-z0-9])/) { Regexp.last_match(1).upcase }
    "\"#{key}\":#{text}"
  end
  '{' + items.join(',') + '}'
end

Token = Struct.new(:kind, :column, :text, :value) do
  def shape
    return { '{' => 'message', '[' => 'list' }[text] if kind == 'symbol'
    return %w[true false].include?(text) ? 'boolean' : 'name' if kind == 'name'

    kind == 'end' ? nil : kind
  end
end

def tokenize(text)
  tokens = []
  position = 0
  while position < text.length
    char = text[position]
    start = position
    if char == ' '
      position += 1
      next
    elsif '{}[]:,'.include?(char)
      tokens << Token.new('symbol', start + 1, char)
      position += 1
    elsif char == '"'
      position += 1
      value = ''.b
      while position < text.length && text[position] != '"'
        if text[position] != '\\'
          value << text.getbyte(position)
          position += 1
          next
        end
        escape = text[position + 1]
        replacements = { '"' => 34, '\\' => 92, 'n' => 10, 't' => 9 }
        if replacements.key?(escape)
          value << replacements[escape]
          position += 2
        elsif escape == 'x' && /\A[0-7][0-9a-f]\z/.match?(text[position + 2, 2].to_s)
          value << text[position + 2, 2].to_i(16)
          position += 4
        else
          raise column_error('syntax error', start + 1)
        end
      end
      raise column_error('syntax error', start + 1) if position >= text.length

      tokens << Token.new('string', start + 1, nil, value)
      position += 1
    elsif char == '<'
      close = text.index('>', position + 1)
      raise column_error('syntax error', start + 1) unless close

      digits = text[position + 1...close]
      raise column_error('syntax error', start + 1) unless /\A(?:[0-9a-f]{2})*\z/.match?(digits)

      tokens << Token.new('bytes', start + 1, nil, [digits].pack('H*'))
      position = close + 1
    elsif char == '-' || /[0-9]/.match?(char)
      match = /\A-?[0-9]+/.match(text[position..])
      raise column_error('syntax error', start + 1) unless match

      tokens << Token.new('integer', start + 1, nil, match[0].to_i)
      position += match[0].length
    elsif /[A-Za-z_]/.match?(char)
      name = /\A[A-Za-z_][A-Za-z0-9_]*/.match(text[position..])[0]
      tokens << Token.new('name', start + 1, name)
      position += name.length
    else
      raise column_error('syntax error', start + 1)
    end
  end
  tokens << Token.new('end', text.length + 1)
end

class LiteralParser
  def initialize(text)
    @tokens = tokenize(text)
    @index = 0
  end

  def peek
    @tokens[@index]
  end

  def take
    token = peek
    @index += 1
    token
  end

  def at_symbol?(symbol)
    peek.kind == 'symbol' && peek.text == symbol
  end

  def fail_at(reason)
    raise column_error(reason, peek.column)
  end

  def expect(symbol)
    fail_at('syntax error') unless at_symbol?(symbol)
    take
  end

  def finish
    fail_at('syntax error') unless peek.kind == 'end'
  end

  def message(type)
    expect('{')
    result = Message.new(type)
    seen = []
    unless at_symbol?('}')
      read_field(result, seen)
      while at_symbol?(',')
        take
        read_field(result, seen)
      end
    end
    closing = expect('}')
    type.fields.each do |field|
      if field.required && !seen.include?(field)
        raise column_error("missing required field #{field.name}", closing.column)
      end
    end
    result
  end

  def read_field(message, seen)
    fail_at('syntax error') unless peek.kind == 'name'
    field = message.type.by_name[peek.text]
    fail_at('unknown field') unless field
    fail_at('duplicate field') if seen.include?(field)
    fail_at('oneof conflict') if field.group && seen.any? { |other| other.group == field.group }
    take
    seen << field
    expect(':')
    if field.repeated
      message.set_items(field, list_value(field))
    else
      message.set(field, element(field))
    end
  end

  def list_value(field)
    fail_at('syntax error') unless peek.shape
    fail_at('type mismatch') unless peek.shape == 'list'
    take
    values = []
    unless at_symbol?(']')
      values << element(field)
      while at_symbol?(',')
        take
        values << element(field)
      end
    end
    expect(']')
    values
  end

  def element(field)
    token = peek
    shape = token.shape
    fail_at('syntax error') unless shape
    fail_at('type mismatch') unless shape == REQUIRED_SHAPES[field.kind]
    return message(field.message_type) if shape == 'message'

    take
    case shape
    when 'integer'
      unless INTEGER_RANGES[field.type_name].cover?(token.value)
        raise column_error('out of range', token.column)
      end
      token.value
    when 'boolean'
      token.text == 'true'
    when 'name'
      unless field.enum_type.numbers.key?(token.text)
        raise column_error('unknown enum value', token.column)
      end
      field.enum_type.numbers[token.text]
    else token.value
    end
  end
end

PathSegment = Struct.new(:field, :index) do
  def position
    index || 0
  end

  def whole?
    field.repeated && index.nil?
  end
end

def parse_path(type, text)
  segments = []
  parts = text.split('.', -1)
  parts.each_with_index do |part, position|
    match = /\A([a-z][a-z0-9_]*)(?:\[([0-9]{1,6})\])?\z/.match(part)
    raise CommandError, 'invalid path' unless match

    field = type.by_name[match[1]]
    index = match[2]&.to_i
    raise CommandError, 'invalid path' unless field && (index.nil? || field.repeated)

    segments << PathSegment.new(field, index)
    next if position == parts.length - 1
    unless field.kind == 'message' && (!field.repeated || !index.nil?)
      raise CommandError, 'invalid path'
    end
    type = field.message_type
  end
  segments
end

def follow(message, segments)
  segments.each do |segment|
    values = message.items(segment.field)
    return nil if segment.position >= values.length

    message = values[segment.position]
  end
  message
end

class Codec
  def initialize(messages)
    @messages = messages
  end

  def execute(line)
    words = line.split(/ /, -1)
    command = words.first
    expected = WORD_COUNTS[command]
    raise CommandError, 'unknown command' unless expected
    if words.length < expected || (words.length > expected && !TEXT_POSITIONS.key?(command))
      raise CommandError, 'wrong number of arguments'
    end
    if %w[VARINT ZIGZAG].include?(command)
      range = command == 'VARINT' ? INTEGER_RANGES['uint64'] : INTEGER_RANGES['sint64']
      unless /\A-?[0-9]{1,18}\z/.match?(words[1]) && range.cover?(words[1].to_i)
        raise CommandError, 'invalid number'
      end
      number = words[1].to_i
      return [hex_text(varint_bytes(number))] if command == 'VARINT'

      value = zigzag(number)
      return ["#{value} #{hex_text(varint_bytes(value))}"]
    end
    type = @messages[words[1]]
    raise CommandError, 'unknown message type' unless type

    data = words[2, HEX_ARGUMENTS.fetch(command, 0)].map { |word| parse_hex(word) }
    path = parse_path(type, words[3]) if %w[GET PATCH CLEAR].include?(command)
    text = line.split(/ /, TEXT_POSITIONS[command] + 1).last if TEXT_POSITIONS.key?(command)
    process(command, type, data, path, text)
  rescue CommandError => error
    ["ERROR #{error.message}"]
  end

  def process(command, type, data, path, text)
    case command
    when 'SCHEMA'
      [type.name] + schema_fields(type, [type], 1)
    when 'ENCODE', 'SIZE'
      parser = LiteralParser.new(text)
      message = parser.message(type)
      parser.finish
      return [hex_text(encode_message(message))] if command == 'ENCODE'

      sizes = message.present_fields.map do |field|
        "#{field.name}=#{field_records(field, message.items(field)).bytesize}"
      end
      [([encode_message(message).bytesize] + sizes).join(' ')]
    when 'EXPLAIN'
      return ['(empty)'] if data.first.empty?

      reader = Reader.new(data.first, true)
      reader.read_message(type, 0, data.first.bytesize)
      reader.lines
    when 'DIFF'
      messages = data.each_with_index.map do |bytes, index|
        begin
          decode_message(type, bytes)
        rescue CommandError => error
          raise CommandError, "#{error.message} in #{index.zero? ? 'first' : 'second'}"
        end
      end
      lines = compare(messages[0], messages[1])
      lines.empty? ? ['SAME'] : lines
    when 'MERGE'
      text_message(decode_message(type, data.join.b))
    else
      message = decode_message(type, data.first)
      case command
      when 'DECODE' then text_message(message)
      when 'LITERAL' then [message_notation(message)]
      when 'JSON' then [json_message(message)]
      when 'CANON' then [hex_text(encode_message(message))]
      when 'GET' then [get_value(message, path)]
      when 'PATCH'
        patch(message, path, text)
        check_required(message)
        [hex_text(encode_message(message))]
      when 'CLEAR'
        clear(message, path)
        check_required(message)
        [hex_text(encode_message(message))]
      end
    end
  end

  def schema_fields(type, chain, depth)
    type.fields.flat_map do |field|
      line = "#{'  ' * depth}#{field.number} #{field.name}: #{field.kind_word}#{field.type_name}"
      if field.enum_type
        entries = field.enum_type.names.sort.map { |number, name| "#{name}=#{number}" }
        line += ' (' + entries.join(', ') + ')'
      end
      nested = field.message_type
      if nested && chain.include?(nested)
        [line + ' (recursive)']
      elsif nested
        [line] + schema_fields(nested, chain + [nested], depth + 1)
      else
        [line]
      end
    end
  end

  def text_message(message)
    [message.type.name + ' {'] + text_contents(message, 1) + ['}']
  end

  def text_contents(message, depth)
    indent = '  ' * depth
    lines = message.present_fields.flat_map do |field|
      message.items(field).flat_map do |value|
        if field.kind == 'message'
          ["#{indent}#{field.name} {"] + text_contents(value, depth + 1) + [indent + '}']
        else
          ["#{indent}#{field.name}: #{value_notation(field, value)}"]
        end
      end
    end
    unknown_lines = message.unknown.map do |unknown|
      "#{indent}#{unknown.number}: #{WIRE_NAMES[unknown.wire]} #{unknown.notation}"
    end
    lines + unknown_lines
  end

  def get_value(message, path)
    last = path.last
    target = follow(message, path[0...-1])
    values = target ? target.items(last.field) : []
    return list_notation(last.field, values) if last.whole?
    return '(none)' if last.position >= values.length

    value_notation(last.field, values[last.position])
  end

  def patch(message, path, text)
    last = path.last
    field = last.field
    parser = LiteralParser.new(text)
    value = last.whole? ? parser.list_value(field) : parser.element(field)
    parser.finish
    target = message
    path[0...-1].each do |segment|
      intermediate = segment.field
      if intermediate.repeated
        values = target.items(intermediate)
        raise CommandError, 'index out of range' if segment.index >= values.length

        target = values[segment.index]
      else
        unless target.has?(intermediate)
          target.remove_group(intermediate)
          target.set(intermediate, Message.new(intermediate.message_type))
        end
        target = target.get(intermediate)
      end
    end
    if last.whole?
      target.set_items(field, value)
    elsif field.repeated
      values = target.items(field).dup
      raise CommandError, 'index out of range' if last.index >= values.length

      values[last.index] = value
      target.set_items(field, values)
    else
      target.remove_group(field)
      target.set(field, value)
    end
  end

  def clear(message, path)
    last = path.last
    target = follow(message, path[0...-1])
    return unless target

    if last.index.nil?
      target.remove(last.field)
    else
      values = target.items(last.field).dup
      values.delete_at(last.index)
      target.set_items(last.field, values)
    end
  end

  def compare(first, second, prefix = '')
    lines = []
    first.type.fields.each do |field|
      left = first.items(field)
      right = second.items(field)
      [left.length, right.length].max.times do |index|
        path = prefix + field.name + (field.repeated ? "[#{index}]" : '')
        both = index < left.length && index < right.length
        if both && field.kind == 'message'
          lines.concat(compare(left[index], right[index], path + '.'))
        elsif !both || left[index] != right[index]
          old = index < left.length ? value_notation(field, left[index]) : '(none)'
          new = index < right.length ? value_notation(field, right[index]) : '(none)'
          lines << "#{path}: #{old} -> #{new}"
        end
      end
    end
    lines
  end
end

messages = read_schema($stdin)
codec = Codec.new(messages)
$stdin.gets.to_i.times { puts codec.execute($stdin.gets.chomp) }
