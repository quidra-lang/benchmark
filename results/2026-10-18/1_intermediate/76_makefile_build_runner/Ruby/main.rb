class MakeError < StandardError
  attr_reader :location

  def initialize(reason, location)
    super(reason)
    @location = location
  end
end

class BuildAbort < StandardError; end
Rule = Struct.new(:target, :prerequisites, :recipe, :stem)

class MakeWorkbench
  FUNCTIONS = {
    'subst' => [3, 3], 'patsubst' => [3, 3], 'strip' => [1, 1],
    'findstring' => [2, 2], 'filter' => [2, 2], 'filter-out' => [2, 2],
    'sort' => [1, 1], 'word' => [2, 2], 'wordlist' => [3, 3],
    'words' => [1, 1], 'firstword' => [1, 1], 'lastword' => [1, 1],
    'dir' => [1, 1], 'notdir' => [1, 1], 'suffix' => [1, 1],
    'basename' => [1, 1], 'addsuffix' => [2, 2], 'addprefix' => [2, 2],
    'wildcard' => [1, 1], 'foreach' => [3, 3], 'if' => [2, 3],
    'call' => [1, nil], 'value' => [1, 1], 'info' => [1, 1],
    'warning' => [1, 1], 'error' => [1, 1]
  }.freeze

  def initialize(files)
    @files = files
    @clock = files.values.max || 0
    @location = 'make'
    @scopes = []
    @active_variables = {}
    @automatic = nil
    clear_makefile
  end

  def trim(text)
    text.sub(/\A +/, '').sub(/ +\z/, '')
  end

  def words(text)
    text.split(' ').reject(&:empty?)
  end

  def error(reason)
    raise MakeError.new(reason, @location)
  end

  def report(error)
    puts "#{error.location}: *** #{error.message}.  Stop."
  end

  def clear_makefile
    @loaded = false
    @variables = {}
    @rules = {}
    @patterns = []
    @phony = {}
    @default = nil
  end

  def closing(text, opening)
    left = text[opening]
    right = left == '(' ? ')' : '}'
    depth = 0
    (opening...text.length).each do |i|
      depth += 1 if text[i] == left
      depth -= 1 if text[i] == right
      return i if depth.zero?
    end
    error('unterminated variable reference')
  end

  def outside(text)
    result = {}
    i = 0
    while i < text.length
      if text[i] == '$'
        i = ['(', '{'].include?(text[i + 1]) ? closing(text, i + 1) + 1 : i + 2
      else
        result[text[i]] ||= i
        i += 1
      end
    end
    result
  end

  def stem(pattern, text)
    percent = pattern.index('%')
    return pattern == text ? '' : nil unless percent
    left = pattern[0...percent]
    right = pattern[(percent + 1)..]
    return nil unless text.length >= left.length + right.length && text.start_with?(left) && text.end_with?(right)
    text[left.length, text.length - left.length - right.length]
  end

  def substitute(text, value)
    text.sub('%') { value }
  end

  def replace(word, pattern, replacement)
    value = stem(pattern, word)
    return word unless value
    pattern.include?('%') ? substitute(replacement, value) : replacement
  end

  def wildcard(pattern)
    unless pattern.include?('*') || pattern.include?('?')
      return @files.key?(pattern) ? [pattern] : []
    end
    regex = Regexp.new('\\A' + Regexp.escape(pattern).gsub('\\*', '[^/]*').gsub('\\?', '[^/]') + '\\z')
    @files.keys.select { |name| regex.match?(name) }.sort
  end

  def reference_value(name)
    @scopes.reverse_each do |scope|
      if scope[0] == :foreach
        return scope[2] if scope[1] == name
      elsif /\A[0-9]+\z/.match?(name)
        return scope[1][name.to_i] || ''
      end
    end
    return @automatic[name] if @automatic && @automatic.key?(name)
    variable_value(name)
  end

  def variable_value(name)
    variable = @variables[name]
    return '' unless variable
    return variable[1] if variable[0] == ':='
    error("Recursive variable '#{name}' references itself (eventually)") if @active_variables[name]
    @active_variables[name] = true
    begin
      expand(variable[1])
    ensure
      @active_variables.delete(name)
    end
  end

  def expand(text)
    result = +''
    i = 0
    while i < text.length
      if text[i] != '$'
        result << text[i]
        i += 1
      elsif text[i + 1] == '$'
        result << '$'
        i += 2
      elsif ['(', '{'].include?(text[i + 1])
        finish = closing(text, i + 1)
        result << reference(text[(i + 2)...finish], text[i + 1])
        i = finish + 1
      else
        result << reference_value(text[i + 1]) if i + 1 < text.length
        i += 2
      end
    end
    result
  end

  def reference(content, bracket)
    space = content.index(' ')
    if space && FUNCTIONS.key?(content[0...space])
      return function(content[0...space], content[(space + 1)..].sub(/\A +/, ''), bracket)
    end
    name = expand(content)
    colon = name.index(':')
    equals = colon ? name.index('=', colon + 1) : nil
    return reference_value(name) unless equals
    variable = name[0...colon]
    pattern = name[(colon + 1)...equals]
    replacement = name[(equals + 1)..]
    unless pattern.include?('%')
      pattern = '%' + pattern
      replacement = '%' + replacement
    end
    words(reference_value(variable)).map { |word| replace(word, pattern, replacement) }.join(' ')
  end

  def function(name, text, bracket)
    minimum, maximum = FUNCTIONS[name]
    args = []
    depth = 0
    start = 0
    close = bracket == '(' ? ')' : '}'
    text.each_char.with_index do |char, i|
      depth += 1 if char == bracket
      depth -= 1 if char == close
      if char == ',' && depth.zero? && (!maximum || args.length < maximum - 1)
        args << text[start...i]
        start = i + 1
      end
    end
    args << text[start..]
    error("insufficient number of arguments (#{args.length}) to function '#{name}'") if args.length < minimum
    if name == 'foreach'
      variable = trim(expand(args[0]))
      list = words(expand(args[1]))
      return list.map do |word|
        @scopes << [:foreach, variable, word]
        begin
          expand(args[2])
        ensure
          @scopes.pop
        end
      end.join(' ')
    end
    if name == 'if'
      condition = trim(expand(args[0]))
      return expand(condition.empty? ? (args[2] || '') : args[1])
    end
    if name == 'call'
      values = args.map { |arg| expand(arg) }
      variable = trim(values.shift)
      entry = @variables[variable]
      return '' unless entry
      return entry[1] if entry[0] == ':='
      @scopes << [:call, [variable] + values]
      begin
        return expand(entry[1])
      ensure
        @scopes.pop
      end
    end
    values = args.map { |arg| expand(arg) }
    values.map! { |arg| trim(arg) } unless name == 'subst'
    a, b, c = values
    case name
    when 'subst'
      a.empty? ? c : c.gsub(a) { b }
    when 'patsubst'
      words(c).map { |word| replace(word, a, b) }.join(' ')
    when 'strip'
      words(a).join(' ')
    when 'findstring'
      b.include?(a) ? a : ''
    when 'filter', 'filter-out'
      patterns = words(a)
      words(b).select { |word| patterns.any? { |pattern| !stem(pattern, word).nil? } == (name == 'filter') }.join(' ')
    when 'sort'
      words(a).uniq.sort.join(' ')
    when 'word'
      error("non-numeric first argument to 'word' function: '#{a}'") unless /\A[0-9]+\z/.match?(a)
      error("first argument to 'word' function must be greater than 0") if a.to_i.zero?
      words(b)[a.to_i - 1] || ''
    when 'wordlist'
      error("non-numeric first argument to 'wordlist' function: '#{a}'") unless /\A[0-9]+\z/.match?(a)
      error("non-numeric second argument to 'wordlist' function: '#{b}'") unless /\A[0-9]+\z/.match?(b)
      error("invalid first argument to 'wordlist' function: '#{a}'") if a.to_i.zero?
      b.to_i < a.to_i ? '' : words(c).drop(a.to_i - 1).take(b.to_i - a.to_i + 1).join(' ')
    when 'words'
      words(a).length.to_s
    when 'firstword'
      words(a).first || ''
    when 'lastword'
      words(a).last || ''
    when 'dir'
      words(a).map { |word| word.include?('/') ? word[0..word.rindex('/')] : './' }.join(' ')
    when 'notdir'
      words(a).map { |word| word[(word.rindex('/') || -1) + 1..] }.join(' ')
    when 'suffix', 'basename'
      words(a).filter_map do |word|
        dot = word.rindex('.')
        slash = word.rindex('/') || -1
        extension = dot && dot > slash
        name == 'suffix' ? (extension ? word[dot..] : nil) : (extension ? word[0...dot] : word)
      end.join(' ')
    when 'addsuffix'
      words(b).map { |word| word + a }.join(' ')
    when 'addprefix'
      words(b).map { |word| a + word }.join(' ')
    when 'wildcard'
      words(a).flat_map { |pattern| wildcard(pattern) }.join(' ')
    when 'value'
      @variables[a]&.[](1) || ''
    when 'info'
      puts a
      ''
    when 'warning'
      puts "#{@location}: #{a}"
      ''
    when 'error'
      error(a)
    end
  end

  def register(target, prerequisites)
    @rules[target] ||= Rule.new(target, [], nil, '')
    rule = @rules[target]
    rule.prerequisites = (rule.prerequisites + prerequisites).uniq
    @default ||= target unless target.start_with?('.')
    rule
  end

  def add_recipe(current, number, text)
    error('recipe commences before first target') unless current
    return if current[:entries].empty?
    unless current[:recipe]
      recipe = []
      current[:entries].each do |rule|
        if current[:explicit] && rule.recipe
          puts "Makefile:#{number}: warning: overriding recipe for target '#{rule.target}'"
          puts "Makefile:#{rule.recipe.first[0]}: warning: ignoring old recipe for target '#{rule.target}'"
        end
        rule.recipe = recipe
      end
      current[:recipe] = recipe
    end
    current[:recipe] << [number, text]
  end

  def parse_rule(text, colon, number)
    targets = words(expand(text[0...colon])).uniq
    rest = text[(colon + 1)..]
    semicolon = outside(rest)[';']
    inline = semicolon ? rest[(semicolon + 1)..].sub(/\A +/, '') : nil
    rest = rest[0...semicolon] if semicolon
    second = outside(rest)[':']
    pattern = second ? trim(expand(rest[0...second])) : nil
    rest = rest[(second + 1)..] if second
    prerequisites = words(expand(rest))
    entries = []
    explicit = true
    if targets == ['.PHONY']
      prerequisites.each { |target| @phony[target] = true }
    elsif pattern
      error("target pattern contains no '%'") unless pattern.include?('%')
      targets.each do |target|
        value = stem(pattern, target)
        if value && !value.empty?
          entry = register(target, prerequisites.map { |p| substitute(p, value) })
          entry.stem = value
          entries << entry
        else
          puts "Makefile:#{number}: target '#{target}' doesn't match the target pattern"
        end
      end
    elsif targets.any? { |target| target.include?('%') }
      error('mixed implicit and normal rules') unless targets.all? { |target| target.include?('%') }
      explicit = false
      targets.each do |target|
        entry = Rule.new(target, prerequisites.dup, nil, '')
        @patterns << entry
        entries << entry
      end
    else
      entries = targets.map { |target| register(target, prerequisites) }
    end
    current = { entries: entries, explicit: explicit, recipe: nil }
    add_recipe(current, number, inline) unless inline.nil?
    current
  end

  def load_makefile(body)
    clear_makefile
    current = nil
    conditions = []
    i = 0
    while i < body.length
      number = i + 1
      @location = "Makefile:#{number}"
      active = conditions.empty? || (conditions.last[:outer] && conditions.last[:value])
      text = body[i]
      i += 1
      if text.start_with?('>')
        add_recipe(current, number, text[1..].sub(/\A +/, '')) if active
        next
      end
      while text.end_with?('\\') && i < body.length
        text = text[0...-1].sub(/ +\z/, '') + ' ' + body[i].sub(/\A +/, '')
        i += 1
      end
      text = trim(text.split('#', 2).first || '')
      first, rest = text.split(' ', 2)
      rest = trim(rest || '')
      if %w[ifdef ifndef ifeq ifneq].include?(first)
        value = false
        if active
          if %w[ifdef ifndef].include?(first)
            variable = @variables[trim(expand(rest))]
            value = !variable.nil? && !variable[1].empty?
            value = !value if first == 'ifndef'
          else
            error('invalid syntax in conditional') unless rest.length >= 2 && rest.start_with?('(') && rest.end_with?(')')
            inner = rest[1...-1]
            depth = 0
            comma = nil
            inner.each_char.with_index do |char, p|
              depth += 1 if char == '('
              depth -= 1 if char == ')'
              if char == ',' && depth.zero?
                comma = p
                break
              end
            end
            error('invalid syntax in conditional') unless comma
            left = trim(expand(inner[0...comma]))
            right = trim(expand(inner[(comma + 1)..]))
            value = left == right
            value = !value if first == 'ifneq'
          end
        end
        conditions << { outer: active, value: value, seen_else: false, number: number }
      elsif first == 'else'
        error("extraneous 'else'") if conditions.empty?
        error("only one 'else' per conditional") if conditions.last[:seen_else]
        conditions.last[:value] = !conditions.last[:value]
        conditions.last[:seen_else] = true
      elsif first == 'endif'
        error("extraneous 'endif'") if conditions.empty?
        conditions.pop
      elsif active && !text.empty?
        positions = outside(text)
        equals = positions['=']
        colon = positions[':']
        if equals && (!colon || colon >= equals - 1)
          operator_start = equals.positive? && [':', '+', '?'].include?(text[equals - 1]) ? equals - 1 : equals
          operator = text[operator_start..equals]
          variable = trim(text[0...operator_start])
          error('empty variable name') if variable.empty?
          rhs = trim(text[(equals + 1)..])
          old = @variables[variable]
          if operator == ':='
            @variables[variable] = [':=', expand(rhs)]
          elsif operator == '+=' && old
            addition = old[0] == ':=' ? expand(rhs) : rhs
            @variables[variable] = [old[0], old[1].empty? ? addition : old[1] + ' ' + addition]
          elsif operator != '?=' || !old
            @variables[variable] = ['=', rhs]
          end
          current = nil
        elsif colon
          current = parse_rule(text, colon, number)
        else
          error('missing separator') unless trim(expand(text)).empty?
        end
      end
    end
    unless conditions.empty?
      @location = "Makefile:#{conditions.last[:number]}"
      error("missing 'endif'")
    end
    @loaded = true
    puts "Makefile loaded: lines=#{body.length} variables=#{@variables.length} targets=#{@rules.length} patterns=#{@patterns.count(&:recipe)} goal=#{@default || '(none)'}"
  rescue MakeError => e
    report(e)
    clear_makefile
  ensure
    @location = 'make'
  end

  def new_time(name)
    @clock += 1
    @files[name] = @clock
  end

  def remove_file(name, forced = false)
    if @files.key?(name)
      @files.delete(name)
      0
    elsif forced
      0
    else
      puts "rm: cannot remove '#{name}': No such file or directory"
      1
    end
  end

  def determine(target)
    explicit = @rules[target]
    return [explicit.prerequisites.dup, explicit.recipe, explicit.stem, :rule] if explicit&.recipe
    unless @phony[target]
      candidates = @patterns.each_with_index.filter_map do |rule, i|
        value = rule.recipe ? stem(rule.target, target) : nil
        [value.length, i, rule, value] if value && !value.empty?
      end.sort_by { |length, i, _, _| [length, i] }
      candidates.each do |_, _, rule, value|
        prerequisites = rule.prerequisites.map { |p| substitute(p, value) }
        if prerequisites.all? { |p| @files.key?(p) || @rules.key?(p) }
          return [(prerequisites + (explicit&.prerequisites || [])).uniq, rule.recipe, value, :rule]
        end
      end
    end
    return [explicit&.prerequisites&.dup || [], nil, explicit&.stem || '', :rule] if explicit || @phony[target]
    [[], nil, '', @files.key?(target) ? :source : :missing]
  end

  def target_time(target)
    @phony[target] ? nil : @files[target]
  end

  def simulate(command)
    parts = words(command)
    first = parts.shift
    case first
    when 'echo'
      puts parts.join(' ')
      0
    when 'touch'
      parts.each { |name| new_time(name) }
      0
    when 'rm'
      forced = parts.first == '-f'
      parts.shift if forced
      result = 0
      parts.each do |pattern|
        matches = wildcard(pattern)
        matches = [pattern] if matches.empty?
        matches.each { |name| result = [result, remove_file(name, forced)].max }
      end
      result
    when 'false'
      1
    when 'exit'
      parts.first.to_i
    else
      0
    end
  end

  def run_recipe(target, prerequisites, recipe, value, newer, options)
    @automatic = { '@' => target, '<' => prerequisites.first || '', '^' => prerequisites.join(' '), '?' => newer.join(' '), '*' => value }
    expanded = recipe.map do |number, text|
      @location = "Makefile:#{number}"
      [number, expand(text)]
    end
    expanded.each do |number, text|
      prefix = text[/\A[ @-]*/]
      command = text[prefix.length..].sub(/ +\z/, '')
      next if command.empty?
      puts command if options['n'] || (!prefix.include?('@') && !options['s'])
      next if options['n']
      code = simulate(command)
      next if code.zero?
      if prefix.include?('-') || options['i']
        puts "make: [Makefile:#{number}: #{target}] Error #{code} (ignored)"
      else
        puts "make: *** [Makefile:#{number}: #{target}] Error #{code}"
        raise BuildAbort unless options['k']
        return :failure
      end
    end
    :success
  ensure
    @automatic = nil
    @location = 'make'
  end

  def make(args)
    options = {}
    goals = []
    words(args).each do |word|
      if word.start_with?('-')
        word[1..].each_char do |char|
          unless 'nBkis'.include?(char)
            puts "make: invalid option -- '#{char}'"
            return
          end
          options[char] = true
        end
      else
        goals << word
      end
    end
    if goals.empty?
      unless @loaded
        puts 'make: *** No targets specified and no makefile found.  Stop.'
        return
      end
      unless @default
        puts 'make: *** No targets.  Stop.'
        return
      end
      goals = [@default]
    end
    saved_files = @files.dup if options['n']
    saved_clock = @clock if options['n']
    results = {}
    used = {}
    building = {}
    count = 0
    build = lambda do |target, parent|
      return results[target] if results.key?(target)
      prerequisites, recipe, value, kind = determine(target)
      used[target] = [recipe, kind]
      if kind == :missing
        results[target] = :failure
        message = "make: *** No rule to make target '#{target}'"
        message += ", needed by '#{parent}'" if parent
        puts message + '.' + (options['k'] ? '' : '  Stop.')
        raise BuildAbort unless options['k']
        return :failure
      end
      if kind == :source
        results[target] = :success
        return :success
      end
      building[target] = true
      failed = false
      kept = []
      prerequisites.each do |prerequisite|
        if building[prerequisite]
          puts "make: Circular #{target} <- #{prerequisite} dependency dropped."
        else
          kept << prerequisite
          failed = true unless build.call(prerequisite, target) == :success
        end
      end
      building.delete(target)
      if failed
        result = :dependency_failure
      else
        time = target_time(target)
        newer = kept.select { |p| options['B'] || time.nil? || target_time(p).nil? || target_time(p) > time }
        if recipe.nil? || (!options['B'] && !time.nil? && newer.empty?)
          result = :success
        else
          count += 1
          result = run_recipe(target, kept, recipe, value, newer, options)
          new_time(target) if result == :success && !@phony[target]
        end
      end
      results[target] = result
    end
    goals.each do |goal|
      before = count
      result = build.call(goal, nil)
      if result == :success && count == before
        recipe, = used[goal]
        puts(@phony[goal] || recipe.nil? ? "make: Nothing to be done for '#{goal}'." : "make: '#{goal}' is up to date.")
      elsif result == :dependency_failure
        puts "make: Target '#{goal}' not remade because of errors."
      end
    end
  rescue BuildAbort
    nil
  rescue MakeError => e
    report(e)
  ensure
    if saved_files
      @files = saved_files
      @clock = saved_clock
    end
    @location = 'make'
    @automatic = nil
  end

  def execute(line, body = nil)
    puts '$ ' + line
    command, args = line.split(' ', 2)
    args ||= ''
    case command
    when 'MAKEFILE'
      load_makefile(body)
    when 'MAKE'
      make(args)
    when 'TOUCH'
      words(args).each { |name| new_time(name) }
    when 'RM'
      words(args).each { |name| remove_file(name) }
    when 'FILES'
      puts "clock #{@clock}"
      @files.keys.sort.each { |name| puts "#{name} #{@files[name]}" }
    when 'VARS'
      return unless @loaded
      @variables.keys.sort.each do |name|
        value = trim(variable_value(name))
        puts "#{name} #{@variables[name][0]}#{value.empty? ? '' : ' ' + value}"
      end
    when 'RULES'
      return unless @loaded
      (@rules.keys.sort.map { |name| @rules[name] } + @patterns.select(&:recipe)).each do |rule|
        puts rule.target + ':' + rule.prerequisites.map { |p| ' ' + p }.join
        rule.recipe&.each { |_, text| puts '>' + text }
      end
      puts '.PHONY: ' + @phony.keys.sort.join(' ') unless @phony.empty?
    when 'EXPAND'
      puts '[' + expand(args) + ']'
    end
  rescue MakeError => e
    report(e)
  end
end

lines = STDIN.each_line.map(&:chomp)
i = 1
files = {}
until lines[i] == 'END FILES'
  name, time = lines[i].split(' ')
  files[name] = time.to_i
  i += 1
end
i += 1
workbench = MakeWorkbench.new(files)
until lines[i] == 'QUIT'
  line = lines[i]
  i += 1
  body = nil
  if line == 'MAKEFILE'
    body = []
    until lines[i] == 'END MAKEFILE'
      body << lines[i]
      i += 1
    end
    i += 1
  end
  workbench.execute(line, body)
end
