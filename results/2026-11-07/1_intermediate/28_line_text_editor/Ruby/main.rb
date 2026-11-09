
class CommandError < StandardError; end

Atom = Data.define(:character, :matched)
Token = Data.define(:kind, :value)
Delimited = Data.define(:text, :atoms, :position)
Lexed = Data.define(:tokens, :position)
Addresses = Data.define(:count, :left, :right, :semicolon)
Line = Data.define(:id, :text)
Snapshot = Data.define(:buffer, :current)
HistoryRecord = Data.define(:command, :state)
LineRange = Data.define(:first, :last)

Command = Struct.new(:kind, :number, :suffix, :option, :name, :search, :destination,
                     :replacement, :all, :options, :sub, keyword_init: true) do
  def initialize(**values)
    super(**{ kind: :empty, number: 0, search: '', destination: [].freeze, all: false, options: '' }.merge(values))
  end

  def address_kind
    case kind
    when :undo, :redo, :history, :marks, :files, :edit then 0
    when :append, :insert, :put, :equals, :read, :mark, :page then 1
    else 2
    end
  end

  def modifying?
    case kind
    when :append, :insert, :change, :delete, :put, :join, :join_space, :move, :copy,
         :substitute, :indent, :unindent, :case, :sort, :read, :edit then true
    when :global, :inverse then sub.modifying?
    else false
    end
  end
end

module Parsing
  SIMPLE = { 'a' => :append, 'i' => :insert, 'c' => :change, 'p' => :print, 'n' => :number,
             'l' => :list, '=' => :equals, '#' => :count, 'y' => :yank, 'K' => :marks,
             'h' => :history, 'f' => :files }.freeze
  BASES = %i[number current last mark forward backward].freeze

  module_function

  def digit?(c) = c && c >= '0' && c <= '9'
  def lower?(c) = c && c >= 'a' && c <= 'z'
  def digits?(s) = s.match?(/\A[0-9]+\z/)

  def delimited(s, position, delimiter)
    text = String.new
    atoms = []
    while position < s.length
      character = s[position]
      position += 1
      return Delimited.new(text.freeze, atoms.freeze, position) if character == delimiter

      escaped = character == '\\'
      if escaped
        raise CommandError, 'missing delimiter' if position == s.length
        character = s[position]
        position += 1
      end
      text << character
      atoms << Atom.new(character.freeze, character == '&' && !escaped)
    end
    raise CommandError, 'missing delimiter'
  end

  def lex_addresses(s)
    tokens = []
    position = 0
    while position < s.length
      c = s[position]
      if digit?(c)
        start = position
        position += 1 while digit?(s[position])
        token = Token.new(:number, s[start...position].to_i(10))
      elsif c == '+' || c == '-'
        position += 1
        start = position
        position += 1 while digit?(s[position])
        value = start == position ? 1 : s[start...position].to_i(10)
        token = Token.new(:offset, c == '-' ? -value : value)
      elsif '.$,;%'.include?(c)
        kind = { '.' => :current, '$' => :last, ',' => :comma, ';' => :semicolon, '%' => :percent }.fetch(c)
        token = Token.new(kind, nil)
        position += 1
      elsif c == "'"
        position += 1
        name = s[position]
        position += 1 if name
        token = Token.new(:mark, name)
      elsif c == '/' || c == '?'
        search = delimited(s, position + 1, c)
        position = search.position
        token = Token.new(c == '/' ? :forward : :backward, search.text)
      else
        break
      end
      tokens << token
    end
    Lexed.new(tokens.freeze, position)
  end

  def with_text?(line)
    part = line[lex_addresses(line).position..]
    return true if %w[a i c].include?(part)
    if part.length >= 2 && 'gv'.include?(part[0]) && !" \\".include?(part[1])
      rest = part[delimited(part, 2, part[1]).position..]
      return %w[a i c].include?(rest)
    end
    false
  rescue CommandError
    false
  end

  def valid_address?(tokens)
    tokens.each_with_index.all? { |token, i| token.kind == :offset || i.zero? && BASES.include?(token.kind) }
  end

  def addresses(tokens)
    return Addresses.new(0, [], [], false) if tokens.empty?
    if tokens.length == 1 && tokens[0].kind == :percent
      return Addresses.new(2, [Token.new(:number, 1)], [Token.new(:last, nil)], false)
    end
    separators = tokens.each_index.select { |i| %i[comma semicolon].include?(tokens[i].kind) }
    raise CommandError, 'bad address' if separators.length > 1
    separator = separators.first
    left = separator ? tokens[0...separator] : tokens
    right = separator ? tokens[separator + 1..] : []
    raise CommandError, 'bad address' unless valid_address?(left) && valid_address?(right)
    Addresses.new(separator ? 2 : 1, left, right, separator && tokens[separator].kind == :semicolon)
  end

  def print_suffix(s)
    return nil if s.empty?
    raise CommandError, 'invalid suffix' unless s.length == 1 && 'pnl'.include?(s)
    s
  end

  def positive(s)
    return 0 if s.empty?
    raise CommandError, 'invalid suffix' unless digits?(s) && s.to_i(10).positive?
    s.to_i(10)
  end

  def filename(s)
    raise CommandError, 'invalid file name' unless s.match?(/\A [a-z0-9]{1,8}\z/)
    s[1..].freeze
  end

  def sort_form?(s) = s == 'sort' || s.start_with?('sort ')

  def command(part)
    c = Command.new
    if sort_form?(part)
      c.kind = :sort
      c.options = part == 'sort' ? '' : part[5..]
      if part != 'sort'
        valid = c.options.match?(/\A[ruin]+\z/) && c.options.chars.uniq.length == c.options.length
        valid &&= !(c.options.include?('i') && c.options.include?('n'))
        raise CommandError, 'invalid suffix' unless valid
      end
      return c.freeze
    end
    return c.freeze if part.empty?
    first, arg = part[0], part[1..]
    if SIMPLE.key?(first)
      c.kind = SIMPLE.fetch(first)
      raise CommandError, 'invalid suffix' unless arg.empty?
      return c.freeze
    end
    case first
    when 'd', 'x', 'j', 'J'
      c.kind = { 'd' => :delete, 'x' => :put, 'j' => :join, 'J' => :join_space }.fetch(first)
      c.suffix = print_suffix(arg)
    when 'z', '>', '<', 'u'
      c.kind = { 'z' => :page, '>' => :indent, '<' => :unindent, 'u' => :undo }.fetch(first)
      c.number = positive(arg)
    when '~'
      c.kind = :case
      raise CommandError, 'invalid suffix' unless arg.empty? || %w[u l].include?(arg)
      c.option = arg.empty? ? nil : arg
    when 'r'
      if arg.empty? || digits?(arg)
        c.kind, c.number = :redo, positive(arg)
      else
        c.kind, c.name = :read, filename(arg)
      end
    when 'w', 'W', 'e'
      if first == 'w' && arg.empty?
        c.kind = :write_print
      else
        c.kind = { 'w' => :write, 'W' => :write_append, 'e' => :edit }.fetch(first)
        c.name = filename(arg)
      end
    when 'k'
      c.kind = :mark
      raise CommandError, 'invalid mark' unless arg.length == 1 && lower?(arg)
      c.option = arg
    when 'm', 't'
      c.kind = first == 'm' ? :move : :copy
      destination = lex_addresses(arg)
      raise CommandError, 'invalid destination' if destination.tokens.empty? || !valid_address?(destination.tokens)
      c.destination, c.suffix = destination.tokens, print_suffix(arg[destination.position..])
    when 's'
      c.kind, c.number = :substitute, 1
      position = 0
      unless arg.match?(/\A[gpnl0-9]*\z/)
        delimiter = arg[0]
        raise CommandError, 'missing delimiter' if " \\".include?(delimiter)
        search = delimited(arg, 1, delimiter)
        replacement = delimited(arg, search.position, delimiter)
        c.search = search.text
        c.replacement = replacement.atoms unless arg[search.position...replacement.position - 1] == '%'
        position = replacement.position
      end
      counted = false
      while position < arg.length
        flag = arg[position]
        position += 1
        if flag == 'g'
          raise CommandError, 'invalid suffix' if c.all
          c.all = true
        elsif 'pnl'.include?(flag)
          raise CommandError, 'invalid suffix' if c.suffix
          c.suffix = flag
        elsif digit?(flag)
          raise CommandError, 'invalid suffix' if counted
          counted = true
          start = position - 1
          position += 1 while digit?(arg[position])
          c.number = arg[start...position].to_i(10)
          raise CommandError, 'invalid suffix' if c.number.zero?
        else
          raise CommandError, 'invalid suffix'
        end
      end
    when 'g', 'v'
      c.kind = first == 'g' ? :global : :inverse
      raise CommandError, 'missing delimiter' if arg.empty? || " \\".include?(arg[0])
      search = delimited(arg, 1, arg[0])
      c.search = search.text
      body = arg[search.position..]
      body = 'p' if body.empty?
      raise CommandError, 'invalid global command' unless 'pnldmtjJs><~aicx'.include?(body[0]) && !sort_form?(body)
      c.sub = command(body)
    else
      raise CommandError, 'unknown command'
    end
    c.freeze
  end
end

class EditorState
  attr_accessor :buffer, :current
  attr_reader :undo, :redo

  def initialize
    @buffer, @marks, @cut = [], Array.new(26), [].freeze
    @current, @display, @next_id = 0, 5, 1
    @pattern = @replacement = nil
    @undo, @redo, @files = [], [], {}
  end

  def initialize_copy(other)
    super
    @buffer = @buffer.dup
    @marks = @marks.dup
    @undo = @undo.dup
    @redo = @redo.dup
    @files = @files.dup
  end

  def snapshot = Snapshot.new(@buffer.dup.freeze, @current)

  def locate(id)
    index = id && @buffer.index { |line| line.id == id }
    index && index + 1
  end

  def resolve_pattern(search)
    @pattern = search unless search.empty?
    raise CommandError, 'no previous pattern' unless @pattern
    @pattern
  end

  def address(tokens)
    value = @current
    tokens.each do |token|
      case token.kind
      when :offset then value += token.value
      when :number then value = token.value
      when :current then value = @current
      when :last then value = @buffer.length
      when :mark
        raise CommandError, 'invalid mark' unless Parsing.lower?(token.value)
        value = locate(@marks[token.value.ord - 'a'.ord])
        raise CommandError, 'mark not set' unless value
      when :forward, :backward
        pattern = resolve_pattern(token.value)
        size = @buffer.length
        start = token.kind == :backward && @current.zero? ? size + 1 : @current
        value = nil
        1.upto(size) do |step|
          index = token.kind == :forward ? (start + step - 1) % size : (start - step - 1) % size
          if @buffer[index].text.include?(pattern)
            value = index + 1
            break
          end
        end
        raise CommandError, 'no match' unless value
      end
    end
    value
  end

  def evaluate(addresses)
    return LineRange.new(0, 0) if addresses.count.zero?
    a = addresses.left.empty? ? (addresses.semicolon ? @current : 1) : address(addresses.left)
    b = 0
    if addresses.count == 2
      if addresses.semicolon
        raise CommandError, 'address out of range' unless a.between?(0, @buffer.length)
        @current = a
      end
      b = addresses.right.empty? ? @buffer.length : address(addresses.right)
    end
    LineRange.new(a, b)
  end

  def checked_range(c, count, values)
    a, b, size = values.first, values.last, @buffer.length
    return LineRange.new(0, 0) if c.address_kind.zero?
    if c.address_kind == 1
      if count.zero?
        a = case c.kind
            when :equals, :read then size
            when :page then @current + 1
            else @current
            end
      end
      minimum = %i[mark page].include?(c.kind) ? 1 : 0
      raise CommandError, 'address out of range' unless a.between?(minimum, size)
      return LineRange.new(a, a)
    end
    if count.zero?
      case c.kind
      when :write, :write_append, :write_print, :count then return LineRange.new(1, size)
      when :global, :inverse, :sort then a, b = 1, size
      when :join, :join_space then a, b = @current, @current + 1
      else a = b = @current
      end
    elsif count == 1
      b = a
    end
    raise CommandError, 'address out of range' unless a.between?(1, size) && b.between?(1, size)
    raise CommandError, 'invalid range' if a > b || a == b && %i[join join_space].include?(c.kind)
    LineRange.new(a, b)
  end

  def print_line(number, form, output)
    text = @buffer[number - 1].text
    case form
    when 'n'
      output << format('%3d %s', number, text)
    when 'l'
      escaped = text.gsub('\\') { '\\\\' } + '$'
      position = 0
      while escaped.length - position > 40
        output << escaped[position, 39] + '\\'
        position += 39
      end
      output << escaped[position..]
    else
      output << text
    end
  end

  def contents(range) = @buffer[range.first - 1...range.last].map(&:text).freeze

  def insert(after, text)
    lines = text.map do |value|
      line = Line.new(@next_id, value.freeze)
      @next_id += 1
      line
    end
    @buffer.insert(after, *lines)
  end

  def set_text(index, text)
    @buffer[index] = Line.new(@buffer[index].id, text.freeze)
  end

  def substitute(c, range, output, in_global)
    pattern = resolve_pattern(c.search)
    used = c.replacement || @replacement
    raise CommandError, 'no previous substitution' unless used
    @replacement = used
    expanded = used.map { |atom| atom.matched ? pattern : atom.character }.join
    last = nil
    range.first.upto(range.last) do |i|
      old = @buffer[i - 1].text
      result = String.new
      position = occurrence = 0
      changed = false
      while (start = old.index(pattern, position))
        result << old[position...start]
        occurrence += 1
        if occurrence == c.number || c.all && occurrence > c.number
          result << expanded
          changed = true
        else
          result << pattern
        end
        position = start + pattern.length
      end
      result << old[position..]
      next unless changed
      raise CommandError, 'line too long' if result.length > 80
      raise CommandError, 'bad line' if result.empty? || result.end_with?(' ')
      set_text(i - 1, result)
      last = i
    end
    raise CommandError, 'no match' unless last || in_global
    if last
      @current = last
      print_line(last, c.suffix, output) if c.suffix
    end
    !last.nil?
  end

  def leading_integer(text)
    prefix = text[/\A-?[0-9]+/]
    prefix ? prefix.to_i(10) : 0
  end

  def sort_lines(c, range)
    decorated = @buffer[range.first - 1...range.last].each_with_index.map do |line, index|
      key = if c.options.include?('n')
              leading_integer(line.text)
            elsif c.options.include?('i')
              line.text.downcase
            else
              line.text
            end
      [key, index, line]
    end
    decorated.sort! do |left, right|
      order = left[0] <=> right[0]
      order = -order if c.options.include?('r')
      order.zero? ? left[1] <=> right[1] : order
    end
    decorated = decorated.uniq { |entry| entry[0] } if c.options.include?('u')
    kept = decorated.map(&:last)
    @buffer[range.first - 1, range.last - range.first + 1] = kept
    @current = range.first + kept.length - 1
  end

  def file_bytes(file) = file.sum { |line| line.length + 1 }

  def file_command(c, range, output)
    file = @files[c.name]
    if %i[write write_append].include?(c.kind)
      saved = c.kind == :write_append && file ? file : []
      file = (saved + contents(range)).freeze
      @files[c.name] = file
    else
      raise CommandError, 'no such file' unless file
      after = range.first
      if c.kind == :edit
        @buffer.clear
        after = 0
      end
      insert(after, file)
      @current = after + file.length
    end
    output << "file #{c.name} lines=#{file.length} bytes=#{file_bytes(file)}"
  end

  def transfer_history(is_redo, count)
    from, to = is_redo ? [@redo, @undo] : [@undo, @redo]
    raise CommandError, (is_redo ? 'nothing to redo' : 'nothing to undo') if from.length < count
    count.times do
      record = from.pop
      to << HistoryRecord.new(record.command, snapshot)
      @buffer, @current = record.state.buffer.dup, record.state.current
    end
  end

  def execute(c, range, text, output, in_global: false)
    a, b = range.first, range.last
    case c.kind
    when :empty
      print_line(b, 'p', output)
      @current = b
    when :print, :number, :list
      form = { print: 'p', number: 'n', list: 'l' }.fetch(c.kind)
      a.upto(b) { |i| print_line(i, form, output) }
      @current = b
    when :page
      @display = c.number unless c.number.zero?
      last = [a + @display - 1, @buffer.length].min
      a.upto(last) { |i| print_line(i, 'p', output) }
      @current = last
    when :equals
      output << a.to_s
    when :count, :write_print
      lines = @buffer[a - 1...b]
      chars = lines.sum { |line| line.text.length }
      if c.kind == :count
        words = lines.sum { |line| line.text.scan(/[^ ]+/).length }
        output << "count lines=#{lines.length} words=#{words} chars=#{chars}"
      else
        a.upto(b) { |i| print_line(i, 'p', output) }
        output << "lines=#{lines.length} bytes=#{chars + lines.length}"
      end
    when :append, :insert
      after = c.kind == :append ? a : [a, 1].max - 1
      insert(after, text)
      @current = after + text.length
    when :change, :delete
      @cut = contents(range)
      @buffer.slice!(a - 1, b - a + 1)
      insert(a - 1, text) if c.kind == :change
      @current = c.kind == :change && !text.empty? ? a + text.length - 1 : [a, @buffer.length].min
    when :yank
      @cut = contents(range)
    when :put
      raise CommandError, 'nothing to put' if @cut.empty?
      insert(a, @cut)
      @current = a + @cut.length
    when :move, :copy
      destination = address(c.destination)
      raise CommandError, 'address out of range' unless destination.between?(0, @buffer.length)
      raise CommandError, 'invalid destination' if c.kind == :move && a <= destination && destination < b
      moved = @buffer[a - 1...b]
      if c.kind == :move
        @buffer.slice!(a - 1, b - a + 1)
        destination -= moved.length if destination >= b
      else
        moved = moved.map do |line|
          copy = Line.new(@next_id, line.text)
          @next_id += 1
          copy
        end
      end
      @buffer.insert(destination, *moved)
      @current = destination + moved.length
    when :join, :join_space
      pieces = @buffer[a - 1...b].map(&:text)
      if c.kind == :join_space
        pieces = [pieces[0]] + pieces.drop(1).map { |line| line.sub(/\A +/, '') }
      end
      joined = pieces.join(c.kind == :join_space ? ' ' : '')
      raise CommandError, 'line too long' if joined.length > 80
      set_text(a - 1, joined)
      @buffer.slice!(a, b - a)
      @current = a
    when :indent, :unindent, :case
      width = c.number.zero? ? 4 : c.number
      a.upto(b) do |i|
        old = @buffer[i - 1].text
        value = case c.kind
                when :indent
                  raise CommandError, 'line too long' if old.length + width > 80
                  ' ' * width + old
                when :unindent
                  old[[width, old[/\A */].length].min..]
                else
                  case c.option
                  when 'u' then old.upcase
                  when 'l' then old.downcase
                  else old.swapcase
                  end
                end
        set_text(i - 1, value)
      end
      @current = b
    when :sort
      sort_lines(c, range)
    when :substitute
      return substitute(c, range, output, in_global)
    when :mark
      @marks[c.option.ord - 'a'.ord] = @buffer[a - 1].id
    when :marks
      marks = @marks.each_with_index.filter_map do |id, index|
        position = locate(id)
        "#{('a'.ord + index).chr}=#{position}" if position
      end
      output << "marks #{marks.empty? ? 'none' : marks.join(' ')}"
    when :undo, :redo
      transfer_history(c.kind == :redo, c.number.zero? ? 1 : c.number)
    when :history
      output << "history undo=#{@undo.length} redo=#{@redo.length}"
      [['undo', @undo], ['redo', @redo]].each do |name, records|
        records.reverse_each.with_index { |record, i| output << "#{name} #{i + 1}: #{record.command}" }
      end
    when :read, :write, :write_append, :edit
      file_command(c, range, output)
    when :files
      files = @files.keys.sort.map { |name| "#{name}=#{@files[name].length}" }
      output << "files #{files.empty? ? 'none' : files.join(' ')}"
    when :global, :inverse
      pattern = resolve_pattern(c.search)
      selected = @buffer[a - 1...b].select { |line| line.text.include?(pattern) == (c.kind == :global) }.map(&:id)
      raise CommandError, 'no match' if selected.empty?
      substituted = false
      selected.each do |id|
        position = locate(id)
        next unless position
        @current = position
        subrange = checked_range(c.sub, 0, LineRange.new(0, 0))
        changed = execute(c.sub, subrange, text, output, in_global: true)
        substituted ||= changed
      end
      raise CommandError, 'no match' if c.sub.kind == :substitute && !substituted
    end
    print_line(@current, c.suffix, output) if c.suffix && @current.positive?
    false
  end
end

class Editor
  def initialize
    @state = EditorState.new
  end

  def apply(line, text)
    lexed = Parsing.lex_addresses(line)
    addresses = Parsing.addresses(lexed.tokens)
    command = Parsing.command(line[lexed.position..])
    raise CommandError, 'unexpected address' if command.address_kind.zero? && addresses.count.positive?
    raise CommandError, 'too many addresses' if command.address_kind == 1 && addresses.count == 2
    trial = @state.dup
    values = trial.evaluate(addresses)
    range = trial.checked_range(command, addresses.count, values)
    output = []
    trial.execute(command, range, text, output)
    raise CommandError, 'buffer full' if trial.buffer.length > 200
    if command.modifying?
      trial.undo << HistoryRecord.new(line, @state.snapshot)
      trial.redo.clear
    end
    @state = trial
    output
  end
end

editor = Editor.new
while (line = STDIN.gets)
  line = line.chomp.freeze
  break if line == 'Q'
  text = []
  if Parsing.with_text?(line)
    while (entered = STDIN.gets)
      entered = entered.chomp.freeze
      break if entered == '.'
      text << entered
    end
  end
  begin
    editor.apply(line, text).each { |message| puts message }
  rescue CommandError => error
    puts "? #{error.message}"
  end
end
