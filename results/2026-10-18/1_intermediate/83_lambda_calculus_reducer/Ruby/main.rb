require 'set'

class LambdaError < StandardError
end

class Untypable < StandardError
end

class Term
  attr_reader :kind, :name, :left, :right, :free, :size, :depth

  def initialize(kind, name = nil, left = nil, right = nil)
    @kind, @name, @left, @right = kind, name, left, right
    case kind
    when :var
      @free = Set[name]
    when :abs
      @free = left.free - Set[name]
    when :app
      @free = left.free | right.free
    else
      @free = Set.new
    end
    @size = 1 + (left&.size || 0) + (right&.size || 0)
    @depth = 1 + [left&.depth || 0, right&.depth || 0].max
  end
end

def variable(name) = Term.new(:var, name)
def abstraction(name, body) = Term.new(:abs, name, body)
def application(left, right) = Term.new(:app, nil, left, right)

def printed(term, end_position = true, debruijn = false)
  case term.kind
  when :var, :macro, :constant
    term.name
  when :number
    "##{term.name}"
  when :index
    term.name.to_s
  when :abs
    names = []
    body = term
    while body.kind == :abs
      names << body.name
      body = body.left
    end
    text = if debruijn
             '\\' * names.length + printed(body, true, true)
           else
             '\\' + names.join(' ') + '. ' + printed(body)
           end
    end_position ? text : "(#{text})"
  when :app
    left = term.left.kind == :abs ? "(#{printed(term.left, true, debruijn)})" : printed(term.left, false, debruijn)
    right = term.right.kind == :app ? "(#{printed(term.right, true, debruijn)})" : printed(term.right, end_position, debruijn)
    left + ' ' + right
  end
end

class Parser
  def initialize(argument, offset, end_column)
    @tokens = []
    i = 0
    while i < argument.length
      c = argument[i]
      if c == ' '
        i += 1
        next
      end
      start = i
      if '\\.()=;'.include?(c)
        kind = c
        i += 1
      elsif c.match?(/[a-z]/)
        kind = :var
        i += 1
        i += 1 while i < argument.length && argument[i].match?(/[a-z0-9]/)
      elsif c.match?(/[A-Z]/)
        kind = :macro
        i += 1
        i += 1 while i < argument.length && argument[i].match?(/[A-Z0-9_]/)
      elsif c == '#' && i + 1 < argument.length && argument[i + 1].match?(/[0-9]/)
        kind = :number
        i += 2
        i += 1 while i < argument.length && argument[i].match?(/[0-9]/)
      else
        raise LambdaError, "column #{offset + i}: unexpected character '#{c}'"
      end
      @tokens << [kind, argument[start...i], offset + start]
    end
    @tokens << [:end, '', end_column]
    @position = 0
  end

  def peek = @tokens[@position]
  def advance
    result = peek
    @position += 1
    result
  end

  def expect(kind)
    notation = { var: 'variable', macro: 'macro name' }[kind] || "'#{kind}'"
    raise LambdaError, "column #{peek[2]}: expected #{notation}" unless peek[0] == kind
    advance[1]
  end

  def term
    elements = []
    while [:var, :macro, :number, '('].include?(peek[0])
      kind, text = advance
      if kind == '('
        elements << term
        expect(')')
      else
        elements << Term.new(kind, kind == :number ? text[1..].to_i : text)
      end
    end
    if peek[0] == '\\'
      advance
      names = [expect(:var)]
      names << advance[1] while peek[0] == :var
      expect('.')
      body = term
      names.reverse_each { |name| body = abstraction(name, body) }
      elements << body
    end
    raise LambdaError, "column #{peek[2]}: expected term" if elements.empty?
    elements.reduce { |left, right| application(left, right) }
  end

  def finish
    raise LambdaError, "column #{peek[2]}: unexpected '#{peek[1]}'" unless peek[0] == :end
  end
end

def references(term)
  case term.kind
  when :macro then [term.name]
  when :abs then references(term.left)
  when :app then references(term.left) + references(term.right)
  else []
  end
end

def name_at(index)
  (97 + index % 26).chr + (index >= 26 ? (index / 26).to_s : '')
end

def canonical(term)
  free = term.free
  counter = 0
  visit = lambda do |node, bindings|
    case node.kind
    when :var
      variable(bindings[node.name] || node.name)
    when :abs
      counter += 1 while free.include?(name_at(counter))
      name = name_at(counter)
      counter += 1
      abstraction(name, visit.call(node.left, bindings.merge(node.name => name)))
    when :app
      application(visit.call(node.left, bindings), visit.call(node.right, bindings))
    else
      node
    end
  end
  visit.call(term, {})
end

def to_debruijn(term, bindings = [])
  case term.kind
  when :var
    index = bindings.index(term.name)
    index ? Term.new(:index, index) : term
  when :abs
    abstraction(nil, to_debruijn(term.left, [term.name] + bindings))
  when :app
    application(to_debruijn(term.left, bindings), to_debruijn(term.right, bindings))
  end
end

def from_debruijn(term)
  counter = 0
  free = term.free
  visit = lambda do |node, bindings|
    case node.kind
    when :index
      variable(bindings[node.name])
    when :var
      node
    when :abs
      counter += 1 while free.include?(name_at(counter))
      name = name_at(counter)
      counter += 1
      abstraction(name, visit.call(node.left, [name] + bindings))
    when :app
      application(visit.call(node.left, bindings), visit.call(node.right, bindings))
    end
  end
  visit.call(term, [])
end

def substitute(term, name, replacement)
  case term.kind
  when :var
    term.name == name ? replacement : term
  when :app
    application(substitute(term.left, name, replacement), substitute(term.right, name, replacement))
  when :abs
    bound = term.name
    body = term.left
    return term if bound == name || !body.free.include?(name)
    if replacement.free.include?(bound)
      stem = bound.sub(/[0-9]+\z/, '')
      suffix = 1
      suffix += 1 while replacement.free.include?(stem + suffix.to_s) || body.free.include?(stem + suffix.to_s)
      fresh = stem + suffix.to_s
      body = substitute(body, bound, variable(fresh))
      bound = fresh
    end
    abstraction(bound, substitute(body, name, replacement))
  end
end

def eta_target(term)
  body = term.left
  if body.kind == :app && body.right.kind == :var && body.right.name == term.name && !body.left.free.include?(term.name)
    body.left
  end
end

def one_step(term, strategy, eta)
  if term.kind == :app
    left, right = term.left, term.right
    if %w[NORMAL CBN].include?(strategy) && left.kind == :abs
      return [substitute(left.left, left.name, right), 'beta']
    end
    step = one_step(left, strategy, eta)
    return [application(step[0], right), step[1]] if step
    unless strategy == 'CBN'
      step = one_step(right, strategy, eta)
      return [application(left, step[0]), step[1]] if step
    end
    if %w[APPLICATIVE CBV].include?(strategy) && left.kind == :abs && (strategy != 'CBV' || [:var, :abs].include?(right.kind))
      return [substitute(left.left, left.name, right), 'beta']
    end
  elsif term.kind == :abs && %w[NORMAL APPLICATIVE].include?(strategy)
    target = eta ? eta_target(term) : nil
    return [target, 'eta'] if target && strategy == 'NORMAL'
    step = one_step(term.left, strategy, eta)
    return [abstraction(term.name, step[0]), step[1]] if step
    return [target, 'eta'] if target
  end
  nil
end

def ski_abstract(name, term)
  return application(Term.new(:constant, 'K'), term) unless term.free.include?(name)
  return Term.new(:constant, 'I') if term.kind == :var && term.name == name
  if term.right.kind == :var && term.right.name == name && !term.left.free.include?(name)
    return term.left
  end
  application(application(Term.new(:constant, 'S'), ski_abstract(name, term.left)), ski_abstract(name, term.right))
end

def to_ski(term)
  case term.kind
  when :var then term
  when :abs then ski_abstract(term.name, to_ski(term.left))
  when :app then application(to_ski(term.left), to_ski(term.right))
  end
end

def ski_step(term)
  head = term
  args = []
  while head.kind == :app
    args.unshift(head.right)
    head = head.left
  end
  arity = head.kind == :constant ? { 'I' => 1, 'K' => 2, 'S' => 3 }[head.name] : nil
  if arity && args.length >= arity
    result = head.name == 'S' ? application(application(args[0], args[2]), application(args[1], args[2])) : args[0]
    args.drop(arity).each { |arg| result = application(result, arg) }
    return [result, head.name]
  end
  args.each_with_index do |arg, i|
    step = ski_step(arg)
    next unless step
    changed = args.dup
    changed[i] = step[0]
    return [changed.reduce(head) { |left, right| application(left, right) }, step[1]]
  end
  nil
end

class TypeInference
  def initialize
    @next = 0
    @links = {}
    @free = {}
  end

  def fresh
    result = [:variable, @next]
    @next += 1
    result
  end

  def prune(type)
    path = []
    while type[0] == :variable && @links.key?(type[1])
      path << type[1]
      type = @links[type[1]]
    end
    path.each { |id| @links[id] = type }
    type
  end

  def occurs(id, type)
    type = prune(type)
    type[0] == :variable ? type[1] == id : occurs(id, type[1]) || occurs(id, type[2])
  end

  def unify(left, right)
    left, right = prune(left), prune(right)
    return if left == right
    if left[0] == :variable
      raise Untypable if occurs(left[1], right)
      @links[left[1]] = right
    elsif right[0] == :variable
      unify(right, left)
    else
      unify(left[1], right[1])
      unify(left[2], right[2])
    end
  end

  def infer(term, environment = {})
    case term.kind
    when :var
      environment[term.name] || (@free[term.name] ||= fresh)
    when :abs
      parameter = fresh
      [:arrow, parameter, infer(term.left, environment.merge(term.name => parameter))]
    when :app
      function = infer(term.left, environment)
      argument = infer(term.right, environment)
      result = fresh
      unify(function, [:arrow, argument, result])
      result
    end
  end

  def show(term)
    type = infer(term)
    names = {}
    visit = lambda do |node|
      node = prune(node)
      if node[0] == :variable
        names[node[1]] ||= name_at(names.length)
      else
        left = visit.call(node[1])
        left = "(#{left})" if prune(node[1])[0] == :arrow
        left + ' -> ' + visit.call(node[2])
      end
    end
    visit.call(type)
  rescue Untypable
    'not typable'
  end
end

def church_value(term)
  if term.kind == :abs && term.left.kind == :abs
    f, x = term.name, term.left.name
    body = term.left.left
    count = 0
    while body.kind == :app && body.left.kind == :var && body.left.name == f
      count += 1
      body = body.right
    end
    return count.to_s if body.kind == :var && body.name == x
    return 'true' if term.left.left.kind == :var && term.left.left.name == f
  end
  if term.kind == :abs
    body = term.left
    if body.kind == :app && body.left.kind == :app && body.left.left.kind == :var && body.left.left.name == term.name
      p, q = body.left.right, body.right
      return "(#{church_value(p)}, #{church_value(q)})" unless p.free.include?(term.name) || q.free.include?(term.name)
    end
  end
  printed(canonical(term))
end

def materialize(code, environment, level = 0)
  while code.kind == :index && code.name >= level
    code, environment = environment[code.name - level]
    level = 0
  end
  case code.kind
  when :app
    application(materialize(code.left, environment, level), materialize(code.right, environment, level))
  when :abs
    abstraction(nil, materialize(code.left, environment, level + 1))
  else
    code
  end
end

class Workbench
  RESERVED = %w[S K I NORMAL APPLICATIVE CBN CBV].freeze
  COMMANDS = %w[let unlet macros steps eta limit expand subst reduce equal alpha debruijn fv size depth type church ski skireduce kam].freeze

  def initialize
    @macros = {
      'S' => abstraction('x', abstraction('y', abstraction('z', application(application(variable('x'), variable('z')), application(variable('y'), variable('z')))))),
      'K' => abstraction('x', abstraction('y', variable('x'))),
      'I' => abstraction('x', variable('x'))
    }
    @steps = false
    @eta = false
    @limit = 10_000
  end

  def depends?(name, target, visited = {})
    return false if visited.key?(name)
    visited[name] = true
    return false unless @macros.key?(name) && !%w[S K I].include?(name)
    references(@macros[name]).any? { |ref| ref == target || depends?(ref, target, visited) }
  end

  def expand(term)
    case term.kind
    when :macro
      raise LambdaError, "unbound macro #{term.name}" unless @macros.key?(term.name)
      expand(@macros[term.name])
    when :number
      body = variable('x')
      term.name.times { body = application(variable('f'), body) }
      abstraction('f', abstraction('x', body))
    when :abs
      abstraction(term.name, expand(term.left))
    when :app
      application(expand(term.left), expand(term.right))
    else
      term
    end
  end

  def reduce(term, strategy = 'NORMAL', eta = @eta, display = false, ski = false)
    count = 0
    loop do
      step = ski ? ski_step(term) : one_step(term, strategy, eta)
      return [term, count] unless step
      return nil if count == @limit
      term = step[0]
      count += 1
      puts "step #{count} (#{step[1]}): #{printed(term)}" if display && @steps
    end
  end

  def kam(term)
    code = to_debruijn(term)
    environment = []
    stack = []
    count = 0
    loop do
      kind = case code.kind
             when :app then 'push'
             when :abs then 'grab' unless stack.empty?
             when :index then 'access'
             end
      break unless kind
      if count == @limit
        puts "no result within #{@limit} transitions"
        return
      end
      case kind
      when 'push'
        stack << [code.right, environment]
        code = code.left
      when 'grab'
        environment = [stack.pop] + environment
        code = code.left
      when 'access'
        code, environment = environment[code.name]
      end
      count += 1
      puts "step #{count} (#{kind}): #{printed(code, true, true)} [env #{environment.length}, stack #{stack.length}]" if @steps
    end
    result = materialize(code, environment)
    stack.reverse_each { |closure| result = application(result, materialize(*closure)) }
    puts "result: #{printed(from_debruijn(result))} (transitions: #{count})"
  end

  def command(line)
    separator = line.index(' ')
    command = separator ? line[0...separator] : line
    argument = separator ? line[(separator + 1)..] : ''
    raise LambdaError, "unknown command #{command}" unless COMMANDS.include?(command)
    if %w[steps eta limit macros unlet].include?(command)
      words = argument.split(' ')
      case command
      when 'steps', 'eta'
        raise LambdaError, 'bad argument' unless words.length == 1 && %w[on off].include?(words[0])
        command == 'steps' ? @steps = words[0] == 'on' : @eta = words[0] == 'on'
      when 'limit'
        raise LambdaError, 'bad argument' unless words.length == 1 && words[0].match?(/\A[0-9]{1,5}\z/) && (1..10_000).cover?(words[0].to_i)
        @limit = words[0].to_i
      when 'macros'
        raise LambdaError, 'bad argument' unless words.empty?
        names = @macros.keys.reject { |name| %w[S K I].include?(name) }.sort
        puts '(none)' if names.empty?
        names.each { |name| puts "#{name} = #{printed(@macros[name])}" }
      when 'unlet'
        raise LambdaError, 'bad argument' unless words.length == 1 && words[0].match?(/\A[A-Z][A-Z0-9_]*\z/)
        name = words[0]
        raise LambdaError, "reserved name #{name}" if RESERVED.include?(name)
        raise LambdaError, "unbound macro #{name}" unless @macros.key?(name)
        user = @macros.keys.sort.find { |key| !%w[S K I].include?(key) && references(@macros[key]).include?(name) }
        raise LambdaError, "#{name} is used by #{user}" if user
        @macros.delete(name)
        puts "removed #{name}"
      end
      return
    end
    parser = Parser.new(argument, command.length + 2, line.length + 1)
    strategy = 'NORMAL'
    name = nil
    terms = []
    case command
    when 'let', 'subst'
      name = parser.expect(command == 'let' ? :macro : :var)
      parser.expect('=')
      terms << parser.term
      if command == 'subst'
        parser.expect(';')
        terms << parser.term
      end
    when 'equal', 'alpha'
      terms << parser.term
      parser.expect(';')
      terms << parser.term
    when 'reduce'
      strategy = parser.advance[1] if parser.peek[0] == :macro && %w[NORMAL APPLICATIVE CBN CBV].include?(parser.peek[1])
      terms << parser.term
    else
      terms << parser.term
    end
    parser.finish
    if command == 'let'
      raise LambdaError, "reserved name #{name}" if RESERVED.include?(name)
      references(terms[0]).each do |ref|
        raise LambdaError, "recursive definition of #{name}" if ref == name || depends?(ref, name)
        raise LambdaError, "unbound macro #{ref}" unless @macros.key?(ref)
      end
      unless terms[0].free.empty?
        raise LambdaError, "free variable #{terms[0].free.min} in definition of #{name}"
      end
      puts "#{@macros.key?(name) ? 'redefined' : 'defined'} #{name}"
      @macros[name] = terms[0]
      return
    end
    terms = terms.map { |term| expand(term) }
    term = terms[0]
    case command
    when 'expand' then puts printed(term)
    when 'subst' then puts printed(substitute(terms[1], name, term))
    when 'alpha' then puts printed(to_debruijn(term), true, true) == printed(to_debruijn(terms[1]), true, true) ? 'yes' : 'no'
    when 'debruijn' then puts printed(to_debruijn(term), true, true)
    when 'fv' then puts term.free.empty? ? '(none)' : term.free.to_a.sort.join(' ')
    when 'size' then puts term.size
    when 'depth' then puts term.depth
    when 'type' then puts TypeInference.new.show(term)
    when 'ski' then puts printed(to_ski(term))
    when 'kam' then kam(term)
    when 'equal'
      left = reduce(term)
      right = reduce(terms[1])
      if !left || !right
        puts 'unknown'
      elsif printed(canonical(left[0])) == printed(canonical(right[0]))
        puts 'yes'
      else
        puts 'no'
      end
    when 'church', 'reduce', 'skireduce'
      result = if command == 'church'
                 reduce(term, 'NORMAL', false)
               elsif command == 'skireduce'
                 reduce(to_ski(term), 'NORMAL', false, true, true)
               else
                 reduce(term, strategy, @eta, true)
               end
      if result.nil?
        puts "no normal form within #{@limit} steps"
      elsif command == 'church'
        puts church_value(canonical(result[0]))
      else
        text = command == 'skireduce' ? printed(result[0]) : printed(canonical(result[0]))
        puts "result: #{text} (steps: #{result[1]})"
      end
    end
  end

  def run
    STDIN.each_line do |input|
      line = input.delete_suffix("\n")
      break if line == 'quit'
      next if line.empty? || line.start_with?('--')
      begin
        command(line)
      rescue LambdaError => error
        puts "error: #{error.message}"
      end
    end
  end
end

Workbench.new.run
