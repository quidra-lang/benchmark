require_relative 'lexer'
require_relative 'definitions'
require_relative 'expression'
require_relative 'expander'
require_relative 'include_manager'

class DirectiveError < StandardError; end
Header = Data.define(:rendering, :name, :quoted)
Block = Struct.new(:kind, :position, :parent, :chosen, :active, :else_seen, :skip_start, keyword_init: true)

class Inclusion
  attr_reader :source, :depth, :stack
  attr_accessor :display_file, :offset, :segment

  def initialize(source, depth)
    @source, @depth, @display_file, @offset = source, depth, source.path, 0
    @stack, @segment = [], []
  end

  def position(physical)
    [display_file, physical + offset]
  end

  def skipping?
    !stack.empty? && !stack[-1].active
  end
end

class Preprocessor
  CONDITIONALS = (IncludeSyntax::STARTS + IncludeSyntax::BRANCHES + ['endif']).freeze

  def initialize
    @macros, @ever_defined, @poisoned = {}, Set.new, Set.new
    @saved = Hash.new { |hash, key| hash[key] = [] }
    @manager = IncludeManager.new
    @expander = Expander.new(@macros, method(:diagnostic))
    @output, @history, @diagnostics = [], [], []
    @tree, @conditional_records, @regions = ['main.c'], [], []
    @diagnostic_counts, @condition_counts = Hash.new(0), Hash.new(0)
  end

  def diagnostic(position, kind, message)
    @diagnostics << "#{position.join(':')}: #{kind}: #{message}"
    @diagnostic_counts[kind] += 1
  end

  def event(position, content)
    @history << "#{position.join(':')}: #{content}"
  end

  def poison_check(context, tokens)
    tokens.each do |token|
      if token.kind == :identifier && @poisoned.include?(token.spelling)
        diagnostic(context.position(token.line), 'error', "attempt to use poisoned \"#{token.spelling}\"")
      end
    end
  end

  def unused_check(macro)
    if macro.main_file && macro.expanded.zero? && macro.tested.zero?
      diagnostic(macro.position, 'warning', "macro \"#{macro.name}\" is not used")
    end
  end

  def define(tokens, position, main_file)
    macro = Definitions.parse(tokens, position, main_file)
    previous = @macros[macro.name]
    if !previous
      @macros[macro.name] = macro
      @ever_defined << macro.name
      operation = 'define'
    elsif previous.identical?(macro)
      operation = 'identical'
    else
      unused_check(previous)
      diagnostic(position, 'warning', "\"#{macro.name}\" redefined (previous definition at #{previous.position.join(':')})")
      @macros[macro.name] = macro
      @ever_defined << macro.name
      operation = 'redefine'
    end
    event(position, "#{operation} #{macro.signature}")
  rescue Definitions::Error => error
    diagnostic(position, 'error', error.message)
  end

  def undefine(tokens, position)
    error = Definitions.check_name(tokens, 'undef')
    if error
      diagnostic(position, 'error', error)
      return
    end
    diagnostic(position, 'warning', 'extra tokens at end of #undef directive') if tokens.length >= 2
    name = tokens[0].spelling
    if @macros.key?(name)
      unused_check(@macros.delete(name))
      event(position, "undef #{name}")
    else
      event(position, "undef #{name} (not defined)")
    end
  end

  def process_defines
    File.binread('input/defines.txt').split("\n").each_with_index do |line, index|
      next if line.empty?
      text = line.include?('=') ? line.sub('=', ' ') : line + ' 1'
      define(Lexer.definition(text, index + 1), ['defines.txt', index + 1], false)
    end
  end

  def separator_needed?(left, right)
    return true if left == '/' && ['/', '*'].include?(right[0])
    Lexer.read_token(left + right)[2] != left.length
  end

  def output_render(tokens)
    previous = nil
    tokens.map do |token|
      space = previous && (token.space || separator_needed?(previous, token.spelling))
      previous = token.spelling
      (space ? ' ' : '') + token.spelling
    end.join
  end

  def marker(filename, line, flag = nil)
    @output << "# #{line} \"#{filename}\"" + (flag ? " #{flag}" : '')
    @previous = [filename, line - 1]
  end

  def output_line(context, physical, text)
    filename, line = context.position(physical)
    previous_file, previous_line = @previous
    if filename == previous_file && previous_line < line && line <= previous_line + 8
      @output.concat(Array.new(line - previous_line - 1, ''))
    else
      marker(filename, line)
    end
    @output << text
    @previous = [filename, line]
    context.source.output_lines += 1
  end

  def flush(context)
    segment, context.segment = context.segment, []
    return if segment.empty?
    poison_check(context, segment)
    @expander.expand(segment, context).chunk(&:line).each do |physical, tokens|
      output_line(context, physical, output_render(tokens))
    end
  end

  def macro_defined?(name)
    if @macros.key?(name)
      @macros[name].tested += 1
      true
    else
      Definitions::BUILTINS.include?(name) || name == '__has_include'
    end
  end

  def header_specification(tokens, position = 0)
    token = tokens[position]
    return [nil, position] unless token
    if [:string, :header].include?(token.kind)
      text = token.spelling
      return [Header.new(text, text[1...-1], text.start_with?('"')), position + 1]
    end
    return [nil, position] unless token.spelling == '<'
    closing = position + 1
    closing += 1 while tokens[closing] && tokens[closing].spelling != '>'
    raise DirectiveError, 'missing terminating > character' unless tokens[closing]
    text = '<' + Lexer.render(tokens[(position + 1)...closing]) + '>'
    [Header.new(text, text[1...-1], false), closing + 1]
  end

  def replace_operators(operands)
    replaced, position = [], 0
    while position < operands.length
      token = operands[position]
      index = position + 1
      if token.kind == :identifier && token.spelling == 'defined'
        parenthesized = operands[index]&.spelling == '('
        index += 1 if parenthesized
        raise DirectiveError, 'operator "defined" requires an identifier' unless operands[index]&.kind == :identifier
        name = operands[index].spelling
        index += 1
        if parenthesized
          raise DirectiveError, 'missing \')\' after "defined"' unless operands[index]&.spelling == ')'
          index += 1
        end
        value = macro_defined?(name)
      elsif token.kind == :identifier && token.spelling == '__has_include'
        raise DirectiveError, 'missing \'(\' after "__has_include"' unless operands[index]&.spelling == '('
        header, index = header_specification(operands, index + 1)
        raise DirectiveError, 'operator "__has_include" requires a header-name' if !header || header.name.empty?
        raise DirectiveError, 'missing \')\' after "__has_include" operand' unless operands[index]&.spelling == ')'
        index += 1
        value = !@manager.search(header.name, header.quoted).nil?
      else
        replaced << token
        position += 1
        next
      end
      replaced << Token.make(:number, value ? '1' : '0', token.line, token.space)
      position = index
    end
    replaced
  end

  def test(context, logical, name, operands)
    position = context.position(logical.tokens[0].line)
    poison_check(context, operands)
    unless %w[if elif].include?(name)
      if operands.empty? || operands[0].kind != :identifier
        message = operands.empty? ? "no macro name given in ##{name} directive" : 'macro names must be identifiers'
        diagnostic(position, 'error', message)
        return [nil, nil]
      end
      diagnostic(position, 'warning', "extra tokens at end of ##{name} directive") if operands.length >= 2
      value = macro_defined?(operands[0].spelling)
      value = !value if %w[ifndef elifndef].include?(name)
      return [value ? 1 : 0, nil]
    end
    expanded = nil
    replaced = replace_operators(operands)
    expanded = @expander.expand(replaced, context)
    tree = Expression.parse(expanded, name)
    value = Expression.evaluate(tree) { |message| diagnostic(position, 'warning', message) }
    [value, expanded]
  rescue DirectiveError, Expression::Error => error
    diagnostic(position, 'error', error.message)
    [nil, expanded]
  end

  def test_description(name, value, expanded)
    text = value.nil? ? 'not taken (error)' : value.zero? ? 'not taken' : 'taken'
    text += " (value #{value})" if !value.nil? && %w[if elif].include?(name)
    text += " [#{output_render(expanded)}]" unless expanded.nil?
    text
  end

  def close_region(context, block, ending)
    start = block.skip_start
    if start && ending >= start
      filename, first = context.position(start)
      last = context.position(ending)[1]
      @regions << "#{filename}:#{first}-#{last} lines=#{ending - start + 1}"
      context.source.skipped_lines += ending - start + 1
    end
    block.skip_start = nil
  end

  def conditional_record(position, depth, name, operands, description)
    directive = "##{name}" + (operands.empty? ? '' : ' ' + Lexer.render(operands))
    @conditional_records << "#{position.join(':')}: #{'  ' * depth}#{directive} => #{description}"
    categories = {'taken' => 'taken', 'not taken' => 'not_taken', 'skipped' => 'skipped',
                  'not evaluated' => 'not_evaluated', 'closes' => 'endif'}
    prefix = categories.keys.find { |item| description.start_with?(item) }
    @condition_counts[categories[prefix]] += 1
  end

  def conditional(context, logical, name, operands)
    position = context.position(logical.tokens[0].line)
    if IncludeSyntax::STARTS.include?(name)
      parent = !context.skipping?
      block = Block.new(kind: name, position: position, parent: parent, chosen: false,
                        active: false, else_seen: false, skip_start: nil)
      description = 'skipped'
      if parent
        value, expanded = test(context, logical, name, operands)
        block.chosen = block.active = !value.nil? && !value.zero?
        block.skip_start = logical.finish + 1 unless block.active
        description = test_description(name, value, expanded)
      end
      conditional_record(position, context.stack.length, name, operands, description)
      context.stack << block
      return
    end
    if context.stack.empty?
      diagnostic(position, 'error', "##{name} without #if")
      return
    end
    block, depth = context.stack[-1], context.stack.length - 1
    close_region(context, block, logical.start - 1)
    if name == 'endif'
      context.stack.pop
      diagnostic(position, 'warning', 'extra tokens at end of #endif directive') if block.parent && !operands.empty?
      description = "closes ##{block.kind} at line #{block.position[1]}"
    else
      diagnostic(position, 'error', "##{name} after #else") if block.else_seen
      if name == 'else'
        diagnostic(position, 'warning', 'extra tokens at end of #else directive') if block.parent && !operands.empty?
        block.else_seen = true
        block.active = block.parent && !block.chosen
        block.chosen = true if block.parent
        description = !block.parent ? 'skipped' : block.active ? 'taken' : 'not taken'
      elsif !block.parent
        block.active, description = false, 'skipped'
      elsif block.chosen
        block.active, description = false, 'not evaluated'
      else
        value, expanded = test(context, logical, name, operands)
        block.active = !value.nil? && !value.zero?
        block.chosen = true if block.active
        description = test_description(name, value, expanded)
      end
      block.skip_start = logical.finish + 1 if block.parent && !block.active
    end
    conditional_record(position, depth, name, operands, description)
  end

  def include_file(context, logical, operands)
    position = context.position(logical.tokens[0].line)
    sequence = operands
    header, consumed = header_specification(sequence)
    if !header && !sequence.empty?
      sequence = @expander.expand(sequence, context)
      header, consumed = header_specification(sequence)
    end
    raise DirectiveError, '#include expects "FILENAME" or <FILENAME>' unless header
    diagnostic(position, 'warning', 'extra tokens at end of #include directive') if consumed < sequence.length
    raise DirectiveError, 'empty filename in #include' if header.name.empty?
    prefix = '  ' * (context.depth + 1) + "#{logical.tokens[0].line}: "
    path = @manager.search(header.name, header.quoted)
    unless path
      @tree << prefix + header.rendering + ' [not found]'
      diagnostic(position, 'error', 'cannot find include file ' + header.rendering)
      return
    end
    previous = @manager.files[path]
    if previous && (previous.once || previous.guard && @macros.key?(previous.guard))
      reason = previous.once ? 'pragma once' : "guard #{previous.guard}"
      @tree << prefix + path + " [skipped: #{reason}]"
      previous.skipped += 1
    elsif context.depth + 1 > 8
      @tree << prefix + path + ' [too deep]'
      diagnostic(position, 'error', '#include nested too deeply')
    else
      @tree << prefix + path
      marker(path, 1, 1)
      process_file(path, context.depth + 1)
      filename, line = context.position(logical.finish + 1)
      marker(filename, line, 2)
    end
  rescue DirectiveError => error
    diagnostic(position, 'error', error.message)
  end

  def decimal_token?(token)
    token&.kind == :number && token.spelling.match?(/\A[0-9]+\z/)
  end

  def line_directive(context, logical, operands)
    position = context.position(logical.tokens[0].line)
    operands = @expander.expand(operands, context) unless decimal_token?(operands[0])
    unless [1, 2].include?(operands.length) && decimal_token?(operands[0]) && (operands.length == 1 || operands[1].kind == :string)
      diagnostic(position, 'error', 'invalid #line directive')
      return
    end
    line = operands[0].spelling.to_i
    unless (1..2_147_483_647).cover?(line)
      diagnostic(position, 'error', 'line number out of range')
      return
    end
    context.offset = line - logical.finish - 1
    context.display_file = operands[1].spelling[1...-1] if operands.length == 2
  end

  def macro_pragma(position, operands, operation)
    unless operands.length == 4 && operands[1].spelling == '(' && operands[2].kind == :string && operands[3].spelling == ')'
      diagnostic(position, 'error', "invalid #pragma #{operation} directive")
      return
    end
    name = operands[2].spelling[1...-1]
    if operation == 'push_macro'
      @saved[name] << @macros[name]
      event(position, "push #{name}")
    elsif @saved[name].empty?
      diagnostic(position, 'warning', "no matching push_macro for \"#{name}\"")
    else
      macro = @saved[name].pop
      if macro
        @macros[name] = macro
      else
        @macros.delete(name)
      end
      event(position, "pop #{name}" + (macro ? '' : ' (undefined)'))
    end
  end

  def pragma(context, logical, operands)
    position = context.position(logical.tokens[0].line)
    name = operands[0]&.kind == :identifier ? operands[0].spelling : nil
    if name == 'once'
      diagnostic(position, 'warning', 'extra tokens at end of #pragma once directive') if operands.length >= 2
      diagnostic(position, 'warning', '#pragma once in main file') if context.depth.zero?
      context.source.once = true
    elsif operands.take(2).map(&:spelling) == %w[GCC poison]
      unless operands.drop(2).all? { |token| token.kind == :identifier }
        diagnostic(position, 'error', 'invalid #pragma GCC poison directive')
        return
      end
      operands.drop(2).each do |token|
        diagnostic(position, 'warning', "poisoning existing macro \"#{token.spelling}\"") if @macros.key?(token.spelling)
        @poisoned << token.spelling
      end
    elsif %w[push_macro pop_macro].include?(name)
      macro_pragma(position, operands, name)
    else
      output_line(context, logical.tokens[0].line, '#pragma' + (operands.empty? ? '' : ' ' + Lexer.render(operands)))
    end
  end

  def directive(context, logical, name, operands)
    return if logical.tokens.length == 1
    poisoning = name == 'pragma' && operands.take(2).map(&:spelling) == %w[GCC poison]
    poison_check(context, operands) unless poisoning
    position = context.position(logical.tokens[0].line)
    case name
    when 'define' then define(operands, position, context.depth.zero?)
    when 'undef' then undefine(operands, position)
    when 'include' then include_file(context, logical, operands)
    when 'line' then line_directive(context, logical, operands)
    when 'error', 'warning'
      diagnostic(position, name, "##{name}" + (operands.empty? ? '' : ' ' + Lexer.render(operands)))
    when 'pragma' then pragma(context, logical, operands)
    else diagnostic(position, 'error', 'invalid preprocessing directive #' + logical.tokens[1].spelling)
    end
  end

  def process_file(path, depth)
    source = @manager.load(path)
    source.entered += 1
    context = Inclusion.new(source, depth)
    source.lines.each do |logical|
      tokens = logical.tokens
      name, operands = IncludeSyntax.directive_name(tokens), tokens.drop(2)
      if tokens[0]&.spelling == '#' && CONDITIONALS.include?(name)
        flush(context)
        conditional(context, logical, name, operands)
      elsif context.skipping?
        next
      elsif tokens[0]&.spelling == '#'
        flush(context)
        directive(context, logical, name, operands)
      else
        context.segment.concat(tokens)
      end
    end
    flush(context)
    context.stack.each { |block| close_region(context, block, source.physical_lines) }
    context.stack.each { |block| diagnostic(block.position, 'error', "unterminated ##{block.kind}") }
  end

  def include_report
    lines = @tree + ['', '== files ==']
    @manager.files.keys.sort.each do |path|
      source = @manager.files[path]
      lines << "#{path} entered=#{source.entered} skipped=#{source.skipped} lines=#{source.physical_lines} " \
               "output_lines=#{source.output_lines} skipped_lines=#{source.skipped_lines} guard=#{source.guard || '-'} once=#{source.once ? 'yes' : 'no'}"
    end
    lines << ''
    current, has_path = +'main.o:', false
    @manager.files.each_key do |path|
      if current.length + 1 + path.length > 76 && has_path
        lines << current + ' \\'
        current, has_path = +' ', false
      end
      current << ' ' << path
      has_path = true
    end
    lines << current
  end

  def references
    @macros.to_h do |name, macro|
      refs = macro.replacement.filter_map do |token|
        token.spelling if token.kind == :identifier && @macros.key?(token.spelling) && !(macro.parameters || []).include?(token.spelling)
      end
      [name, refs.uniq.sort]
    end
  end

  def recursive?(name, refs)
    pending, seen = refs[name].dup, Set.new
    until pending.empty?
      current = pending.pop
      return true if current == name
      pending.concat(refs[current]) if seen.add?(current)
    end
    false
  end

  def following(heading, items)
    heading + items.map { |item| ' ' + item }.join
  end

  def macro_report
    lines = ['== history ==', *@history, '', '== table ==']
    refs = references
    @macros.keys.sort.each do |name|
      macro = @macros[name]
      lines << "#define #{macro.signature}" + (macro.replacement.empty? ? '' : ' ' + Lexer.render(macro.replacement))
      lines << "  at #{macro.position.join(':')} expanded=#{macro.expanded} tested=#{macro.tested} recursive=#{recursive?(name, refs) ? 'yes' : 'no'}"
      lines << following('  refs:', refs[name])
    end
    objects = @macros.values.count { |macro| macro.parameters.nil? }
    lines.concat(['', "macros=#{@macros.length} object_like=#{objects} function_like=#{@macros.length - objects}"])
    lines << following('undefined:', (@ever_defined - @macros.keys.to_set).to_a.sort)
    counts = @expander.builtin_counts
    lines << "builtins: __COUNTER__=#{counts['__COUNTER__']} __FILE__=#{counts['__FILE__']} __LINE__=#{counts['__LINE__']}"
  end

  def conditional_report
    counts = @condition_counts
    @conditional_records + ['', '== skipped regions ==', *@regions, '',
      "directives=#{@conditional_records.length} taken=#{counts['taken']} not_taken=#{counts['not_taken']} " \
      "skipped=#{counts['skipped']} not_evaluated=#{counts['not_evaluated']} endif=#{counts['endif']} regions=#{@regions.length}"]
  end

  def write_reports
    reports = {'preprocessed.txt' => @output, 'includes.txt' => include_report, 'macros.txt' => macro_report,
               'conditionals.txt' => conditional_report,
               'diagnostics.txt' => @diagnostics + ["errors=#{@diagnostic_counts['error']} warnings=#{@diagnostic_counts['warning']}"]}
    Dir.mkdir('output') unless Dir.exist?('output')
    reports.each do |name, lines|
      File.binwrite(File.join('output', name), lines.map { |line| line.sub(/ +\z/, '') }.join("\n") + "\n")
    end
  end

  def run
    process_defines
    marker('main.c', 1)
    process_file('main.c', 0)
    @macros.keys.sort.each { |name| unused_check(@macros[name]) }
    write_reports
  end
end

Preprocessor.new.run if $PROGRAM_NAME == __FILE__
