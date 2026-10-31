require 'set'

PRIORITIES = %w[LOW MEDIUM HIGH CRITICAL].freeze
WORKFLOWS = {
  'BUG' => %w[OPEN TRIAGED IN_PROGRESS REVIEW RESOLVED CLOSED REOPENED],
  'TASK' => %w[OPEN IN_PROGRESS DONE],
  'STORY' => %w[BACKLOG READY IN_PROGRESS REVIEW DONE]
}.freeze
TRANSITIONS = {
  'BUG' => %w[OPEN:TRIAGED TRIAGED:IN_PROGRESS IN_PROGRESS:REVIEW REVIEW:IN_PROGRESS
              REVIEW:RESOLVED RESOLVED:CLOSED RESOLVED:REOPENED CLOSED:REOPENED REOPENED:IN_PROGRESS],
  'TASK' => %w[OPEN:IN_PROGRESS IN_PROGRESS:OPEN IN_PROGRESS:DONE],
  'STORY' => %w[BACKLOG:READY READY:BACKLOG READY:IN_PROGRESS IN_PROGRESS:REVIEW REVIEW:IN_PROGRESS REVIEW:DONE]
}.freeze
DONE_STATES = %w[RESOLVED CLOSED DONE].freeze
ESTIMATES = [0, 1, 2, 3, 5, 8, 13, 21].freeze
EQUALITY = %w[= !=].freeze
ORDERED = %w[= != < <= > >=].freeze
FIELD_OPERATORS = {
  'id' => ORDERED, 'type' => EQUALITY, 'status' => EQUALITY, 'priority' => ORDERED,
  'assignee' => EQUALITY, 'reviewer' => EQUALITY, 'estimate' => ORDERED,
  'sprint' => EQUALITY, 'comments' => ORDERED, 'blocked' => EQUALITY,
  'done' => EQUALITY, 'title' => ['~']
}.freeze

class CommandError < StandardError; end

def display(value)
  value.nil? ? '-' : value.to_s
end

def yes_no(value)
  value ? 'yes' : 'no'
end

def number_list(numbers)
  numbers.empty? ? '-' : numbers.sort.join(',')
end

class Issue
  attr_reader :number, :kind, :title, :blocks, :blockers, :duplicates, :history
  attr_accessor :priority, :state, :assignee, :reviewer, :estimate, :sprint, :comments, :duplicate

  def initialize(number, kind, priority, title)
    @number, @kind, @priority, @title = number, kind, priority, title
    @state = WORKFLOWS[kind].first
    @comments = 0
    @blocks, @blockers, @duplicates = Set.new, Set.new, Set.new
    @history = []
  end

  def done?
    DONE_STATES.include?(@state)
  end

  def points
    @estimate || 0
  end

  def level
    PRIORITIES.index(@priority)
  end
end

class Sprint
  attr_reader :name, :records
  attr_accessor :phase, :start, :finish, :velocity

  def initialize(name)
    @name, @phase, @velocity, @records = name, 'PLANNED', 0, {}
  end
end

class Tracker
  def initialize
    @day = 1
    @users = Set.new
    @issues = {}
    @sprints = {}
  end

  def execute(line)
    @output = []
    command, *args = line.split(' ')
    begin
      process(command, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
    active = active_sprint
    active.records[@day] = remaining(active) if active
    @output
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def issue(text)
    @issues.fetch(text.to_i) { raise CommandError, 'unknown issue' }
  end

  def user(spec)
    return nil if spec == '-'
    raise CommandError, 'unknown user' unless @users.include?(spec)

    spec
  end

  def sprint(name)
    @sprints.fetch(name) { raise CommandError, 'unknown sprint' }
  end

  def not_done(issue)
    raise CommandError, 'issue done' if issue.done?
  end

  def ordered_issues
    @issues.values.sort_by(&:number)
  end

  def unfinished(issue)
    issue.blockers.sort.reject { |number| @issues[number].done? }
  end

  def blocked?(issue)
    !issue.done? && !unfinished(issue).empty?
  end

  def wip(user)
    @issues.values.count { |issue| issue.assignee == user && issue.state == 'IN_PROGRESS' }
  end

  def active_sprint
    @sprints.values.find { |sprint| sprint.phase == 'ACTIVE' }
  end

  def members(sprint)
    ordered_issues.select { |issue| issue.sprint == sprint.name }
  end

  def remaining(sprint)
    members(sprint).reject(&:done?).sum(&:points)
  end

  def summary(sprint)
    issues = members(sprint)
    "issues #{issues.length} points #{issues.sum(&:points)}"
  end

  def record(issue, text)
    issue.history << "day #{@day} #{text}"
  end

  def blocked_states(numbers)
    numbers.to_h { |number| [number, blocked?(@issues[number])] }
  end

  def notify(before)
    before.keys.sort.each do |number|
      after = blocked?(@issues[number])
      emit(after ? 'BLOCKED' : 'UNBLOCKED', number) if before[number] != after
    end
  end

  def change_state(issue, target)
    before = blocked_states(issue.blocks)
    emit('MOVE', issue.number, issue.state, target)
    record(issue, "MOVE #{issue.state} #{target}")
    issue.state = target
    notify(before)
  end

  def reaches?(start, goal)
    pending = [start.number]
    visited = Set.new
    until pending.empty?
      number = pending.pop
      return true if number == goal.number
      next if visited.include?(number)

      visited << number
      pending.concat(@issues[number].blocks.to_a)
    end
    false
  end

  def process(command, args)
    case command
    when 'DAY'
      day = args[0].to_i
      raise CommandError, 'day backwards' if day < @day

      @day = day
      emit('DAY', day)
    when 'USER'
      raise CommandError, 'user exists' if @users.include?(args[0])

      @users << args[0]
      emit('USER', args[0])
    when 'CREATE'
      number, kind, priority = args[0].to_i, args[1], args[2]
      raise CommandError, 'issue exists' if @issues.key?(number)
      raise CommandError, 'bad type' unless WORKFLOWS.key?(kind)
      raise CommandError, 'bad priority' unless PRIORITIES.include?(priority)

      created = Issue.new(number, kind, priority, args.drop(3).join(' '))
      @issues[number] = created
      record(created, "CREATE #{kind} #{priority}")
      emit('CREATE', number, kind, priority, created.state)
    when 'PRIORITY'
      item = issue(args[0])
      priority = args[1]
      raise CommandError, 'bad priority' unless PRIORITIES.include?(priority)
      not_done(item)
      raise CommandError, 'no change' if item.priority == priority

      old = item.priority
      item.priority = priority
      record(item, "PRIORITY #{old} #{priority}")
      emit('PRIORITY', item.number, old, priority)
    when 'ASSIGN', 'REVIEWER'
      set_person(command, args)
    when 'ESTIMATE'
      item = issue(args[0])
      points = args[1].to_i
      raise CommandError, 'bad estimate' unless ESTIMATES.include?(points)
      not_done(item)
      raise CommandError, 'no change' if item.estimate == points

      old = display(item.estimate)
      item.estimate = points
      record(item, "ESTIMATE #{old} #{points}")
      emit('ESTIMATE', item.number, old, points)
    when 'COMMENT'
      item = issue(args[0])
      author = user(args[1])
      item.comments += 1
      record(item, "COMMENT #{author} #{args.drop(2).join(' ')}")
      emit('COMMENT', item.number, item.comments)
    when 'MOVE' then move(args)
    when 'LINK', 'UNLINK' then link(command, args)
    when 'SPRINT' then sprint_command(args)
    when 'QUERY' then query(args.join(' '))
    when 'SHOW' then show(issue(args[0]))
    when 'HISTORY'
      item = issue(args[0])
      emit('HISTORY', item.number, item.history.length)
      @output.concat(item.history)
    when 'BOARD' then board
    when 'WORKLOAD' then workload
    when 'SPRINTS' then list_sprints
    when 'BURNDOWN' then burndown(sprint(args[0]))
    end
  end

  def set_person(command, args)
    item = issue(args[0])
    chosen = user(args[1])
    not_done(item)
    if command == 'ASSIGN'
      raise CommandError, 'no change' if item.assignee == chosen
      if chosen.nil? && %w[IN_PROGRESS REVIEW].include?(item.state)
        raise CommandError, 'assignee required'
      end
      raise CommandError, "wip limit #{args[1]}" if item.state == 'IN_PROGRESS' && wip(chosen) >= 3
      if item.state == 'REVIEW' && chosen == item.reviewer
        raise CommandError, 'reviewer is assignee'
      end
      item.assignee = chosen
    else
      raise CommandError, 'no change' if item.reviewer == chosen
      raise CommandError, 'reviewer required' if chosen.nil? && item.state == 'REVIEW'
      if item.state == 'REVIEW' && chosen == item.assignee
        raise CommandError, 'reviewer is assignee'
      end
      item.reviewer = chosen
    end
    record(item, "#{command} #{args[1]}")
    emit(command, item.number, args[1])
  end

  def move(args)
    item = issue(args[0])
    target = args[1]
    raise CommandError, "duplicate of #{item.duplicate}" if item.duplicate
    raise CommandError, 'bad state' unless WORKFLOWS[item.kind].include?(target)
    unless TRANSITIONS[item.kind].include?("#{item.state}:#{target}")
      raise CommandError, "cannot move #{item.state} to #{target}"
    end
    if target == 'IN_PROGRESS'
      active = active_sprint
      if item.kind == 'STORY' && (active.nil? || item.sprint != active.name)
        raise CommandError, 'not in active sprint'
      end
      raise CommandError, 'no assignee' if item.assignee.nil?
      raise CommandError, "wip limit #{item.assignee}" if wip(item.assignee) >= 3
    elsif target == 'REVIEW'
      raise CommandError, 'no reviewer' if item.reviewer.nil?
      raise CommandError, 'reviewer is assignee' if item.reviewer == item.assignee
    end
    blockers = unfinished(item)
    if %w[DONE RESOLVED].include?(target) && !blockers.empty?
      raise CommandError, "blocked by #{blockers.first}"
    end
    raise CommandError, 'no estimate' if target == 'READY' && item.estimate.nil?

    change_state(item, target)
  end

  def link(command, args)
    relation = args[1]
    allowed = command == 'LINK' ? %w[BLOCKS DUPLICATES] : ['BLOCKS']
    raise CommandError, 'bad link' unless allowed.include?(relation)

    source, target = issue(args[0]), issue(args[2])
    if command == 'UNLINK'
      raise CommandError, 'no link' unless source.blocks.include?(target.number)

      before = blocked_states([target.number])
      source.blocks.delete(target.number)
      target.blockers.delete(source.number)
      record(source, "UNLINK BLOCKS #{target.number}")
      record(target, "UNLINK BLOCKED_BY #{source.number}")
      emit('UNLINK', source.number, 'BLOCKS', target.number)
      notify(before)
      return
    end
    raise CommandError, 'self link' if source == target
    if relation == 'BLOCKS'
      raise CommandError, 'link exists' if source.blocks.include?(target.number)
      raise CommandError, 'cycle' if reaches?(target, source)
      not_done(target)
      before = blocked_states([target.number])
      source.blocks << target.number
      target.blockers << source.number
      record(source, "LINK BLOCKS #{target.number}")
      record(target, "LINK BLOCKED_BY #{source.number}")
      emit('LINK', source.number, relation, target.number)
      notify(before)
    else
      raise CommandError, 'type mismatch' if source.kind != target.kind
      not_done(source)
      raise CommandError, 'target is duplicate' if target.duplicate

      source.duplicate = target.number
      target.duplicates << source.number
      record(source, "LINK DUPLICATES #{target.number}")
      record(target, "LINK DUPLICATED_BY #{source.number}")
      emit('LINK', source.number, relation, target.number)
      change_state(source, source.kind == 'BUG' ? 'CLOSED' : 'DONE')
      if source.sprint && @sprints[source.sprint].phase != 'ENDED'
        record(source, "SPRINT REMOVE #{source.sprint}")
        source.sprint = nil
      end
    end
  end

  def sprint_command(args)
    action, name = args[0], args[1]
    if action == 'NEW'
      raise CommandError, 'sprint exists' if @sprints.key?(name)

      @sprints[name] = Sprint.new(name)
      emit('SPRINT', 'NEW', name)
      return
    end
    plan = sprint(name)
    case action
    when 'ADD', 'REMOVE'
      item = issue(args[2])
      raise CommandError, 'sprint ended' if plan.phase == 'ENDED'
      if action == 'ADD'
        not_done(item)
        if item.sprint && @sprints[item.sprint].phase != 'ENDED'
          raise CommandError, "in sprint #{item.sprint}"
        end
        raise CommandError, 'not ready' if item.state == 'BACKLOG'

        item.sprint = name
      else
        raise CommandError, 'not in sprint' if item.sprint != name
        not_done(item)
        item.sprint = nil
      end
      record(item, "SPRINT #{action} #{name}")
      emit('SPRINT', action, name, item.number, summary(plan))
    when 'START'
      raise CommandError, 'sprint not planned' if plan.phase != 'PLANNED'
      active = active_sprint
      raise CommandError, "sprint active #{active.name}" if active
      raise CommandError, 'sprint empty' if members(plan).empty?

      plan.phase, plan.start = 'ACTIVE', @day
      plan.records[@day] = remaining(plan)
      emit('SPRINT', 'START', name, 'day', @day, summary(plan), 'remaining', remaining(plan))
    when 'END'
      raise CommandError, 'sprint not active' if plan.phase != 'ACTIVE'

      plan.records[@day] = remaining(plan)
      finished, returned = members(plan).partition(&:done?)
      plan.velocity = finished.sum(&:points)
      plan.phase, plan.finish = 'ENDED', @day
      emit('SPRINT', 'END', name, 'day', @day, 'velocity', plan.velocity,
           'done', finished.length, 'returned', returned.length)
      returned.each do |item|
        item.sprint = nil
        record(item, "SPRINT RETURN #{name}")
        emit('RETURNED', item.number)
      end
    end
  end

  def condition(token)
    match = /\A([a-z]*)(>=|<=|!=|=|<|>|~)(.*)\z/.match(token)
    unless match && !match[1].empty? && !match[3].empty?
      raise CommandError, "syntax near #{token}"
    end
    field, operator, text = match.captures
    raise CommandError, "unknown field #{field}" unless FIELD_OPERATORS.key?(field)
    raise CommandError, "bad operator #{token}" unless FIELD_OPERATORS[field].include?(operator)

    value = if text == '-' && %w[assignee reviewer estimate sprint].include?(field) && EQUALITY.include?(operator)
              nil
            elsif %w[id estimate comments].include?(field) && /\A[0-9]{1,6}\z/.match?(text)
              text.to_i
            elsif field == 'priority' && PRIORITIES.include?(text)
              PRIORITIES.index(text)
            elsif field == 'type' && WORKFLOWS.key?(text)
              text
            elsif field == 'status' && WORKFLOWS.values.flatten.include?(text)
              text
            elsif %w[assignee reviewer].include?(field) && @users.include?(text)
              text
            elsif field == 'sprint' && @sprints.key?(text)
              text
            elsif %w[blocked done].include?(field) && %w[yes no].include?(text)
              text
            elsif field == 'title'
              text.downcase
            else
              raise CommandError, "bad value #{token}"
            end
    [field, operator, value]
  end

  def compile_query(text)
    tokens = text.scan(/[()]|[^ ()]+/)
    conditions = {}
    operand, depth = true, 0
    tokens.each_with_index do |token, index|
      if operand
        if token == '('
          depth += 1
        elsif %w[AND OR )].include?(token)
          raise CommandError, "syntax near #{token}"
        elsif token != 'NOT'
          conditions[index] = condition(token)
          operand = false
        end
      elsif %w[AND OR].include?(token)
        operand = true
      elsif token == ')' && depth.positive?
        depth -= 1
      else
        raise CommandError, "syntax near #{token}"
      end
    end
    raise CommandError, 'syntax at end' if operand || !depth.zero?

    output, operators = [], []
    precedence = { 'OR' => 1, 'AND' => 2, 'NOT' => 3 }
    tokens.each_with_index do |token, index|
      if conditions.key?(index)
        output << conditions[index]
      elsif token == '(' || token == 'NOT'
        operators << token
      elsif token == ')'
        output << operators.pop until operators.last == '('
        operators.pop
      else
        while !operators.empty? && operators.last != '(' && precedence[operators.last] >= precedence[token]
          output << operators.pop
        end
        operators << token
      end
    end
    output.concat(operators.reverse)
  end

  def field_value(item, field)
    case field
    when 'id' then item.number
    when 'type' then item.kind
    when 'status' then item.state
    when 'priority' then item.level
    when 'blocked' then yes_no(blocked?(item))
    when 'done' then yes_no(item.done?)
    when 'title' then item.title.downcase
    else item.public_send(field)
    end
  end

  def matches?(item, program)
    stack = []
    program.each do |node|
      if node == 'NOT'
        stack << !stack.pop
      elsif node == 'AND' || node == 'OR'
        right, left = stack.pop, stack.pop
        stack << (node == 'AND' ? left && right : left || right)
      else
        field, operator, expected = node
        actual = field_value(item, field)
        result = case operator
                 when '=' then actual == expected
                 when '!=' then actual != expected
                 when '~' then actual.include?(expected)
                 else
                   !actual.nil? && case operator
                                  when '<' then actual < expected
                                  when '<=' then actual <= expected
                                  when '>' then actual > expected
                                  when '>=' then actual >= expected
                                  end
                 end
        stack << result
      end
    end
    stack.last
  end

  def query(text)
    program = compile_query(text)
    matches = @issues.values.select { |item| matches?(item, program) }.sort_by { |item| [-item.level, item.number] }
    emit('QUERY', matches.length)
    matches.each do |item|
      emit(item.number, item.kind, item.priority, item.state, display(item.assignee), display(item.estimate), item.title)
    end
  end

  def show(item)
    emit('ISSUE', item.number, item.kind, item.priority, item.state, 'blocked', yes_no(blocked?(item)))
    emit('TITLE', item.title)
    emit('PEOPLE', 'assignee', display(item.assignee), 'reviewer', display(item.reviewer))
    emit('PLAN', 'estimate', display(item.estimate), 'sprint', display(item.sprint), 'comments', item.comments)
    emit('LINKS', 'blocks', number_list(item.blocks), 'blocked_by', number_list(item.blockers),
         'duplicate_of', display(item.duplicate), 'duplicated_by', number_list(item.duplicates))
  end

  def board
    emit('BOARD')
    WORKFLOWS.each do |kind, states|
      parts = [kind]
      states.each { |state| parts.concat([state, @issues.values.count { |item| item.kind == kind && item.state == state }]) }
      emit(*parts)
    end
    finished = @issues.values.count(&:done?)
    emit('TOTAL', @issues.length, 'open', @issues.length - finished, 'done', finished)
  end

  def workload
    emit('WORKLOAD', @users.length)
    @users.sort.each do |name|
      assigned = @issues.values.select { |item| item.assignee == name && !item.done? }
      emit(name, 'assigned', assigned.length, 'in_progress', assigned.count { |item| item.state == 'IN_PROGRESS' },
           'review', assigned.count { |item| item.state == 'REVIEW' }, 'reviewing',
           @issues.values.count { |item| item.reviewer == name && item.state == 'REVIEW' }, 'points', assigned.sum(&:points))
    end
  end

  def list_sprints
    emit('SPRINTS', @sprints.length)
    @sprints.each_value do |plan|
      case plan.phase
      when 'PLANNED' then emit(plan.name, plan.phase, summary(plan))
      when 'ACTIVE' then emit(plan.name, plan.phase, 'start', plan.start, summary(plan), 'remaining', remaining(plan))
      else emit(plan.name, plan.phase, 'start', plan.start, 'end', plan.finish, 'velocity', plan.velocity)
      end
    end
  end

  def burndown(plan)
    raise CommandError, 'sprint not started' if plan.phase == 'PLANNED'

    last = plan.phase == 'ACTIVE' ? @day : plan.finish
    emit('BURNDOWN', plan.name, plan.phase, 'days', last - plan.start + 1)
    value = 0
    (plan.start..last).each do |day|
      value = plan.records[day] if plan.records.key?(day)
      emit('day', day, value)
    end
  end
end

tracker = Tracker.new
$stdin.gets.to_i.times { puts tracker.execute($stdin.gets.chomp) }
