require_relative 'charset'
require_relative 'formatter'
require_relative 'backtrack_vm'
require_relative 'pike_vm'

class Pattern
  class ParseError < StandardError
    attr_reader :column
    def initialize(message, column)
      super(message)
      @column = column
    end
  end
  attr_reader :name, :flags, :source, :groups, :names, :error, :program, :root

  def initialize(name, flags, source)
    @name, @flags, @source = name, flags, source
    @at, @groups, @names, @references = 0, 0, {}, []
    @root = alternation
    fail_at('unmatched )', @at) if peek
    @references.each do |node, position|
      if node[1].is_a?(String)
        fail_at('unknown group name', position) unless @names.key?(node[1])
        node[1] = @names[node[1]]
      else
        fail_at('invalid group reference', position) if node[1] > @groups
      end
    end
    @program = [[:save, 0]]
    compile(@root)
    @program.concat([[:save, 1], [:match]])
  rescue ParseError => e
    @error = e
  end

  def peek
    @source[@at]
  end

  def take
    char = peek
    @at += 1 if char
    char
  end

  def fail_at(message, position)
    raise ParseError.new(message, position + 1)
  end

  def quantifier?(char)
    char && '*+?{'.include?(char)
  end

  def alternation
    nodes = [concatenation]
    while peek == '|'
      take
      nodes << concatenation
    end
    nodes.length == 1 ? nodes[0] : [:alt, nodes]
  end

  def concatenation
    nodes = []
    nodes << quantified while peek && !['|', ')'].include?(peek)
    nodes.length == 1 ? nodes[0] : [:cat, nodes]
  end

  def quantified
    fail_at('nothing to repeat', @at) if quantifier?(peek)
    node = element
    return node unless quantifier?(peek)
    fail_at('nothing to repeat', @at) if [:assert, :look].include?(node[0])
    position, char = @at, take
    minimum, maximum = case char
                       when '*' then [0, nil]
                       when '+' then [1, nil]
                       when '?' then [0, 1]
                       else read_bounds(position)
                       end
    kind = peek == '?' ? (take; :lazy) : peek == '+' ? (take; :possessive) : :greedy
    fail_at('nested quantifier', @at) if quantifier?(peek)
    [:repeat, node, minimum, maximum, kind]
  end

  def read_digits
    first = @at
    take while Charset.digit?(peek&.ord)
    @source[first...@at]
  end

  def read_bounds(position)
    digits = read_digits
    fail_at('invalid quantifier', position) if digits.empty?
    minimum = digits.to_i
    if peek == '}'
      maximum = minimum
    elsif take == ','
      digits = read_digits
      maximum = digits.empty? ? nil : digits.to_i
      fail_at('invalid quantifier', position) unless peek == '}'
    else
      fail_at('invalid quantifier', position)
    end
    take
    fail_at('quantifier too large', position) if minimum > 100 || (maximum && maximum > 100)
    fail_at('quantifier range out of order', position) if maximum && minimum > maximum
    [minimum, maximum]
  end

  def element
    position = @at
    case take
    when '(' then group(position)
    when '[' then character_class(position)
    when '\\' then escape(position)
    when '.' then [:any]
    when '^' then [:assert, :BOL]
    when '$' then [:assert, :EOL]
    else [:char, @source.getbyte(position)]
    end
  end

  def read_name
    first = @at
    if Charset.letter?(peek&.ord) || peek == '_'
      take
      take while Charset.letter?(peek&.ord) || Charset.digit?(peek&.ord) || peek == '_'
    end
    name = @source[first...@at]
    fail_at('invalid group name', @at) if name.empty? || peek != '>'
    take
    name
  end

  def group(position)
    kind = :capture
    if peek == '?'
      take
      kind = { ':' => :plain, '=' => :AHEAD, '!' => :NOT, '<' => :named }[take]
      fail_at('invalid group', position) unless kind
    end
    if kind == :named
      name_position = @at
      name = read_name
      fail_at('duplicate group name', name_position) if @names.key?(name)
    end
    if [:capture, :named].include?(kind)
      @groups += 1
      number = @groups
      @names[name] = number if kind == :named
    end
    body = alternation
    fail_at('missing )', position) unless take == ')'
    case kind
    when :plain then body
    when :capture, :named then [:group, number, body]
    else [:look, kind, body]
    end
  end

  def class_item
    position, char = @at, take
    return char.ord unless char == '\\'
    char = take
    fail_at('trailing backslash', position) unless char
    return Charset.predefined(char) if 'dDwWsS'.include?(char)
    return 10 if char == 'n'
    return 9 if char == 't'
    fail_at('invalid escape', position) if Charset.letter?(char.ord) || Charset.digit?(char.ord)
    char.ord
  end

  def character_class(position)
    negated = peek == '^'
    take if negated
    fail_at('empty class', @at) if peek == ']'
    set = []
    loop do
      fail_at('missing ]', position) unless peek
      break if peek == ']'
      item = class_item
      if peek == '-' && @source[@at + 1] && @source[@at + 1] != ']'
        dash = @at
        take
        fail_at('invalid range', dash) if item.is_a?(Array)
        last = class_item
        fail_at('invalid range', dash) if last.is_a?(Array) || item > last
        set |= (item..last).to_a
      else
        set |= Array(item)
      end
    end
    take
    [:class, set.sort, negated]
  end

  def escape(position)
    char = take
    fail_at('trailing backslash', position) unless char
    if 'dDwWsS'.include?(char)
      base = Charset.predefined(char.downcase)
      return [:class, base, char != char.downcase]
    end
    return [:assert, char == 'b' ? :WORD : :NOTWORD] if ['b', 'B'].include?(char)
    return [:char, char == 'n' ? 10 : 9] if ['n', 't'].include?(char)
    if ('1'..'9').cover?(char)
      node = [:backref, (char + read_digits).to_i]
    elsif char == 'k'
      fail_at('invalid escape', position) unless take == '<'
      node = [:backref, read_name]
    else
      fail_at('invalid escape', position) if Charset.letter?(char.ord) || Charset.digit?(char.ord)
      return [:char, char.ord]
    end
    @references << [node, position]
    node
  end

  def emit(*instruction)
    @program << instruction
    @program.length - 1
  end

  def compile(node)
    op, a, b, c, kind = node
    case op
    when :char, :any, :class, :assert, :backref then emit(*node)
    when :group
      emit(:save, 2 * a)
      compile(b)
      emit(:save, 2 * a + 1)
    when :cat then a.each { |part| compile(part) }
    when :alt
      jumps = []
      a[0...-1].each do |part|
        split = emit(:split, @program.length + 1, nil)
        compile(part)
        jumps << emit(:jmp, nil)
        @program[split][2] = @program.length
      end
      compile(a[-1])
      jumps.each { |p| @program[p][1] = @program.length }
    when :look
      p = emit(:look, a, nil)
      compile(b)
      emit(:match)
      @program[p][2] = @program.length
    when :repeat
      if kind == :possessive
        p = emit(:look, :ATOMIC, nil)
        compile([:repeat, a, b, c, :greedy])
        emit(:match)
        @program[p][2] = @program.length
      elsif c.nil?
        if b.zero?
          p = emit(:split, nil, nil)
          compile(a)
          emit(:jmp, p)
          @program[p][1, 2] = kind == :lazy ? [@program.length, p + 1] : [p + 1, @program.length]
        else
          (b - 1).times { compile(a) }
          first = @program.length
          compile(a)
          p = emit(:split, nil, nil)
          @program[p][1, 2] = kind == :lazy ? [p + 1, first] : [first, p + 1]
        end
      else
        b.times { compile(a) }
        splits = []
        (c - b).times do
          p = emit(:split, nil, nil)
          splits << p
          compile(a)
        end
        splits.each { |p| @program[p][1, 2] = kind == :lazy ? [@program.length, p + 1] : [p + 1, @program.length] }
      end
    end
  end

  def compatible?
    @program.none? { |i| [:look, :backref].include?(i[0]) }
  end

  # Properties are derived from the tree, including deliberately conservative backreferences.
  def properties(node = @root)
    op, a, b, c = node
    case op
    when :char then [1, 1, Charset::ALL.select { |x| Charset.equal?(x, a, @flags) }, false]
    when :any then [1, 1, Charset::ALL.select { |x| @flags.include?('s') || x != 10 }, false]
    when :class then [1, 1, Charset::ALL.select { |x| Charset.class?(x, a, b, @flags) }, false]
    when :assert, :look then [0, 0, [], true]
    when :backref then [0, nil, Charset::ALL, true]
    when :group then properties(b)
    when :repeat
      minimum, maximum, set, nullable = properties(a)
      high = maximum == 0 ? 0 : maximum.nil? || c.nil? ? nil : maximum * c
      [minimum * b, high, c == 0 ? [] : set, c == 0 || b == 0 || nullable]
    when :alt, :cat
      parts = a.map { |child| properties(child) }
      if op == :alt
        [parts.map(&:first).min, parts.any? { |p| p[1].nil? } ? nil : parts.map { |p| p[1] }.max,
         parts.flat_map { |p| p[2] }.uniq, parts.any? { |p| p[3] }]
      else
        first, nullable = [], true
        parts.each do |part|
          first |= part[2]
          unless part[3]
            nullable = false
            break
          end
        end
        [parts.sum(&:first), parts.any? { |p| p[1].nil? } ? nil : parts.sum { |p| p[1] }, first, nullable]
      end
    end
  end
end

module RegexApplication
  def self.decode(quoted)
    result, at = +'', 1
    while at < quoted.length - 1
      char = quoted[at]
      if char == '\\'
        at += 1
        char = { 'n' => "\n", 't' => "\t", '\\' => '\\', '"' => '"' }[quoted[at]]
      end
      result << char
      at += 1
    end
    result
  end

  def self.template(text, pattern)
    parts, at = [], 0
    while at < text.length
      if text[at] != '$'
        parts << text[at]
      elsif text[at + 1] == '$'
        parts << '$'
        at += 1
      elsif Charset.digit?(text.getbyte(at + 1))
        at += 1
        parts << text[at].to_i
      elsif text[at + 1] == '{'
        last = text.index('}', at + 2)
        return nil unless last
        name = text[(at + 2)...last]
        number = if !name.empty? && name.bytes.all? { |c| Charset.digit?(c) }
                   name.to_i
                 else pattern.names[name]
                 end
        return nil unless number
        parts << number
        at = last
      else
        return nil
      end
      return nil if parts[-1].is_a?(Integer) && parts[-1] > pattern.groups
      at += 1
    end
    parts
  end

  def self.scan(vm, text, once, full)
    matches, start = [], 0
    while start <= text.length
      match = vm.search(start, full)
      break unless match
      matches << match
      break if once
      start = match[1] > match[0] ? match[1] : match[1] + 1
    end
    matches
  end

  def self.capture(text, c, k)
    first, last = c[2 * k, 2]
    first && last ? text[first...last] : nil
  end

  def self.match_lines(text, c, groups)
    lines = ["match #{c[0]}-#{c[1]} #{Formatter.quote(capture(text, c, 0))}"]
    (1..groups).each do |k|
      value = capture(text, c, k)
      lines << (value ? "group #{k} #{c[2 * k]}-#{c[2 * k + 1]} #{Formatter.quote(value)}" : "group #{k} -")
    end
    lines
  end

  def self.run
    patterns = {}
    File.readlines('input/patterns.txt', chomp: true).each do |line|
      first = line.index(' ')
      second = line.index(' ', first + 1)
      name, flags, source = line[0...first], line[(first + 1)...second], line[(second + 1)..]
      patterns[name] = Pattern.new(name, flags, source)
    end
    subjects = {}
    File.readlines('input/subjects.txt', chomp: true).each do |line|
      name, value = line.split(' ', 2)
      subjects[name] = decode(value)
    end
    results, programs, steps, errors = [], [], ['command,engine,steps'], []
    patterns.each_value do |p|
      errors.concat(["#{p.name}: #{p.error.message} at column #{p.error.column}", "  #{p.source}", '  ' + ' ' * (p.error.column - 1) + '^']) if p.error
    end
    File.readlines('input/commands.txt', chomp: true).each_with_index do |line, index|
      number = index + 1
      results << "##{number} #{line}"
      command, rest = line.split(' ', 2)
      mode, rest = rest.split(' ', 2) if command == 'REPLACE'
      name, subject, replacement = rest.split(' ', 3)
      p = patterns.fetch(name)
      if p.error
        results << 'invalid pattern'
        next
      end
      if command == 'LIST'
        results << "instructions #{p.program.length}"
        minimum, maximum, first = p.properties
        names = p.names.map { |key, value| "#{key}:#{value}" }.join(',')
        programs << "=== #{p.name}"
        programs << "flags=#{p.flags} groups=#{p.groups} names=#{names.empty? ? '-' : names} length=#{minimum}..#{maximum || 'inf'} first=#{first.empty? ? '-' : Formatter.set(first)} pike=#{p.compatible? ? 'yes' : 'no'} size=#{p.program.length}"
        p.program.each_with_index { |instruction, i| programs << "#{i} #{Formatter.instruction(instruction)}" }
        next
      end
      parts = template(decode(replacement), p) if command == 'REPLACE'
      if command == 'REPLACE' && !parts
        results << 'invalid template'
        next
      end
      text = subjects.fetch(subject)
      once = ['MATCH', 'SEARCH'].include?(command) || (command == 'REPLACE' && mode == 'FIRST')
      vm = BacktrackVM.new(p.program, p.groups, p.flags, text)
      aborted = false
      begin
        matches = scan(vm, text, once, command == 'MATCH')
      rescue BacktrackVM::TooManySteps
        aborted = true
      end
      steps << "#{number},backtrack,#{vm.steps}"
      if p.compatible?
        pike = PikeVM.new(p.program, p.groups, p.flags, text)
        other = scan(pike, text, once, command == 'MATCH')
        steps << "#{number},pike,#{pike.steps}"
        if !aborted && matches != other
          results << 'MISMATCH'
          next
        end
        matches = other
        engine = aborted ? 'pike (backtrack: TOO_MANY_STEPS)' : 'both'
      elsif aborted
        results << 'TOO_MANY_STEPS'
        next
      else
        engine = 'backtrack'
      end
      results << "engine #{engine}"
      case command
      when 'MATCH', 'SEARCH'
        results.concat(matches.empty? ? ['no match'] : match_lines(text, matches[0], p.groups))
      when 'FINDALL'
        results << "matches #{matches.length}"
        matches.each { |c| results.concat(match_lines(text, c, p.groups)) }
      when 'REPLACE'
        value, at = +'', 0
        matches.each do |c|
          value << text[at...c[0]]
          parts.each { |part| value << (part.is_a?(Integer) ? capture(text, c, part).to_s : part) }
          at = c[1]
        end
        value << text[at..]
        results.concat(["replacements #{matches.length}", "result #{Formatter.quote(value)}"])
      when 'SPLIT'
        results << "pieces #{matches.length + 1}"
        at = 0
        matches.each do |c|
          results << "piece #{Formatter.quote(text[at...c[0]])}"
          (1..p.groups).each do |k|
            value = capture(text, c, k)
            results << (value ? "group #{k} #{Formatter.quote(value)}" : "group #{k} -")
          end
          at = c[1]
        end
        results << "piece #{Formatter.quote(text[at..])}"
      end
    end
    { 'results.txt' => results, 'programs.txt' => programs.empty? ? ['no programs'] : programs,
      'steps.csv' => steps, 'errors.txt' => errors.empty? ? ['no errors'] : errors }.each do |name, lines|
      File.write("output/#{name}", lines.join("\n") + "\n")
    end
  end
end

RegexApplication.run if $PROGRAM_NAME == __FILE__
