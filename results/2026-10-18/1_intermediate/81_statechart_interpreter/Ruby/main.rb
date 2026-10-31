class EvaluationError < StandardError; end

class Expression
  attr_reader :references

  def initialize(text)
    @tokens = text.scan(/\|\||&&|==|!=|<=|>=|[()+*\/%!<>-]|[0-9]+|[A-Za-z_][A-Za-z0-9_]*/)
    @index = 0
    @references = []
    @tree = parse(0)
  end

  PRECEDENCE = { '||' => 0, '&&' => 1, '==' => 2, '!=' => 2, '<' => 2, '<=' => 2,
                 '>' => 2, '>=' => 2, '+' => 3, '-' => 3, '*' => 4, '/' => 4, '%' => 4 }.freeze

  def parse(level)
    return unary if level == 5
    left = parse(level + 1)
    while PRECEDENCE[@tokens[@index]] == level
      operator = @tokens[@index]
      @index += 1
      left = [operator, left, parse(level + 1)]
    end
    left
  end

  def unary
    token = @tokens[@index]
    @index += 1
    if %w[! -].include?(token)
      [token == '!' ? :not : :negative, unary]
    elsif token == '('
      result = parse(0)
      @index += 1
      result
    elsif token == 'in'
      @index += 1
      state = @tokens[@index]
      @index += 2
      @references << [:state, state]
      [:in, state]
    elsif /\A[0-9]+\z/.match?(token)
      [:number, token.to_i]
    else
      @references << [:variable, token] unless token == '_data'
      [:variable, token]
    end
  end

  def evaluate(variables, data, configuration, states, node = @tree)
    operator, left, right = node
    return left if operator == :number
    return left == '_data' ? data : variables[left] if operator == :variable
    return configuration.key?(states[left]) ? 1 : 0 if operator == :in
    if operator == :not || operator == :negative
      value = evaluate(variables, data, configuration, states, left)
      return operator == :not ? (value.zero? ? 1 : 0) : -value
    end
    a = evaluate(variables, data, configuration, states, left)
    return 0 if operator == '&&' && a.zero?
    return 1 if operator == '||' && !a.zero?
    b = evaluate(variables, data, configuration, states, right)
    raise EvaluationError if %w[/ %].include?(operator) && b.zero?
    case operator
    when '+' then a + b
    when '-' then a - b
    when '*' then a * b
    when '/', '%'
      quotient = a.abs / b.abs
      quotient = -quotient if a.negative? != b.negative?
      operator == '/' ? quotient : a - quotient * b
    when '==' then a == b ? 1 : 0
    when '!=' then a != b ? 1 : 0
    when '<' then a < b ? 1 : 0
    when '<=' then a <= b ? 1 : 0
    when '>' then a > b ? 1 : 0
    when '>=' then a >= b ? 1 : 0
    when '&&', '||' then b.zero? ? 0 : 1
    end
  end
end

class State
  attr_accessor :name, :kind, :parent, :children, :initial, :history_kind, :default,
                :entries, :exits, :transitions, :depth, :entered, :taken, :dwell, :entry_time

  def initialize(name, kind, parent = nil)
    @name, @kind, @parent = name, kind, parent
    @children = []
    @entries = []
    @exits = []
    @transitions = []
    @initial = @history_kind = @default = nil
    @depth = parent ? parent.depth + 1 : 0
    @entered = @taken = @dwell = @entry_time = 0
  end

  def child_states
    @children.reject { |state| state.kind == 'history' }
  end

  def compound?
    @kind == 'root' || (@kind == 'state' && !child_states.empty?)
  end

  def parallel?
    @kind == 'parallel' && !child_states.empty?
  end

  def atomic?
    @kind != 'history' && child_states.empty?
  end

  def initial_child
    @initial || child_states.first
  end
end

class Transition
  attr_accessor :source, :kind, :descriptors, :delay, :guard, :target, :mode, :actions
end

class Chart
  def initialize(definitions)
    @definitions = definitions
    @root = State.new('', 'root')
    @states = {}
    @variables = {}
    @errors = {}
    @document = []
    @configuration = {}
    @history = {}
    @queue = []
    @reservations = []
    @creation = @time = @data = @macrosteps = @microsteps = 0
    @trace = @halted = false
  end

  def descendant?(state, ancestor)
    parent = state.parent
    while parent
      return true if parent == ancestor
      parent = parent.parent
    end
    false
  end

  def check_references(references)
    references.each do |kind, name|
      return "unknown variable #{name}" if kind == :variable && !@variables.key?(name)
      return "unknown state #{name}" if kind == :state && !@states.key?(name)
    end
    nil
  end

  def expression(text)
    text ? Expression.new(text) : nil
  end

  def actions(text)
    references = []
    result = (text ? text.split('; ') : []).map do |action|
      kind, rest = action.split(' ', 2)
      record = { kind: kind }
      case kind
      when 'raise'
        event, value = rest.split(' ', 2)
        record.merge!(event: event, expression: expression(value))
      when 'send'
        event, delay, value = rest.split(' ', 3)
        record.merge!(event: event, delay: delay.to_i, expression: expression(value))
      when 'cancel'
        record[:event] = rest
      when 'log'
        if rest.start_with?('"')
          finish = rest.index('"', 1)
          record[:text] = rest[1...finish]
          record[:expression] = expression(rest[(finish + 2)..]) if finish + 1 < rest.length
        else
          record[:expression] = expression(rest)
        end
      else
        name, value = action.split(' = ', 2)
        record.merge!(kind: 'assign', name: name, expression: expression(value))
        references << [:variable, name]
      end
      references.concat(record[:expression].references) if record[:expression]
      record
    end
    [result, references]
  end

  def validate
    @definitions.each do |line, number|
      parts = line.split(' ')
      kind, name = parts.take(2)
      if %w[state parallel final history].include?(kind)
        parent_name = kind == 'state' && parts[2] == 'initial' ? nil : parts[2]
        if @states.key?(name)
          @errors[number] = "duplicate state #{name}"
        elsif parent_name && !@states.key?(parent_name)
          @errors[number] = "unknown state #{parent_name}"
        elsif parent_name && %w[final history].include?(@states[parent_name].kind)
          @errors[number] = "#{parent_name} cannot have children"
        else
          parent = parent_name ? @states[parent_name] : @root
          state = State.new(name, kind, parent)
          state.history_kind = parts[3] if kind == 'history'
          state.default = parts[4] if kind == 'history'
          if kind == 'state' && (at = parts.index('initial'))
            state.initial = parts[at + 1]
          end
          @states[name] = state
          parent.children << state
        end
      elsif kind == 'var'
        if @variables.key?(name)
          @errors[number] = "duplicate variable #{name}"
        else
          @variables[name] = parts[2].to_i
        end
      end
    end
    visit = lambda do |state|
      @document << state
      state.children.each { |child| visit.call(child) }
    end
    @root.children.each { |state| visit.call(state) }
    @definitions.each do |line, number|
      next if @errors.key?(number)
      kind, name = line.split(' ').take(2)
      state = @states[name]
      reason = nil
      if kind == 'state' && state.initial
        child = @states[state.initial]
        reason = child.nil? ? "unknown state #{state.initial}" : child.parent != state || child.kind == 'history' ? "#{child.name} is not a child of #{name}" : nil
      elsif %w[final history].include?(kind)
        parent = state.parent
        if parent.kind != 'state' || parent.child_states.empty?
          reason = "#{name} needs a compound parent"
        elsif kind == 'history' && state.default
          target = @states[state.default]
          reason = target.nil? ? "unknown state #{state.default}" : !descendant?(target, parent) || target.kind == 'history' ? "#{target.name} is not a descendant of #{parent.name}" : nil
        end
      elsif %w[entry exit].include?(kind)
        if state.nil?
          reason = "unknown state #{name}"
        elsif state.kind == 'history'
          reason = "#{name} cannot have actions"
        else
          list, references = actions(line.split(' / ', 2)[1])
          reason = check_references(references)
          (kind == 'entry' ? state.entries : state.exits) << list unless reason
        end
      elsif kind == 'on'
        if state.nil?
          reason = "unknown state #{name}"
        elsif %w[final history].include?(state.kind)
          reason = "#{name} cannot have transitions"
        else
          match = /\Aon (\S+) (always|after [0-9]+|[^ ]+)(?: \[(.*?)\])?(?: (->|~>) (\S+))?(?: \/ (.*))?\z/.match(line)
          trigger, guard_text, arrow, target_name, action_text = match.captures.drop(1)
          guard = expression(guard_text)
          list, references = actions(action_text)
          ordered_references = guard ? guard.references.dup : []
          ordered_references << [:state, target_name] if target_name
          reason = check_references(ordered_references + references)
          unless reason
            transition = Transition.new
            transition.source = state
            transition.kind = trigger == 'always' ? :always : trigger.start_with?('after ') ? :timer : :event
            transition.descriptors = trigger.split('|') if transition.kind == :event
            transition.delay = trigger.split(' ')[1].to_i if transition.kind == :timer
            transition.guard = guard
            transition.target = target_name ? @states[target_name] : nil
            transition.mode = arrow == '~>' ? :local : arrow ? :external : :internal
            transition.actions = list
            state.transitions << transition
          end
        end
      end
      @errors[number] = reason if reason
    end
    unless @errors.empty?
      @errors.keys.sort.each { |number| puts "error line #{number}: #{@errors[number]}" }
      return false
    end
    @document.each do |state|
      state.initial = @states[state.initial] if state.initial
      state.default = @states[state.default] if state.default
    end
    true
  end

  def default_target(history)
    history.default || history.parent.initial_child
  end

  def warn_unreachable
    reachable = { @root.initial_child => true }
    loop do
      before = reachable.length
      reachable.keys.each do |state|
        reachable[state.parent] = true if state.parent && state.parent != @root
        reachable[state.initial_child] = true if state.compound?
        state.child_states.each { |child| reachable[child] = true } if state.parallel?
        state.transitions.each do |transition|
          target = transition.target
          reachable[target.kind == 'history' ? default_target(target) : target] = true if target
        end
      end
      break if reachable.length == before
    end
    @document.each { |state| puts "warning: unreachable state #{state.name}" if state.kind != 'history' && !reachable[state] }
  end

  def evaluate(value)
    value.evaluate(@variables, @data, @configuration, @states)
  end

  def reserve(record)
    @creation += 1
    @reservations << record.merge(due: @time + record[:delay], number: @creation)
  end

  def run_actions(list)
    list.each do |action|
      value = action[:expression] ? evaluate(action[:expression]) : 0
      case action[:kind]
      when 'assign' then @variables[action[:name]] = value
      when 'raise' then @queue << [action[:event], value]
      when 'send' then reserve(kind: :send, event: action[:event], value: value, delay: action[:delay])
      when 'cancel' then @reservations.reject! { |r| r[:kind] == :send && r[:event] == action[:event] }
      when 'log'
        puts(action[:expression] ? (action[:text] || '') + value.to_s : action[:text])
      end
    end
  rescue EvaluationError
    @queue << ['error.execution', 0]
  end

  def effective_targets(transition)
    target = transition.target
    return [] unless target
    target.kind == 'history' ? (@history.key?(target) ? @history[target] : [default_target(target)]) : [target]
  end

  def choice(transition)
    return { transition: transition, scope: nil, exits: {} } if transition.mode == :internal
    targets = effective_targets(transition)
    source = transition.source
    if transition.mode == :local && source.compound? && targets.all? { |target| descendant?(target, source) }
      scope = source
    else
      scope = source.parent
      scope = scope.parent until scope.compound? && targets.all? { |target| descendant?(target, scope) }
    end
    { transition: transition, scope: scope, exits: @configuration.select { |state, _| descendant?(state, scope) } }
  end

  def matches?(transition, trigger)
    if trigger[:kind] == :always
      transition.kind == :always
    elsif trigger[:kind] == :timer
      transition == trigger[:transition]
    else
      transition.kind == :event && transition.descriptors.any? { |descriptor| descriptor == '*' || descriptor == trigger[:event] || trigger[:event].start_with?(descriptor + '.') }
    end
  end

  def select_transitions(trigger)
    selected = []
    @document.each do |atomic|
      next unless @configuration[atomic] && atomic.atomic?
      state = atomic
      found = nil
      while state != @root && !found
        state.transitions.each do |transition|
          next unless matches?(transition, trigger)
          begin
            accepted = transition.guard.nil? || !evaluate(transition.guard).zero?
          rescue EvaluationError
            @queue << ['error.execution', 0]
            accepted = false
          end
          if accepted
            found = transition
            break
          end
        end
        state = state.parent
      end
      selected << found if found && !selected.include?(found)
    end
    occupied = {}
    selected.filter_map do |transition|
      candidate = choice(transition)
      next if candidate[:exits].keys.any? { |state| occupied[state] }
      occupied.merge!(candidate[:exits])
      candidate
    end
  end

  def expand_entry(set)
    loop do
      before = set.length
      set.keys.each do |state|
        if state.parallel?
          state.child_states.each { |child| set[child] = true }
        elsif state.compound? && state.child_states.none? { |child| set[child] }
          set[state.initial_child] = true
        end
      end
      break if set.length == before
    end
    set
  end

  def complete?(state)
    if state.compound?
      state.child_states.any? { |child| child.kind == 'final' && @configuration[child] }
    elsif state.parallel?
      state.child_states.all? { |child| complete?(child) }
    else
      false
    end
  end

  def enter(set)
    @document.each do |state|
      next unless set[state]
      @configuration[state] = true
      state.entered += 1
      state.entry_time = @time
      state.transitions.each { |transition| reserve(kind: :timer, transition: transition, delay: transition.delay) if transition.kind == :timer }
      state.entries.each { |list| run_actions(list) }
      next unless state.kind == 'final'
      parent = state.parent
      @queue << ["done.state.#{parent.name}", 0]
      grandparent = parent.parent
      @queue << ["done.state.#{grandparent.name}", 0] if grandparent.parallel? && grandparent.child_states.all? { |child| complete?(child) }
    end
  end

  def list(states)
    states.empty? ? '-' : states.map(&:name).join(',')
  end

  def trigger_name(trigger)
    if trigger[:kind] == :always
      'always'
    elsif trigger[:kind] == :timer
      transition = trigger[:transition]
      "after(#{transition.delay})@#{transition.source.name}"
    else
      trigger[:event] + (trigger[:value].zero? ? '' : "=#{trigger[:value]}")
    end
  end

  def microstep(selected, trigger)
    exits = selected.each_with_object({}) { |candidate, set| set.merge!(candidate[:exits]) }
    @document.each do |state|
      next unless state.kind == 'history' && exits[state.parent]
      @history[state] = @document.select do |active|
        @configuration[active] && (state.history_kind == 'deep' ? active.atomic? && descendant?(active, state.parent) : active.parent == state.parent)
      end
    end
    entries = {}
    selected.each do |candidate|
      transition = candidate[:transition]
      next if transition.mode == :internal
      effective_targets(transition).each do |target|
        state = target
        while descendant?(state, candidate[:scope])
          entries[state] = true
          state = state.parent
        end
      end
    end
    expand_entry(entries)
    if @trace
      sources = selected.map { |candidate| candidate[:transition].source }
      puts "[t=#{@time}] #{trigger_name(trigger)} (#{list(sources)}): exit #{list(@document.reverse.select { |state| exits[state] })}; enter #{list(@document.select { |state| entries[state] })}"
    end
    @document.reverse_each do |state|
      next unless exits[state]
      state.exits.each { |actions| run_actions(actions) }
      @configuration.delete(state)
      state.dwell += @time - state.entry_time
      @reservations.reject! { |r| r[:kind] == :timer && r[:transition].source == state }
    end
    selected.each do |candidate|
      transition = candidate[:transition]
      run_actions(transition.actions)
      transition.source.taken += 1
    end
    enter(entries)
  end

  def macrostep(trigger)
    @macrosteps += 1
    count = 0
    perform = lambda do |selected, current|
      if count == 1000
        puts "LIVELOCK t=#{@time}"
        @halted = true
      else
        count += 1
        @microsteps += 1
        microstep(selected, current)
      end
    end
    @data = trigger[:kind] == :event ? trigger[:value] : 0
    if trigger[:kind] == :start
      enter(expand_entry({ @root.initial_child => true }))
    else
      selected = select_transitions(trigger)
      perform.call(selected, trigger) unless selected.empty?
    end
    until @halted
      @data = 0
      current = { kind: :always }
      selected = select_transitions(current)
      unless selected.empty?
        perform.call(selected, current)
        next
      end
      break if @queue.empty?
      event, value = @queue.shift
      @data = value
      current = { kind: :event, event: event, value: value }
      selected = select_transitions(current)
      perform.call(selected, current) unless selected.empty?
    end
  end

  def dump
    puts "dump t=#{@time}"
    @document.each { |state| puts '  ' * state.depth + state.name if @configuration[state] }
    @variables.keys.sort.each { |name| puts "  var #{name} = #{@variables[name]}" }
    @document.each { |state| puts "  history #{state.name} = #{list(@history[state])}" if @history.key?(state) }
    @reservations.sort_by { |r| [r[:due], r[:number]] }.each do |reservation|
      if reservation[:kind] == :timer
        puts "  timer #{reservation[:due]} #{trigger_name(reservation)}"
      else
        puts "  send #{reservation[:due]} #{reservation[:event]} #{reservation[:value]}"
      end
    end
  end

  def run(script)
    return unless validate
    warn_unreachable
    macrostep(kind: :start)
    script.each do |line|
      break if @halted
      command, rest = line.split(' ', 2)
      case command
      when 'event'
        name, value = rest.split(' ')
        macrostep(kind: :event, event: name, value: value.to_i)
      when 'tick'
        finish = @time + rest.to_i
        loop do
          break if @halted
          next_reservation = @reservations.select { |r| r[:due] <= finish }.min_by { |r| [r[:due], r[:number]] }
          break unless next_reservation
          @reservations.delete(next_reservation)
          @time = next_reservation[:due]
          trigger = next_reservation[:kind] == :timer ? next_reservation : { kind: :event, event: next_reservation[:event], value: next_reservation[:value] }
          macrostep(trigger)
        end
        @time = finish unless @halted
      when 'set'
        name, value = rest.split(' ')
        if @variables.key?(name)
          @variables[name] = value.to_i
        else
          puts "error: unknown variable #{name}"
        end
      when 'trace'
        @trace = rest == 'on'
      when 'eval'
        value = expression(rest)
        reason = check_references(value.references)
        if reason
          puts "error: #{reason}"
        else
          @data = 0
          begin
            puts "#{rest} -> #{evaluate(value)}"
          rescue EvaluationError
            puts 'error: division by zero'
          end
        end
      when 'dump'
        dump
      end
    end
    puts "end t=#{@time} macrosteps=#{@macrosteps} microsteps=#{@microsteps}"
    @document.each do |state|
      next if state.kind == 'history'
      time = state.dwell + (@configuration[state] ? @time - state.entry_time : 0)
      puts "  #{state.name} entered=#{state.entered} taken=#{state.taken} time=#{time}"
    end
  end
end

input = STDIN.each_line.map(&:chomp)
charts = input[0].to_i
i = 1
charts.times do
  name = input[i].split(' ')[1]
  i += 1
  definitions = []
  until input[i] == 'RUN'
    definitions << [input[i], i + 1]
    i += 1
  end
  i += 1
  script = []
  until input[i] == 'END'
    script << input[i]
    i += 1
  end
  i += 1
  puts "chart #{name}"
  Chart.new(definitions).run(script)
end
