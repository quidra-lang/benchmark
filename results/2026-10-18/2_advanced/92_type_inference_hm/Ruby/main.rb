require_relative 'lexer'
require_relative 'parser'
require_relative 'inference'
require_relative 'evaluator'

def print_value(value)
  case value
  when true then 'true'
  when false then 'false'
  when Integer then value.to_s
  when String
    '"' + value.gsub(/[\\"\n\t]/) { |c| { '\\' => '\\\\', '"' => '\\"', "\n" => '\\n', "\t" => '\\t' }.fetch(c) } + '"'
  when PairValue then "(#{print_value(value.first)}, #{print_value(value.second)})"
  when Array then '[' + value.map { |element| print_value(element) }.join('; ') + ']'
  else '<fun>'
  end
end

class TypePrinter
  def initialize(quantified = nil)
    @quantified, @names = quantified, {}
  end
  def print(value)
    value = Unifier.resolve(value)
    if value.is_a?(TypeVariable)
      return @names[value] if @names.key?(value)
      index = @names.length
      prefix = @quantified && !@quantified.include?(value) ? "'_" : "'"
      return @names[value] = prefix + (97 + index % 26).chr + (index >= 26 ? (index / 26).to_s : '')
    end
    return value.kind if %w[int bool string].include?(value.kind)
    first = Unifier.resolve(value.children[0])
    left = print(first)
    first_kind = first.is_a?(TypeVariable) ? nil : first.kind
    if value.kind == 'list'
      left = "(#{left})" if %w[pair function].include?(first_kind)
      return left + ' list'
    end
    second = Unifier.resolve(value.children[1])
    right = print(second)
    second_kind = second.is_a?(TypeVariable) ? nil : second.kind
    if value.kind == 'pair'
      left = "(#{left})" if %w[pair function].include?(first_kind)
      right = "(#{right})" if %w[pair function].include?(second_kind)
      return left + ' * ' + right
    end
    left = "(#{left})" if first_kind == 'function'
    left + ' -> ' + right
  end
end

def declared_type_text(node)
  return node.value if node.kind == 'type_variable'
  return node.kind if %w[int bool string].include?(node.kind)
  first = node.children[0]
  left = declared_type_text(first)
  if node.kind == 'list'
    left = "(#{left})" if %w[pair function].include?(first.kind)
    return left + ' list'
  end
  second = node.children[1]
  right = declared_type_text(second)
  if node.kind == 'pair'
    left = "(#{left})" if %w[pair function].include?(first.kind)
    right = "(#{right})" if %w[pair function].include?(second.kind)
    return left + ' * ' + right
  end
  left = "(#{left})" if first.kind == 'function'
  left + ' -> ' + right
end

def signature_type(node, variables = {})
  return variables[node.value] ||= TypeVariable.new if node.kind == 'type_variable'
  Type.new(node.kind, *node.children.map { |child| signature_type(child, variables) })
end

def identical_types?(first, second)
  first, second = Unifier.resolve(first), Unifier.resolve(second)
  return first.equal?(second) if first.is_a?(TypeVariable) || second.is_a?(TypeVariable)
  first.kind == second.kind && first.children.zip(second.children).all? { |a, b| identical_types?(a, b) }
end

def signature_matches?(inferred, declared, assignments = {})
  inferred, declared = Unifier.resolve(inferred), Unifier.resolve(declared)
  if inferred.is_a?(TypeVariable)
    return identical_types?(assignments[inferred], declared) if assignments.key?(inferred)
    assignments[inferred] = declared
    return true
  end
  return false if declared.is_a?(TypeVariable) || inferred.kind != declared.kind
  inferred.children.zip(declared.children).all? { |a, b| signature_matches?(a, b, assignments) }
end

def check_signatures(group, signatures)
  group.bindings.zip(signatures) do |binding, signature|
    next unless signature
    declared = signature_type(signature[1])
    inferred = binding.scheme.value
    unless signature_matches?(inferred, declared)
      raise InferenceError.new('signature', binding.position, name: binding.name, inferred: inferred, declared: declared)
    end
    binding.scheme = Scheme.new(declared, Unifier.free_variables(declared))
  end
end

def edit_distance(first, second)
  previous = (0..second.length).to_a
  first.each_char.with_index(1) do |left, row|
    current = [row]
    second.each_char.with_index(1) do |right, column|
      current << [current[-1] + 1, previous[column] + 1, previous[column - 1] + (left == right ? 0 : 1)].min
    end
    previous = current
  end
  previous[-1]
end

def type_error_message(error)
  details = error.details
  printer = TypePrinter.new
  name = details[:name]
  case error.kind
  when 'unbound'
    candidates = details[:candidates].filter_map do |candidate|
      distance = edit_distance(name, candidate)
      [distance, candidate] if distance <= 2 && distance < name.length
    end
    suggestion = candidates.min
    "unbound variable '#{name}'" + (suggestion ? " (did you mean '#{suggestion[1]}'?)" : '')
  when 'not_function' then 'expected a function but found ' + printer.print(details[:found])
  when 'check'
    message = 'expected ' + printer.print(details[:expected]) + ' but found ' + printer.print(details[:found])
    failure = details[:failure]
    if failure.infinite
      variable, type = failure.expected, failure.found
      variable, type = type, variable unless variable.is_a?(TypeVariable)
      message += ' (infinite type ' + printer.print(variable) + ' = ' + printer.print(type) + ')'
    elsif failure.nested
      message += ' (' + printer.print(failure.expected) + ' vs ' + printer.print(failure.found) + ')'
    end
    message
  when 'duplicate_pattern' then "variable '#{name}' is bound twice in this pattern"
  when 'duplicate_let' then "variable '#{name}' is bound twice in this let"
  when 'recursive_function' then "'#{name}' in let rec must be a function"
  when 'signature'
    "'#{name}' has type " + printer.print(details[:inferred]) + ' but its signature is ' + printer.print(details[:declared])
  end
end

def built_in_environments
  first, second = TypeVariable.new, TypeVariable.new
  fst = Scheme.new(Type.new('function', Type.new('pair', first, second), first), [first, second])
  first, second = TypeVariable.new, TypeVariable.new
  snd = Scheme.new(Type.new('function', Type.new('pair', first, second), second), [first, second])
  result = TypeVariable.new
  types = {
    'fst' => fst, 'snd' => snd,
    'not' => Scheme.new(Type.new('function', Unifier::BOOL, Unifier::BOOL)),
    'string_of_int' => Scheme.new(Type.new('function', Unifier::INT, Unifier::STRING)),
    'failwith' => Scheme.new(Type.new('function', Unifier::STRING, result), [result])
  }
  values = {
    'fst' => Builtin.new(->(v, _) { v.first }), 'snd' => Builtin.new(->(v, _) { v.second }),
    'not' => Builtin.new(->(v, _) { !v }), 'string_of_int' => Builtin.new(->(v, _) { v.to_s }),
    'failwith' => Builtin.new(->(v, p) { raise RuntimeFailure.new(p, 'failure ' + print_value(v)) })
  }
  [types, values]
end

def leading_parameters(node)
  parameters = []
  while node.kind == 'fun'
    parameters << node.value.spelling
    node = node.children[0]
  end
  [parameters, node]
end
def format_binding(binding)
  parameters, body = leading_parameters(binding.expression)
  ([binding.name] + parameters + ['=', format_expression(body)]).join(' ')
end
def format_group(group)
  (group.rec_position ? 'let rec ' : 'let ') + group.bindings.map { |binding| format_binding(binding) }.join(' and ')
end
def ends_with_match?(node)
  case node.kind
  when 'match' then true
  when 'let', 'fun' then ends_with_match?(node.children[0])
  when 'if' then ends_with_match?(node.children[2])
  else false
  end
end
def format_pattern(node)
  return node.value if %w[wildcard name].include?(node.kind)
  return print_value(node.value) if %w[integer boolean string].include?(node.kind)
  return '[' + node.children.map { |child| format_pattern(child) }.join('; ') + ']' if node.kind == 'list'
  first, second = node.children
  left, right = format_pattern(first), format_pattern(second)
  return "(#{left}, #{right})" if node.kind == 'pair'
  left = "(#{left})" if first.kind == 'cons'
  left + ' :: ' + right
end
def format_expression(node, minimum = 0)
  children = node.children
  strength = 9
  text = case node.kind
         when 'integer', 'boolean', 'string' then print_value(node.value)
         when 'name' then node.value
         when 'fun'
           strength = 0
           parameters, body = leading_parameters(node)
           'fun ' + parameters.join(' ') + ' -> ' + format_expression(body)
         when 'apply'
           strength = 8
           format_expression(children[0], 8) + ' ' + format_expression(children[1], 9)
         when 'binary'
           operator = node.value.spelling
           strength, right = Parser::OPERATORS.fetch(operator)
           format_expression(children[0], strength + (right ? 1 : 0)) + " #{operator} " +
             format_expression(children[1], strength + (right ? 0 : 1))
         when 'negate'
           strength = 7
           '-' + format_expression(children[0], 7)
         when 'if'
           strength = 0
           'if ' + format_expression(children[0]) + ' then ' + format_expression(children[1]) + ' else ' + format_expression(children[2])
         when 'pair' then '(' + children.map { |child| format_expression(child) }.join(', ') + ')'
         when 'list' then '[' + children.map { |child| format_expression(child) }.join('; ') + ']'
         when 'let'
           strength = 0
           format_group(node.value) + ' in ' + format_expression(children[0])
         when 'match'
           strength = 0
           arms = node.value.each_with_index.map do |(pattern, arm), index|
             body = format_expression(arm)
             body = "(#{body})" if index < node.value.length - 1 && ends_with_match?(arm)
             format_pattern(pattern) + ' -> ' + body
           end
           'match ' + format_expression(children[0]) + ' with ' + arms.join(' | ')
         end
  strength < minimum ? "(#{text})" : text
end
def format_item(item)
  case item.kind
  when 'signature' then "val #{item.value[0].spelling} : #{declared_type_text(item.value[1])};;"
  when 'declaration' then format_group(item.value) + ';;'
  else format_expression(item.value) + ';;'
  end
end

# Pattern-matrix usefulness decides coverage of nested products and unbounded lists
# symbolically, without enumerating values or imposing a depth bound.
def coverage_type(type)
  type = Unifier.resolve(type)
  return ['opaque'] if type.is_a?(TypeVariable) || type.kind == 'function'
  [type.kind, *type.children.map { |child| coverage_type(child) }]
end
def coverage_pattern(pattern)
  return nil if %w[wildcard name].include?(pattern.kind)
  return [[pattern.kind, pattern.value], []] if %w[integer boolean string].include?(pattern.kind)
  if pattern.kind == 'list'
    pattern.children.reverse.reduce([['nil'], []]) { |tail, child| [['cons'], [coverage_pattern(child), tail]] }
  else
    [[pattern.kind == 'pair' ? 'pair' : 'cons'], pattern.children.map { |child| coverage_pattern(child) }]
  end
end
def constructors(type)
  case type[0]
  when 'bool' then [['boolean', false], ['boolean', true]]
  when 'list' then [['nil'], ['cons']]
  when 'pair' then [['pair']]
  else []
  end
end
def constructor_arguments(constructor, type)
  return type.drop(1) if constructor == ['pair']
  return [type[1], type] if constructor == ['cons']
  []
end
def specialize(matrix, constructor, arity)
  matrix.filter_map do |row|
    if row[0].nil?
      Array.new(arity) + row.drop(1)
    elsif row[0][0] == constructor
      row[0][1] + row.drop(1)
    end
  end
end
def useful_pattern?(matrix, query, types, cache)
  key = [matrix, query, types]
  return cache[key] if cache.key?(key)
  return matrix.empty? if query.empty?
  return true if matrix.empty?
  head = query[0]
  result = if head
             constructor, arguments = head
             selected = specialize(matrix, constructor, arguments.length)
             useful_pattern?(selected, arguments + query.drop(1), constructor_arguments(constructor, types[0]) + types.drop(1), cache)
           else
             possible = constructors(types[0])
             present = matrix.filter_map { |row| row[0]&.first }
             if !possible.empty? && possible.all? { |constructor| present.include?(constructor) }
               possible.any? do |constructor|
                 arguments = constructor_arguments(constructor, types[0])
                 useful_pattern?(specialize(matrix, constructor, arguments.length), Array.new(arguments.length) + query.drop(1), arguments + types.drop(1), cache)
               end
             else
               useful_pattern?(matrix.select { |row| row[0].nil? }.map { |row| row.drop(1) }, query.drop(1), types.drop(1), cache)
             end
           end
  cache[key] = result
end

SymbolInfo = Struct.new(:name, :position, :top_level, :used)
class StaticChecks
  def initialize
    @symbols, @groups, @warnings = [], [], []
    @references = {}.compare_by_identity
  end
  def symbol(name, position, top_level = false)
    result = SymbolInfo.new(name, position, top_level, false)
    @symbols << result
    result
  end
  def bind_pattern(pattern, environment)
    environment[pattern.value] = symbol(pattern.value, pattern.position) if pattern.kind == 'name'
    pattern.children.each { |child| bind_pattern(child, environment) }
  end
  def group(group, environment, top_level = false)
    symbols = group.bindings.map { |binding| symbol(binding.name, binding.position, top_level) }
    @groups << [group, symbols]
    inner = environment.merge(symbols.to_h { |entry| [entry.name, entry] })
    group.bindings.each { |binding| expression(binding.expression, group.rec_position ? inner : environment) }
    inner
  end
  def match_warnings(node)
    matrix, cache = [], {}
    types = [coverage_type(node.children[0].inferred)]
    node.value.each_with_index do |(pattern, _), index|
      query = [coverage_pattern(pattern)]
      @warnings << [pattern.position, 2, 'this match case is unused'] if index.positive? && !useful_pattern?(matrix, query, types, cache)
      matrix = matrix + [query]
    end
    @warnings << [node.position, 1, 'this match is not exhaustive'] if useful_pattern?(matrix, [nil], types, cache)
  end
  def expression(node, environment)
    case node.kind
    when 'name'
      entry = environment[node.value]
      @references[node] = entry
      entry.used = true if entry
    when 'fun'
      inner = environment.dup
      token = node.value
      inner[token.spelling] = symbol(token.spelling, token.position) unless token.spelling == '_'
      expression(node.children[0], inner)
    when 'let'
      expression(node.children[0], group(node.value, environment))
    when 'match'
      expression(node.children[0], environment)
      match_warnings(node)
      node.value.each do |pattern, arm|
        inner = environment.dup
        bind_pattern(pattern, inner)
        expression(arm, inner)
      end
    else node.children.each { |child| expression(child, environment) }
    end
  end
  def nodes(node, &block)
    block.call(node)
    node.value.bindings.each { |binding| nodes(binding.expression, &block) } if node.kind == 'let'
    node.children.each { |child| nodes(child, &block) }
    node.value.each { |_, arm| nodes(arm, &block) } if node.kind == 'match'
  end
  def target?(node, targets) = targets.any? { |entry| entry.equal?(@references[node]) }
  def classification(node, targets)
    _, body = leading_parameters(node)
    calls = []
    visit = lambda do |current, tail|
      children = current.children
      case current.kind
      when 'name' then calls << false if target?(current, targets)
      when 'apply'
        arguments = []
        function = current
        while function.kind == 'apply'
          arguments << function.children[1]
          function = function.children[0]
        end
        if function.kind == 'name' && target?(function, targets)
          calls << tail
        else
          visit.call(function, false)
        end
        arguments.reverse_each { |argument| visit.call(argument, false) }
      when 'if'
        visit.call(children[0], false)
        visit.call(children[1], tail)
        visit.call(children[2], tail)
      when 'match'
        visit.call(children[0], false)
        current.value.each { |_, arm| visit.call(arm, tail) }
      when 'let'
        current.value.bindings.each { |binding| visit.call(binding.expression, false) }
        visit.call(children[0], tail)
      when 'binary'
        visit.call(children[0], false)
        visit.call(children[1], %w[&& ||].include?(current.value.spelling) && tail)
      else children.each { |child| visit.call(child, false) }
      end
    end
    visit.call(body, true)
    calls.empty? ? '' : (calls.all? ? 'tail recursive' : 'recursive')
  end
  def item(item, names)
    environment = names.to_h { |name| [name, nil] }
    item.kind == 'declaration' ? group(item.value, environment, true) : expression(item.value, environment)
    @groups.each do |bindings, targets|
      next unless bindings.rec_position
      referenced = false
      bindings.bindings.each { |binding| nodes(binding.expression) { |node| referenced = true if target?(node, targets) } }
      @warnings << [bindings.rec_position, 3, 'unused rec flag'] unless referenced
      bindings.bindings.each { |binding| binding.classification = classification(binding.expression, targets) }
    end
    @symbols.each do |entry|
      if !entry.top_level && !entry.used && !entry.name.start_with?('_')
        @warnings << [entry.position, 4, "unused variable '#{entry.name}'"]
      end
    end
    @warnings.sort_by { |position, priority, _| [position[1], position[2], priority] }
  end
end

class Reports
  attr_accessor :current_file
  attr_reader :statistics
  def initialize(sources)
    @sources = sources.transform_values(&:lines).transform_values { |lines| lines.map(&:chomp) }
    @lines = []
    @statistics = sources.to_h { |filename, _| [filename, %w[items bindings syntax type runtime warnings calls].to_h { |name| [name, 0] }] }
  end
  def report(kind, position, message)
    filename, line, column = position
    @statistics[@current_file][kind == 'warning' ? 'warnings' : kind.split.first] += 1
    @lines << "#{filename}:#{line}:#{column}: #{kind}: #{message}"
    if line <= @sources[filename].length
      @lines << '    ' + @sources[filename][line - 1]
      @lines << ' ' * (column + 3) + '^'
    end
  end
  def finish
    @lines << '== summary =='
    @statistics.each { |file, counts| @lines << file + ': ' + counts.map { |name, count| "#{name}=#{count}" }.join(' ') }
    @lines
  end
end

class MiniML
  def initialize(sources)
    @sources = sources
    @type_environment, @value_environment = built_in_environments
    @reports = Reports.new(sources)
    @types, @values, @formatted = [], [], []
  end
  def unused_signature(signature)
    token = signature[0]
    @reports.report('warning', token.position, "signature for '#{token.spelling}' is never used")
  end
  def classification_suffix(binding) = binding.classification.empty? ? '' : " (#{binding.classification})"
  def write_types(item, inferred, local_bindings)
    if item.kind == 'declaration'
      item.value.bindings.each { |binding| @types << "#{binding.name} : #{TypePrinter.new.print(binding.scheme.value)}#{classification_suffix(binding)}" }
    else
      @types << '- : ' + TypePrinter.new.print(inferred)
    end
    local_bindings.sort_by { |binding| binding.position.drop(1) }.each do |binding|
      _, line, column = binding.position
      text = TypePrinter.new(binding.scheme.quantified).print(binding.scheme.value)
      @types << "  #{binding.name} (#{line}:#{column}) : #{text}#{classification_suffix(binding)}"
    end
  end
  def process_item(item, pending, evaluator, counts)
    @formatted << format_item(item)
    if item.kind == 'signature'
      name = item.value[0].spelling
      unused_signature(pending[name]) if pending.key?(name)
      pending[name] = item.value
      return
    end
    signatures = item.kind == 'declaration' ? item.value.bindings.map { |binding| pending.delete(binding.name) } : []
    inferencer = Inferencer.new
    inferred = nil
    begin
      if item.kind == 'declaration'
        inferencer.group(item.value, @type_environment)
        check_signatures(item.value, signatures)
      else
        inferred = inferencer.expression(item.value, @type_environment)
      end
    rescue InferenceError => error
      @reports.report('type error', error.position, type_error_message(error))
      return
    end
    warnings = StaticChecks.new.item(item, @type_environment.keys)
    write_types(item, inferred, inferencer.local_bindings)
    warnings.each { |position, _, message| @reports.report('warning', position, message) }
    begin
      if item.kind == 'declaration'
        environment = evaluator.group(item.value, @value_environment)
      else
        value = evaluator.expression(item.value, @value_environment)
      end
    rescue RuntimeFailure => error
      @reports.report('runtime error', error.position, error.message)
      return
    end
    if item.kind == 'declaration'
      item.value.bindings.each do |binding|
        @type_environment[binding.name] = binding.scheme
        @values << "#{binding.name} = #{print_value(environment[binding.name])}"
      end
      @value_environment = environment
      counts['bindings'] += item.value.bindings.length
    else
      @values << '- = ' + print_value(value)
    end
  end
  def process_file(filename)
    @reports.current_file = filename
    counts = @reports.statistics[filename]
    @types << "== #{filename} =="
    @values << "== #{filename} =="
    @formatted << "(* #{filename} *)"
    pending = {}
    evaluator = Evaluator.new
    parser = Parser.new(Lexer.tokenize(@sources[filename], filename))
    until parser.peek.kind == 'EOF'
      counts['items'] += 1
      begin
        item = parser.item
      rescue SyntaxFailure => error
        token = error.token
        message = case token.kind
                  when 'invalid' then token.value
                  when 'EOF' then 'unexpected end of file'
                  else "unexpected '#{token.spelling}'"
                  end
        @reports.report('syntax error', token.position, message)
        parser.recover
        next
      end
      process_item(item, pending, evaluator, counts)
    end
    pending.values.sort_by { |signature| signature[0].position.drop(1) }.each { |signature| unused_signature(signature) }
    counts['calls'] = evaluator.calls
  end
  def run
    @sources.each_key { |filename| process_file(filename) }
    { 'types.txt' => @types, 'values.txt' => @values, 'errors.txt' => @reports.finish, 'formatted.ml' => @formatted }
  end
end

if $PROGRAM_NAME == __FILE__
  sources = %w[prelude.ml program.ml].to_h { |file| [file, File.read(File.join('input', file), encoding: 'ASCII')] }
  MiniML.new(sources).run.each { |filename, lines| File.write(File.join('output', filename), lines.join("\n") + "\n") }
end
