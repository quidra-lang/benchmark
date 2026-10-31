require 'set'
require_relative 'grid_map'
require_relative 'low_level'
require_relative 'cbs'
require_relative 'prioritized'
require_relative 'report'

class Warehouse
  CLASSES = %w[cardinal semi_cardinal non_cardinal].freeze

  def initialize
    @grid, @agents = GridMap.read_grid, GridMap.read_agents
    @settings = read_parameters
    @distances = @agents.map { |agent| @grid.distances(agent.goal) }
  end

  def read_parameters
    settings = { orders: [(0...@agents.length).to_a], runs: [], delays: [] }
    File.foreach('input/params.txt', chomp: true) do |line|
      kind, *args = line.split(' ')
      case kind
      when 'HORIZON' then settings[:horizon] = args[0].to_i
      when 'HL_BUDGET' then settings[:hl_budget] = args[0].to_i
      when 'LL_BUDGET' then settings[:ll_budget] = args[0].to_i
      when 'WINDOW' then settings[:window], settings[:step] = args.map(&:to_i)
      when 'ORDER' then settings[:orders] << args.map(&:to_i)
      when 'RUN' then settings[:runs] << { name: args.join('-'), solver: args[0], cost_function: args[1] }
      when 'ANIMATE' then settings[:animate], settings[:frames] = args[0], args[1].to_i
      when 'DELAY' then settings[:delays] << args.map(&:to_i)
      end
    end
    settings
  end

  def mdd(id, length, restrictions)
    layers = [Set[@agents[id].start]]
    1.upto(length) do |time|
      layer = Set.new
      layers.last.each do |cell|
        @grid.destinations(cell).each do |destination, _|
          if time + @distances[id].fetch(destination, length + 1) <= length && restrictions.allowed?(cell, destination, time)
            layer.add(destination)
          end
        end
      end
      layers << layer
    end
    valid = Array.new(length + 1) { Set.new }
    valid[length].add(@agents[id].goal)
    (length - 1).downto(0) do |time|
      layers[time].each do |source|
        if @grid.destinations(source).any? { |destination, _| valid[time + 1].include?(destination) && restrictions.allowed?(source, destination, time + 1) }
          valid[time].add(source)
        end
      end
    end
    valid
  end

  def classify(conflict, paths, restrictions, cache)
    fixed = [conflict.a, conflict.b].count do |id|
      layers = cache[id] ||= mdd(id, paths[id].length - 1, restrictions[id])
      width = ->(time) { time < layers.length ? layers[time].length : 1 }
      width.call(conflict.time) == 1 && (conflict.kind == 'vertex' || width.call(conflict.time - 1) == 1)
    end
    CLASSES[2 - fixed]
  end

  def independent_plan
    budget = LowLevel::Budget.new
    restrictions = LowLevel::Prohibitions.new
    @agents.each_with_index.map do |agent, id|
      LowLevel.search(@grid, agent, @distances[id], agent.start, 0, restrictions, @settings[:horizon], budget)[0]
    end
  end

  def conflict_groups(conflicts)
    adjacent = Array.new(@agents.length) { Set.new }
    conflicts.each do |conflict|
      adjacent[conflict.a].add(conflict.b)
      adjacent[conflict.b].add(conflict.a)
    end
    seen, groups = Set.new, []
    @agents.each_index do |start|
      next if seen.include?(start) || adjacent[start].empty?

      component, queue = [], [start]
      seen.add(start)
      until queue.empty?
        current = queue.shift
        component << current
        adjacent[current].each do |other|
          queue << other if seen.add?(other)
        end
      end
      groups << component.sort.map { |id| Report.agent(id) }.join
    end
    groups
  end

  def overview
    degrees = @grid.free.map { |cell| @grid.degree(cell) }
    remaining, components = @grid.free.dup, 0
    until remaining.empty?
      components += 1
      seed = remaining.first
      remaining.delete(seed)
      queue = [seed]
      until queue.empty?
        @grid.neighbors(queue.shift).each do |cell|
          queue << cell if remaining.delete?(cell)
        end
      end
    end
    @shortest = @agents.each_with_index.map { |agent, id| @distances[id].fetch(agent.start) }
    @soc_lower, @makespan_lower = @shortest.sum, @shortest.max
    lines = ["instance width #{@grid.width} height #{@grid.height} free #{@grid.free.length} agents #{@agents.length}",
             "map isolated #{degrees.count(0)} dead_ends #{degrees.count(1)} corridors #{degrees.count(2)} " \
               "junctions #{degrees.count { |degree| degree >= 3 }} components #{components}"]
    @agents.each_with_index do |agent, id|
      layers = mdd(id, @shortest[id], LowLevel::Prohibitions.new)
      lines << "agent #{agent.name} start #{Report.cell(agent.start)} goal #{Report.cell(agent.goal)} " \
               "distance #{@shortest[id]} mdd #{layers.sum(&:length)} width #{layers.map(&:length).max}"
    end
    lines << "lower_bound soc #{@soc_lower} makespan #{@makespan_lower}"
    @independent_conflicts = CBS.conflicts(@independent)
    restrictions, cache = Array.new(@agents.length) { LowLevel::Prohibitions.new }, {}
    @independent_classes = @independent_conflicts.map { |conflict| classify(conflict, @independent, restrictions, cache) }
    kinds = @independent_conflicts.map(&:kind).tally
    classes = @independent_classes.tally
    lines << "independent conflicts #{@independent_conflicts.length} vertex #{kinds.fetch('vertex', 0)} " \
             "edge #{kinds.fetch('edge', 0)} #{class_counts(classes)}"
    groups = conflict_groups(@independent_conflicts)
    lines << "groups #{groups.empty? ? '-' : groups.join(' ')}"
    lines
  end

  def class_counts(counts) = CLASSES.map { |category| "#{category} #{counts.fetch(category, 0)}" }.join(' ')

  def solve_pp(run)
    budget = run[:budget]
    @settings[:orders].each_with_index do |order, index|
      number = index + 1
      run[:high_level] += 1
      before = budget.expansions
      paths, attempts, failure = Prioritized.try_order(@grid, @agents, @distances, @settings[:horizon], order, budget)
      attempts.each do |attempt|
        prefix = "order #{number} agent #{Report.agent(attempt[:agent])}"
        result = attempt[:path] ? "cost #{attempt[:path].length - 1}" : 'failed'
        run[:trace] << "#{prefix} #{result} expansions #{attempt[:expansions]}"
      end
      if failure == 'll_budget'
        run[:reason] = failure
        break
      end
      planned = attempts.length - (failure.nil? ? 0 : 1)
      summary = "order #{number} #{order.map { |id| Report.agent(id) }.join} planned #{planned} expansions #{budget.expansions - before}"
      if failure.nil?
        run[:specific] << "#{summary} ok"
        run[:status], run[:paths], run[:end] = 'OK', paths, "end OK order #{number}"
        return
      end
      run[:specific] << "#{summary} failed #{Report.agent(failure)}"
    end
    run[:reason] ||= 'orders'
    run[:end] = "end FAIL #{run[:reason]}"
  end

  def node(paths, restrictions, number, depth, parent, cost_function)
    costs = paths.map { |path| path.length - 1 }
    cost = cost_function == 'SOC' ? costs.sum : costs.max
    CBS::Node.new(paths, restrictions, number, depth, parent, cost, CBS.conflicts(paths))
  end

  def add_constraint(base, addition)
    id, kind, u, v, time = addition
    changed = base.dup
    restrictions = changed[id] = base[id].copy
    kind == 'vertex' ? restrictions.states.add([u, time]) : restrictions.moves.add([u, v, time])
    changed
  end

  def choose_split(node, solver)
    return [node.conflicts.first, nil] if solver == 'CBS'

    cache = {}
    classes = node.conflicts.map { |conflict| classify(conflict, node.paths, node.constraints, cache) }
    index = classes.each_index.min_by { |i| [CLASSES.index(classes[i]), i] }
    [node.conflicts[index], classes[index]]
  end

  def constraint_lines(node)
    entries = []
    node.constraints.each_with_index do |restrictions, id|
      restrictions.states.each { |cell, time| entries << [id, time, 0, *cell, *cell] }
      restrictions.moves.each { |u, v, time| entries << [id, time, 1, *u, *v] }
    end
    entries.sort.map do |id, time, kind, ux, uy, vx, vy|
      text = kind.zero? ? "vertex #{ux},#{uy}" : "edge #{ux},#{uy} #{vx},#{vy}"
      "constraint #{Report.agent(id)} #{text} t #{time}"
    end
  end

  def solve_cbs(run)
    open = LowLevel::MinHeap.new
    generated, expanded, pruned, classes = 0, 0, 0, Hash.new(0)
    answer, reason = nil, 'exhausted'
    begin
      empty = Array.new(@agents.length) { LowLevel::Prohibitions.new }
      paths = @agents.each_with_index.map do |agent, id|
        LowLevel.search(@grid, agent, @distances[id], agent.start, 0, empty[id], @settings[:horizon], run[:budget])[0]
      end
      root = node(paths, empty, 0, 0, nil, run[:cost_function])
      open.push(root.key, root)
      generated = 1
      until open.empty?
        current = open.pop
        if current.conflicts.empty?
          answer = current
          break
        end
        if expanded == @settings[:hl_budget]
          reason = 'hl_budget'
          break
        end
        expanded += 1
        conflict, category = choose_split(current, run[:solver])
        classes[category] += 1 if category
        children = []
        CBS.split(conflict).each do |addition|
          affected = addition[0]
          restrictions = add_constraint(current.constraints, addition)
          path, = LowLevel.search(@grid, @agents[affected], @distances[affected], @agents[affected].start,
                                  0, restrictions[affected], @settings[:horizon], run[:budget])
          unless path
            pruned += 1
            children << '-'
            next
          end
          child_paths = current.paths.dup
          child_paths[affected] = path
          child = node(child_paths, restrictions, generated, current.depth + 1, current.number, run[:cost_function])
          open.push(child.key, child)
          children << generated
          generated += 1
        end
        text = "expand #{expanded} node #{current.number} parent #{current.parent || '-'} depth #{current.depth} " \
               "cost #{current.cost} conflicts #{current.conflicts.length} split #{Report.conflict(conflict)}"
        text += " class #{category}" if category
        run[:trace] << "#{text} children #{children.join(' ')}"
      end
    rescue LowLevel::BudgetExceeded
      reason = 'll_budget'
    end
    run[:high_level], run[:generated] = expanded, generated
    run[:specific] << "search expanded #{expanded} generated #{generated} pruned #{pruned} open #{open.length}"
    run[:specific] << "classes #{class_counts(classes)}" if run[:solver] == 'ICBS'
    if answer
      run[:status], run[:paths] = 'OK', answer.paths
      run[:specific] << "solution node #{answer.number} depth #{answer.depth}"
      run[:specific].concat(constraint_lines(answer))
      run[:end] = "end OK node #{answer.number} cost #{answer.cost}"
    else
      run[:reason], run[:end] = reason, "end FAIL #{reason}"
    end
  end

  def solve_whca(run)
    window, step = @settings.values_at(:window, :step)
    current = @agents.map(&:start)
    executed = current.map { |cell| [cell] }
    time, rounds, reason = 0, 0, nil
    begin
      until @agents.each_index.all? { |id| current[id] == @agents[id].goal }
        if time >= @settings[:horizon]
          reason = 'timeout'
          break
        end
        rounds += 1
        restrictions = LowLevel::Prohibitions.new
        away, done = @agents.each_index.partition { |id| current[id] != @agents[id].goal }
        plans = {}
        (away + done).each do |id|
          path, expansions = LowLevel.search(@grid, @agents[id], @distances[id], current[id], time,
                                             restrictions, time + window, run[:budget], window: true)
          prefix = "round #{rounds} time #{time} agent #{Report.agent(id)}"
          unless path
            run[:trace] << "#{prefix} blocked expansions #{expansions}"
            reason = 'blocked'
            break
          end
          path += [path.last] * (window + 1 - path.length)
          plans[id] = path
          run[:trace] << "#{prefix} moves #{Report.actions(path)} expansions #{expansions}"
          restrictions.reserve(path, start_time: time)
        end
        break if reason

        @agents.each_index do |id|
          executed[id].concat(plans.fetch(id)[1..step])
          current[id] = plans.fetch(id)[step]
        end
        time += step
      end
    rescue LowLevel::BudgetExceeded
      reason = 'll_budget'
    end
    run[:high_level] = rounds
    run[:specific] << "window #{window} step #{step} rounds #{rounds}"
    if reason
      run[:reason], run[:end] = reason, "end FAIL #{reason}"
    else
      executed.each_with_index do |path, id|
        path.pop while path.length > 1 && path[-1] == @agents[id].goal && path[-2] == @agents[id].goal
      end
      run[:status], run[:paths], run[:end] = 'OK', executed, "end OK rounds #{rounds}"
    end
  end

  def validate(paths)
    start = @agents.each_index.count { |id| paths[id].first != @agents[id].start }
    goal = @agents.each_index.count { |id| paths[id].last != @agents[id].goal }
    moves = paths.sum do |path|
      path.each_cons(2).count { |source, destination| !@grid.destinations(source).any? { |cell, _| cell == destination } }
    end
    conflicts = CBS.conflicts(paths)
    vertex = conflicts.count { |conflict| conflict.kind == 'vertex' }
    edge = conflicts.length - vertex
    follows = 0
    1.upto(paths.map { |path| path.length - 1 }.max) do |time|
      @agents.each_index do |a|
        past_a, next_a = CBS.position(paths[a], time - 1), CBS.position(paths[a], time)
        next if next_a == past_a

        @agents.each_index do |b|
          follows += 1 if a != b && next_a == CBS.position(paths[b], time - 1) && CBS.position(paths[b], time) != past_a
        end
      end
    end
    { verdict: [start, goal, moves, vertex, edge].all?(&:zero?) ? 'VALID' : 'INVALID',
      start: start, goal: goal, moves: moves, vertex: vertex, edge: edge, follows: follows, conflicts: conflicts }
  end

  def plan_statistics(paths, cost_function)
    per_agent = paths.each_with_index.map do |path, id|
      actions = Report.actions(path)
      moves = actions.delete('.')
      { cost: path.length - 1, extra: path.length - 1 - @shortest[id], waits: actions.count('.'),
        turns: moves.chars.each_cons(2).count { |a, b| a != b }, arrive: path.index(@agents[id].goal),
        leave: path.each_cons(2).count { |a, b| a == @agents[id].goal && b != a }, actions: actions }
    end
    lengths = per_agent.map { |record| record[:cost] }
    soc, makespan = lengths.sum, lengths.max
    cost, lower = cost_function == 'SOC' ? [soc, @soc_lower] : [makespan, @makespan_lower]
    traffic, waits = Hash.new(0), Hash.new(0)
    paths.each do |path|
      path.uniq.each { |cell| traffic[cell] += 1 }
      path.each_cons(2) { |a, b| waits[a] += 1 if a == b }
    end
    { agents: per_agent, cost: cost, soc: soc, makespan: makespan, ratio: Report.fraction(cost, lower),
      sum_extra: per_agent.sum { |record| record[:extra] }, max_extra: per_agent.map { |record| record[:extra] }.max,
      waits: per_agent.sum { |record| record[:waits] }, turns: per_agent.sum { |record| record[:turns] },
      arrivals: (0..makespan).map { |time| lengths.count { |length| length <= time } }, traffic: traffic,
      cell_waits: waits, hotspots: traffic.keys.sort_by { |x, y| [-traffic[[x, y]], y, x] }.take(5) }
  end

  def delayed_execution(paths)
    steps = paths.map do |path|
      [[0, path[0]]] + (1...path.length).filter_map { |time| [time, path[time]] if path[time] != path[time - 1] }
    end
    prerequisites = steps.each_with_index.map do |entries, id|
      entries.map do |scheduled, cell|
        steps.each_with_index.flat_map do |others, other|
          next [] if other == id

          others.each_with_index.filter_map { |(time, position), index| [other, index] if position == cell && time < scheduled }
        end
      end
    end
    progress, finish = Array.new(paths.length, 0), Array.new(paths.length, 0)
    time, holds = 0, 0
    until steps.each_index.all? { |id| progress[id] == steps[id].length - 1 }
      advancing, stopped = [], 0
      steps.each_index do |id|
        next if progress[id] == steps[id].length - 1

        if @settings[:delays].any? { |agent, start, duration| agent == id && start <= time && time < start + duration }
          stopped += 1
        elsif prerequisites[id][progress[id] + 1].all? { |other, index| progress[other] > index }
          advancing << id
        else
          holds += 1
        end
      end
      return { deadlock: time, blocked: holds } if advancing.empty? && stopped.zero?

      advancing.each do |id|
        progress[id] += 1
        finish[id] = time + 1 if progress[id] == steps[id].length - 1
      end
      time += 1
    end
    { deadlock: nil, blocked: holds, finish: finish, soc: finish.sum, makespan: finish.max }
  end

  def run_lines(run)
    prefix = "run #{run[:name]} solver #{run[:solver]} cost_function #{run[:cost_function]} result"
    return ["#{prefix} FAIL reason #{run[:reason]}"] + run[:specific] unless run[:status] == 'OK'

    metrics, execution = run.values_at(:metrics, :execution)
    lines = ["#{prefix} OK cost #{metrics[:cost]} soc #{metrics[:soc]} makespan #{metrics[:makespan]} ratio #{metrics[:ratio]}"] + run[:specific]
    metrics[:agents].each_with_index do |record, id|
      lines << "agent #{Report.agent(id)} cost #{record[:cost]} extra #{record[:extra]} waits #{record[:waits]} " \
               "turns #{record[:turns]} arrive #{record[:arrive]} leave #{record[:leave]} moves #{record[:actions]}"
    end
    lines << "arrivals #{metrics[:arrivals].join(' ')}"
    lines << "hotspots #{metrics[:hotspots].map { |cell| "#{Report.cell(cell)}:#{metrics[:traffic].fetch(cell)}" }.join(' ')}"
    if execution[:deadlock]
      lines << "execution deadlock time #{execution[:deadlock]}"
    else
      lines << "execution soc #{execution[:soc]} makespan #{execution[:makespan]} blocked #{execution[:blocked]} finish #{execution[:finish].join(' ')}"
    end
    lines
  end

  def solution_lines
    lines = @overview.dup
    @results.each { |run| lines << ''; lines.concat(run_lines(run)) }
    succeeded = @results.select { |run| run[:status] == 'OK' }
    lines << '' << "summary ok #{succeeded.length} failed #{@results.length - succeeded.length}"
    unless succeeded.empty?
      [:soc, :makespan].each do |kind|
        best = succeeded.map { |run| run[:metrics][kind] }.min
        names = succeeded.select { |run| run[:metrics][kind] == best }.map { |run| run[:name] }.join(' ')
        lines << "best_#{kind} #{best} #{names}"
      end
      ranked = succeeded.sort_by { |run| [run[:metrics][:soc], run[:metrics][:makespan], run[:index]] }
      lines << "ranking #{ranked.map { |run| run[:name] }.join(' ')}"
    end
    lines
  end

  def stats_lines
    lines = ['run,solver,cost_function,result,reason,cost,soc,makespan,sum_extra,max_extra,waits,turns,' \
             'exec_soc,exec_makespan,high_level,generated,searches,expansions']
    @results.each do |run|
      fields = run.values_at(:name, :solver, :cost_function, :status) + [run[:reason] || '-']
      if run[:status] == 'OK'
        fields.concat(run[:metrics].values_at(:cost, :soc, :makespan, :sum_extra, :max_extra, :waits, :turns))
        fields.concat(run[:execution][:deadlock] ? ['-', '-'] : run[:execution].values_at(:soc, :makespan))
      else
        fields.concat(['-'] * 9)
      end
      fields.concat([run[:high_level], run[:generated] || '-', run[:budget].searches, run[:budget].expansions])
      lines << Report.csv(fields)
    end
    lines
  end

  def validation_lines
    baseline = validate(@independent)
    baseline[:conflicts] = @independent_conflicts
    plans = [['INDEPENDENT', baseline]] + @results.map { |run| [run[:name], run[:validation]] }
    plans.flat_map do |name, validation|
      next ["plan #{name} verdict NONE"] unless validation

      counters = [:start, :goal, :moves, :vertex, :edge, :follows].map { |key| "#{key} #{validation[key]}" }.join(' ')
      lines = ["plan #{name} verdict #{validation[:verdict]} #{counters}"]
      validation[:conflicts].each_with_index do |conflict, index|
        text = "  #{Report.conflict(conflict)}"
        text += " #{@independent_classes[index]}" if name == 'INDEPENDENT'
        lines << text
      end
      lines
    end
  end

  def picture(placements)
    @grid.rows.each_with_index.map do |row, y|
      row.chars.each_with_index.map { |char, x| placements.fetch([x, y], char) }.join
    end
  end

  def animation_lines
    run = @results.find { |result| result[:name] == @settings[:animate] }
    return ["run #{run[:name]} FAIL"] unless run[:status] == 'OK'

    paths, frames = run[:paths], @settings[:frames]
    lines = ["run #{run[:name]} frames #{frames}"]
    frames.times do |time|
      done, moving, waiting = 0, 0, 0
      placements = @agents.to_h { |agent| [agent.goal, agent.name.downcase] }
      paths.each_with_index do |path, id|
        if time >= path.length - 1
          done += 1
        elsif time.positive? && CBS.position(path, time) != CBS.position(path, time - 1)
          moving += 1
        else
          waiting += 1
        end
        placements[CBS.position(path, time)] = Report.agent(id)
      end
      lines << '' << "frame #{time} done #{done} moving #{moving} waiting #{waiting}"
      lines.concat(picture(placements))
    end
    [['traffic', :traffic], ['waits', :cell_waits]].each do |label, key|
      placements = run[:metrics][key].to_h { |cell, count| [cell, count >= 10 ? '+' : count.to_s] }
      lines << '' << label
      lines.concat(picture(placements))
    end
    lines
  end

  def run
    @independent = independent_plan
    @overview = overview
    @results = @settings[:runs].each_with_index.map do |definition, index|
      result = definition.merge(index: index, status: 'FAIL', reason: nil, high_level: 0,
                                generated: nil, budget: LowLevel::Budget.new(@settings[:ll_budget]), specific: [], trace: [])
      case result[:solver]
      when 'PP' then solve_pp(result)
      when 'CBS', 'ICBS' then solve_cbs(result)
      when 'WHCA' then solve_whca(result)
      end
      if result[:status] == 'OK'
        result[:metrics] = plan_statistics(result[:paths], result[:cost_function])
        result[:validation] = validate(result[:paths])
        result[:execution] = delayed_execution(result[:paths])
      end
      result
    end
    trace = @results.each_with_index.flat_map do |result, index|
      (index.zero? ? [] : ['']) + ["run #{result[:name]}"] + result[:trace] + [result[:end]]
    end
    Report.write('solutions.txt', solution_lines)
    Report.write('stats.csv', stats_lines)
    Report.write('validation.txt', validation_lines)
    Report.write('trace.txt', trace)
    Report.write('frames.txt', animation_lines)
  end
end

Warehouse.new.run if $PROGRAM_NAME == __FILE__
