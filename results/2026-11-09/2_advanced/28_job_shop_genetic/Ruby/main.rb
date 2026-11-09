require_relative 'instance'
require_relative 'minstd'
require_relative 'dispatch_rules'
require_relative 'genetic'
require_relative 'gantt'

module JobShop
  Schedule = Struct.new(:order, :starts, :completions, :machine_previous,
                        :machine_following, :makespan, keyword_init: true)

  class Program
    RULES = %w[SPT LPT MWKR FIFO].freeze

    def read_input
      @instance = Instance.read('input/instance.txt')
      @operations = @instance.operations
      @count = @operations.length
      @machine_count = @instance.machines.length - 1
      @durations = @operations.map(&:duration)
      @work = @durations.sum
      @params = {}
      File.readlines('input/ga_params.txt', chomp: true).each do |line|
        name, *values = line.split
        @params[name] = case name
                        when 'crossover', 'swap_mutation', 'insert_mutation'
                          values.first.split('/').map(&:to_i)
                        when 'checkpoints'
                          values.map(&:to_i)
                        else
                          values.first.to_i
                        end
      end
    end

    def jackson_bound(machine)
      tasks = @instance.machines[machine].operations.map { |id| @operations[id] }
      remaining = tasks.map(&:duration)
      time = 0
      bound = 0
      while remaining.any?(&:positive?)
        available = tasks.each_index.select { |index| remaining[index].positive? && tasks[index].head <= time }
        if available.empty?
          time = tasks.filter_map { |task| task.head if task.head > time }.min
          available = tasks.each_index.select { |index| remaining[index].positive? && tasks[index].head <= time }
        end
        selected = available.min_by { |index| [-tasks[index].tail, tasks[index].job] }
        release = tasks.filter_map { |task| task.head if task.head > time }.min
        delta = release ? [remaining[selected], release - time].min : remaining[selected]
        time += delta
        remaining[selected] -= delta
        bound = [bound, time + tasks[selected].tail].max if remaining[selected].zero?
      end
      bound
    end

    def lower_bounds
      @jackson = Array.new(@machine_count + 1, 0)
      (1..@machine_count).each { |machine| @jackson[machine] = jackson_bound(machine) }
      job = @instance.jobs.min_by { |candidate| [-candidate.work, candidate.number] }
      machine = (1..@machine_count).min_by { |number| [-@instance.machines[number].bound, number] }
      jackson_machine = (1..@machine_count).min_by { |number| [-@jackson[number], number] }
      @bounds = { job: job, machine: machine, jackson: jackson_machine }
      @lower_bound = [job.work, @instance.machines[machine].bound, @jackson[jackson_machine]].max
    end

    def order_from_starts(starts)
      @instance.machines.map do |machine|
        machine ? machine.operations.sort_by { |id| starts[id] } : []
      end
    end

    def schedule(order, durations = @durations)
      machine_previous = Array.new(@count)
      machine_following = Array.new(@count)
      order.each do |sequence|
        sequence.each_cons(2) do |first, second|
          machine_previous[second] = first
          machine_following[first] = second
        end
      end
      predecessors = @operations.map do |operation|
        [operation.previous, machine_previous[operation.id]].compact.uniq
      end
      successors = Array.new(@count) { [] }
      predecessors.each_with_index do |parents, id|
        parents.each { |parent| successors[parent] << id }
      end
      pending = predecessors.map(&:length)
      ready = (0...@count).select { |id| pending[id].zero? }
      starts = Array.new(@count)
      completions = Array.new(@count)
      cursor = 0
      while cursor < ready.length
        id = ready[cursor]
        cursor += 1
        starts[id] = predecessors[id].map { |parent| completions[parent] }.max || 0
        completions[id] = starts[id] + durations[id]
        successors[id].each do |following|
          pending[following] -= 1
          ready << following if pending[following].zero?
        end
      end
      Schedule.new(order: order, starts: starts, completions: completions,
                   machine_previous: machine_previous, machine_following: machine_following,
                   makespan: completions.max)
    end

    def decoded(chromosome)
      schedule(order_from_starts(Genetic.decode(@instance, chromosome)))
    end

    def chromosome(current)
      @operations.sort_by { |operation| [current.starts[operation.id], operation.job] }.map(&:job)
    end

    def path_analysis(current)
      last = @operations.select { |operation| current.completions[operation.id] == current.makespan }.min_by(&:job).id
      path = [last]
      until current.starts[path.last].zero?
        id = path.last
        machine_parent = current.machine_previous[id]
        parent = if machine_parent && current.completions[machine_parent] == current.starts[id]
                   machine_parent
                 else
                   @operations[id].previous
                 end
        path << parent
      end
      path.reverse!
      blocks = path.chunk { |id| @operations[id].machine }.map { |_, members| members }
      machine_counts = Array.new(@machine_count + 1, 0)
      path.each { |id| machine_counts[@operations[id].machine] += 1 }
      counts = Array.new(@count, 0)
      @operations.sort_by { |operation| [current.starts[operation.id], operation.job] }.each do |operation|
        id = operation.id
        counts[id] = if current.starts[id].zero?
                       1
                     else
                       [operation.previous, current.machine_previous[id]].compact.uniq.sum do |parent|
                         current.completions[parent] == current.starts[id] ? counts[parent] : 0
                       end
                     end
      end
      total = @operations.sum { |operation| current.completions[operation.id] == current.makespan ? counts[operation.id] : 0 }
      bottleneck = (1..@machine_count).min_by { |machine| [-machine_counts[machine], machine] }
      { path: path, blocks: blocks, count: total, machine_counts: machine_counts, bottleneck: bottleneck }
    end

    def swapped_order(order, first, second)
      changed = order.map(&:dup)
      sequence = changed[@operations[first].machine]
      index = sequence.index(first)
      sequence[index], sequence[index + 1] = second, first
      changed
    end

    def neighbours(current, analysis = path_analysis(current))
      analysis[:blocks].flat_map { |block| block.each_cons(2).to_a }.map do |first, second|
        { first: first, second: second, schedule: schedule(swapped_order(current.order, first, second)) }
      end
    end

    def tabu_search(initial)
      current = best = initial
      found = 0
      tabu = {}
      records = []
      stop = 'limit'
      (1..@params['tabu_iterations']).each do |iteration|
        moves = neighbours(current)
        if moves.empty?
          stop = 'no_moves'
          break
        end
        moves.each_with_index do |move, index|
          move[:index] = index
          move[:tabu] = tabu.fetch([move[:first], move[:second]], 0) >= iteration
        end
        selectable = moves.reject { |move| move[:tabu] && move[:schedule].makespan >= best.makespan }
        if selectable.empty?
          stop = 'all_tabu'
          break
        end
        choice = selectable.min_by { |move| [move[:schedule].makespan, move[:index]] }
        current = choice[:schedule]
        tabu[[choice[:second], choice[:first]]] = iteration + @params['tabu_tenure']
        if current.makespan < best.makespan
          best = current
          found = iteration
        end
        records << choice.merge(iteration: iteration, moves: moves.length,
                                tabu_count: moves.count { |move| move[:tabu] }, best: best.makespan)
      end
      { schedule: best, found: found, records: records, stop: stop }
    end

    def run_genetic(baselines)
      random = Minstd.new(@params['seed'])
      population = RULES.map { |rule| chromosome(baselines[rule][:schedule]) }
      basic = @instance.jobs.flat_map { |job| Array.new(job.operations.length, job.number) }
      population << random.shuffle(basic.dup) while population.length < @params['population']
      records = []
      progress = ['generation,best,mean,worst,distinct']
      counters = { crossovers: 0, swaps: 0, inserts: 0 }
      previous_best = nil
      values = []
      best_index = 0
      (0..@params['generations']).each do |generation|
        values = population.map do |genes|
          starts = Genetic.decode(@instance, genes)
          @operations.map { |operation| starts[operation.id] + operation.duration }.max
        end
        ranking = population.each_index.sort_by { |index| [values[index], index] }
        best_index = ranking.first
        if generation.zero? || values[best_index] < previous_best
          records << [generation, values[best_index], best_index + 1]
        end
        previous_best = values[best_index]
        if @params['checkpoints'].include?(generation)
          numerator = values.sum
          denominator = population.length
          divisor = numerator.gcd(denominator)
          mean = "#{numerator / divisor}/#{denominator / divisor}"
          progress << [generation, values.min, mean, values.max, population.uniq.length].join(',')
        end
        break if generation == @params['generations']

        following = ranking.first(@params['elitism']).map { |index| population[index].dup }
        ((population.length - @params['elitism']) / 2).times do
          first = population[Genetic.tournament(values, @params['tournament'], random)]
          second = population[Genetic.tournament(values, @params['tournament'], random)]
          children = if random.decide(@params['crossover'])
                       counters[:crossovers] += 1
                       Genetic.crossover(first, second, @instance.jobs, random)
                     else
                       [first.dup, second.dup]
                     end
          children.each do |child|
            if random.decide(@params['swap_mutation'])
              counters[:swaps] += 1
              Genetic.swap(child, random)
            end
            if random.decide(@params['insert_mutation'])
              counters[:inserts] += 1
              Genetic.insert(child, random)
            end
          end
          following.concat(children)
        end
        population = following
      end
      best_chromosome = population[best_index]
      best_schedule = decoded(best_chromosome)
      seen = {}
      top = []
      population.each_index.sort_by { |index| [values[index], index] }.each do |index|
        genes = population[index]
        next if seen[genes]

        seen[genes] = true
        top << { individual: index + 1, value: values[index],
                 distance: distances(decoded(genes), best_schedule).sum }
        break if top.length == 5
      end
      { chromosome: best_chromosome, schedule: best_schedule, records: records,
        progress: progress, counters: counters, top: top }
    end

    def gene_positions(genes)
      next_index = Hash.new(0)
      positions = Array.new(@count)
      genes.each_with_index do |number, position|
        id = @instance.by_job.fetch(number).operations[next_index[number]]
        positions[id] = position
        next_index[number] += 1
      end
      positions
    end

    def left_shifts(current)
      shifts = []
      (1..@machine_count).each do |machine|
        sequence = current.order[machine]
        sequence.each_with_index do |id, index|
          next if index.zero?

          parent = @operations[id].previous
          ready = parent ? current.completions[parent] : 0
          index.times do |position|
            left = position.zero? ? 0 : current.completions[sequence[position - 1]]
            right = current.starts[sequence[position]]
            start = [left, ready].max
            next unless start + @durations[id] <= right

            shifts << { id: id, position: position, from: current.starts[id], to: start }
            break
          end
        end
      end
      shifts
    end

    def activate(initial)
      current = initial
      records = []
      loop do
        candidates = left_shifts(current)
        break if candidates.empty?

        choice = candidates.min_by { |shift| [shift[:from], @operations[shift[:id]].job] }
        order = current.order.map(&:dup)
        sequence = order[@operations[choice[:id]].machine]
        sequence.delete(choice[:id])
        sequence.insert(choice[:position], choice[:id])
        records << choice
        current = schedule(order)
      end
      { schedule: current, shifts: records }
    end

    def slack_values(current)
      latest = Array.new(@count)
      slack = Array.new(@count)
      free = Array.new(@count)
      @operations.sort_by { |operation| [current.starts[operation.id], operation.job] }.reverse_each do |operation|
        id = operation.id
        successors = [operation.following, current.machine_following[id]].compact.uniq
        latest[id] = (successors.map { |following| latest[following] }.min || current.makespan) - operation.duration
        slack[id] = latest[id] - current.starts[id]
        free[id] = (successors.map { |following| current.starts[following] }.min || current.makespan) - current.completions[id]
      end
      [slack, free]
    end

    def distances(first, second)
      result = Array.new(@machine_count + 1, 0)
      (1..@machine_count).each do |machine|
        positions = second.order[machine].each_with_index.to_h
        sequence = first.order[machine]
        result[machine] = sequence.each_with_index.sum do |id, index|
          sequence.drop(index + 1).count { |other| positions[id] > positions[other] }
        end
      end
      result
    end

    def machine_statistics(current, machine)
      sequence = current.order[machine]
      gaps = []
      intervals = []
      first_start = current.starts[sequence.first]
      intervals << [0, first_start] if first_start.positive?
      sequence.each_cons(2) do |first, second|
        left = current.completions[first]
        right = current.starts[second]
        if right > left
          gaps << right - left
          intervals << [left, right]
        end
      end
      last_completion = current.completions[sequence.last]
      intervals << [last_completion, current.makespan] if last_completion < current.makespan
      { gaps: gaps, intervals: intervals }
    end

    def flow(current)
      @instance.jobs.sum { |job| current.completions[job.operations.last] }
    end

    def idle(current)
      @machine_count * current.makespan - @work
    end

    def percentage(numerator, denominator)
      tenths = (2000 * numerator + denominator) / (2 * denominator)
      "#{tenths / 10}.#{tenths % 10}%"
    end

    def notation(id)
      operation = @operations[id]
      "J#{operation.job}-#{operation.index}"
    end

    def letter_sequence(order, machine)
      order[machine].map { |id| (64 + @operations[id].job).chr }.join
    end

    def baseline_lines
      lines = ["INSTANCE jobs #{@instance.jobs.length} machines #{@machine_count} operations #{@count} work #{@work} errors #{@instance.errors.length}"]
      @instance.errors.each { |error| lines << "ERROR #{error}" }
      @instance.jobs.each do |job|
        route = job.operations.map { |id| "M#{@operations[id].machine}" }.join(' ')
        lines << "JOB J#{job.number} operations #{job.operations.length} work #{job.work} route #{route}"
      end
      (1..@machine_count).each do |number|
        machine = @instance.machines[number]
        lines << "MACHINE M#{number} operations #{machine.operations.length} load #{machine.load} head #{machine.head} tail #{machine.tail} bound #{machine.bound} jackson #{@jackson[number]}"
      end
      lines << "BOUND job #{@bounds[:job].work} J#{@bounds[:job].number}"
      lines << "BOUND machine #{@instance.machines[@bounds[:machine]].bound} M#{@bounds[:machine]}"
      lines << "BOUND jackson #{@jackson[@bounds[:jackson]]} M#{@bounds[:jackson]}"
      lines << "BOUND lower #{@lower_bound}"
      RULES.each do |rule|
        baseline = @baselines[rule]
        current = baseline[:schedule]
        analysis = baseline[:analysis]
        search = baseline[:search]
        lines << "RULE #{rule} makespan #{current.makespan} gap #{percentage(current.makespan - @lower_bound, @lower_bound)} flow #{flow(current)} idle #{idle(current)} decisions #{baseline[:decisions]} ties #{baseline[:ties]}"
        lines << "PATH #{rule} operations #{analysis[:path].length} blocks #{analysis[:blocks].length} critical_paths #{analysis[:count]} bottleneck M#{analysis[:bottleneck]}"
        lines << "TABU #{rule} makespan #{current.makespan} -> #{search[:schedule].makespan} found #{search[:found]} iterations #{search[:records].length} stop #{search[:stop]}"
      end
      best = RULES.each_with_index.min_by { |rule, index| [@baselines[rule][:schedule].makespan, index] }.first
      lines << "BEST #{best} makespan #{@baselines[best][:schedule].makespan}"
      (1..@machine_count).each do |machine|
        values = RULES.map do |rule|
          "#{rule} #{percentage(@instance.machines[machine].load, @baselines[rule][:schedule].makespan)}"
        end
        lines << "UTILIZATION M#{machine} #{values.join(' ')}"
      end
      lines
    end

    def best_schedule_lines
      counters = @ga[:counters]
      ga_makespan = @ga[:schedule].makespan
      lines = ["GA best #{ga_makespan} generation #{@ga[:records].last[0]} crossovers #{counters[:crossovers]} swaps #{counters[:swaps]} inserts #{counters[:inserts]}"]
      @ga[:records].each do |generation, value, individual|
        lines << "RECORD generation #{generation} makespan #{value} individual #{individual}"
      end
      @ga[:top].each_with_index do |individual, index|
        lines << "TOP #{index + 1} individual #{individual[:individual]} makespan #{individual[:value]} distance #{individual[:distance]}"
      end
      lines << "GA_CHROMOSOME #{@ga[:chromosome].join(' ')}"
      lines << "ACTIVE_DECODE makespan #{@active[:schedule].makespan} decisions #{@active[:decisions]}"
      @activated[:shifts].each_with_index do |shift, index|
        lines << "SHIFT #{index + 1} #{notation(shift[:id])} M#{@operations[shift[:id]].machine} start #{shift[:from]} -> #{shift[:to]}"
      end
      lines << "ACTIVATED makespan #{ga_makespan} -> #{@activated[:schedule].makespan} shifts #{@activated[:shifts].length}"
      lines << "SCHEDULE makespan #{@final.makespan} lower_bound #{@lower_bound} gap #{percentage(@final.makespan - @lower_bound, @lower_bound)} improvement #{ga_makespan - @final.makespan} shiftable #{left_shifts(@final).length}"
      lines << "CHROMOSOME #{chromosome(@final).join(' ')}"
      lines << "LEGEND #{@instance.jobs.map { |job| "#{(64 + job.number).chr}=J#{job.number}" }.join(' ')}"
      chart = Gantt.build(@instance, @final, @analysis[:path], @params['gantt_width'])
      lines << "GANTT scale #{chart[:scale]} columns #{chart[:columns]}"
      lines.concat(chart[:lines])
      (1..@machine_count).each do |machine|
        orders = ["FINAL #{letter_sequence(@final.order, machine)}"]
        orders.concat(RULES.map { |rule| "#{rule} #{letter_sequence(@baselines[rule][:schedule].order, machine)}" })
        lines << "ORDER M#{machine} #{orders.join(' ')}"
      end
      (1..@machine_count).each do |machine|
        load = @instance.machines[machine].load
        stats = machine_statistics(@final, machine)
        sequence = @final.order[machine].map do |id|
          "J#{@operations[id].job}:#{@final.starts[id]}-#{@final.completions[id]}"
        end
        lines << "MACHINE M#{machine} load #{load} idle #{@final.makespan - load} utilization #{percentage(load, @final.makespan)} gaps #{stats[:gaps].length} longest_gap #{stats[:gaps].max || 0} sequence #{sequence.join(' ')}"
        intervals = stats[:intervals].map { |left, right| "#{left}-#{right}" }
        lines << "IDLE M#{machine} #{intervals.empty? ? 'none' : intervals.join(' ')}"
      end
      @instance.jobs.each do |job|
        completion = @final.completions[job.operations.last]
        lines << "JOB J#{job.number} operations #{job.operations.length} work #{job.work} start #{@final.starts[job.operations.first]} completion #{completion} waiting #{completion - job.work}"
      end
      total_flow = flow(@final)
      lines << "TOTAL flow #{total_flow} waiting #{total_flow - @work} idle #{idle(@final)}"
      total_pairs = 0
      (1..@machine_count).each do |machine|
        count = @instance.machines[machine].operations.length
        pairs = count * (count - 1) / 2
        total_pairs += pairs
        values = @distances.map { |name, distances| "#{name} #{distances[machine]}" }
        lines << "DISTANCE M#{machine} pairs #{pairs} #{values.join(' ')}"
      end
      values = @distances.map { |name, distances| "#{name} #{distances.sum}" }
      lines << "DISTANCE total pairs #{total_pairs} #{values.join(' ')}"
      lines
    end

    def critical_path_lines
      lines = ["SEARCH start #{@activated[:schedule].makespan} iterations #{@params['tabu_iterations']} tenure #{@params['tabu_tenure']}"]
      @search[:records].each do |record|
        first = record[:first]
        second = record[:second]
        kind = record[:tabu] ? 'aspiration' : 'free'
        lines << "ITER #{record[:iteration]} moves #{record[:moves]} tabu #{record[:tabu_count]} swap M#{@operations[first].machine} #{notation(first)} #{notation(second)} #{kind} makespan #{record[:schedule].makespan} best #{record[:best]}"
      end
      lines << "STOP iterations #{@search[:records].length} reason #{@search[:stop]} best #{@final.makespan} found #{@search[:found]}"
      path = @analysis[:path]
      lines << "PATH operations #{path.length} blocks #{@analysis[:blocks].length} makespan #{@final.makespan} critical_paths #{@analysis[:count]}"
      path.each_with_index do |id, index|
        link = if index.zero?
                 'start'
               elsif @final.machine_previous[id] == path[index - 1]
                 'machine'
               else
                 'job'
               end
        lines << "NODE #{index + 1} #{notation(id)} M#{@operations[id].machine} #{@final.starts[id]}-#{@final.completions[id]} #{link}"
      end
      @analysis[:blocks].each_with_index do |block, index|
        interval = "#{@final.starts[block.first]}-#{@final.completions[block.last]}"
        lines << "BLOCK #{index + 1} M#{@operations[block.first].machine} #{interval} #{block.map { |id| notation(id) }.join(' ')}"
      end
      neighbours(@final, @analysis).each_with_index do |move, index|
        first = move[:first]
        second = move[:second]
        lines << "NEIGHBOUR #{index + 1} M#{@operations[first].machine} #{notation(first)} #{notation(second)} makespan #{move[:schedule].makespan}"
      end
      lines << "CRITICAL operations #{@slack.count(&:zero?)} total #{@count}"
      @instance.jobs.each { |job| lines << "SLACK J#{job.number} #{job.operations.map { |id| @slack[id] }.join(' ')}" }
      @instance.jobs.each { |job| lines << "FREE J#{job.number} #{job.operations.map { |id| @free[id] }.join(' ')}" }
      (1..@machine_count).each do |machine|
        changed = @operations.map do |operation|
          operation.duration + (operation.machine == machine ? (operation.duration + 9) / 10 : 0)
        end
        sensitivity = schedule(@final.order, changed).makespan
        critical_count = @instance.machines[machine].operations.count { |id| @slack[id].zero? }
        lines << "MACHINE M#{machine} critical #{critical_count} path #{@analysis[:machine_counts][machine]} sensitivity #{sensitivity} delta #{sensitivity - @final.makespan}"
      end
      bottleneck = @analysis[:bottleneck]
      lines << "BOTTLENECK M#{bottleneck} path #{@analysis[:machine_counts][bottleneck]}"
      lines
    end

    def write(name, lines)
      File.binwrite(File.join('output', name), lines.join("\n") + "\n")
    end

    def run
      read_input
      lower_bounds
      @baselines = {}
      RULES.each do |rule|
        dispatched = DispatchRules.build(@instance, rule)
        current = schedule(order_from_starts(dispatched[:starts]))
        @baselines[rule] = dispatched.merge(schedule: current, analysis: path_analysis(current),
                                            search: tabu_search(current))
      end
      @ga = run_genetic(@baselines)
      dispatched = DispatchRules.build(@instance, 'GENES', gene_positions(@ga[:chromosome]))
      @active = dispatched.merge(schedule: schedule(order_from_starts(dispatched[:starts])))
      @activated = activate(@ga[:schedule])
      @search = tabu_search(@activated[:schedule])
      @final = @search[:schedule]
      @analysis = path_analysis(@final)
      @slack, @free = slack_values(@final)
      @distances = RULES.to_h { |rule| [rule, distances(@final, @baselines[rule][:schedule])] }
      @distances['GA'] = distances(@final, @ga[:schedule])
      Dir.mkdir('output') unless Dir.exist?('output')
      write('baselines.txt', baseline_lines)
      write('ga_progress.csv', @ga[:progress])
      write('best_schedule.txt', best_schedule_lines)
      write('critical_path.txt', critical_path_lines)
    end
  end
end

JobShop::Program.new.run
