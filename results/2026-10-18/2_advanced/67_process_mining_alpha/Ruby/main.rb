require 'set'
require_relative 'eventlog'
require_relative 'dfg'
require_relative 'alpha_miner'
require_relative 'heuristic_miner'
require_relative 'conformance'
require_relative 'report'

def fraction(value, denominator = 1)
  Report.fraction(value, denominator)
end

def percentage(numerator, denominator)
  Report.percentage(numerator, denominator)
end

def list(values)
  Report.list(values)
end

def parameters(values)
  settings = {filter: values['filter_min_follows'].to_i, sla: values['sla_minutes'].to_i,
              observations: values['positive_observations'].to_i}
  {dependency: 'dependency_threshold', relative: 'relative_to_best', loop1: 'loop1_threshold',
   loop2: 'loop2_threshold', and: 'and_threshold'}.each { |key, name| settings[key] = Rational(values[name]) }
  settings
end

def validate(rows)
  events, errors = [], []
  adopted = Set.new
  rows.each do |row|
    time = Eventlog.timestamp_minutes(row[:timestamp])
    key = row.values_at(:case_id, :activity, :timestamp)
    if time.nil?
      errors << "ERROR line #{row[:line]}: bad timestamp #{row[:timestamp]}"
    elsif adopted.include?(key)
      errors << "ERROR line #{row[:line]}: duplicate event #{row[:case_id]} #{row[:activity]} #{row[:timestamp]}"
    else
      adopted.add(key)
      events << row.merge(time: time)
    end
  end
  [events, errors]
end

def log_summary(rows, events, errors, cases, activities, resources, net, settings)
  lines = errors.dup
  chronological = events.sort_by { |event| [event[:time], event[:line]] }
  lines << "LOG rows #{rows.length} adopted #{events.length} rejected #{errors.length} cases #{cases.length} activities #{activities.length} resources #{resources.length} first #{chronological.first[:timestamp]} last #{chronological.last[:timestamp]}"
  statistics = activities.to_h do |name|
    [name, {events: 0, cases: 0, start: 0, end: 0, rework: 0, wait: 0, waits: 0, resources: Set.new}]
  end
  weekdays = Array.new(7) { {events: 0, starts: 0, ends: 0} }
  weekday = ->(time) { (time / 1440 + 3) % 7 }
  day_counts = Hash.new(0)
  late = 0
  cases.each do |item|
    frequencies = Hash.new(0)
    item[:events].each_with_index do |event, i|
      statistic = statistics[event[:activity]]
      statistic[:events] += 1
      statistic[:resources].add(event[:resource])
      frequencies[event[:activity]] += 1
      weekdays[weekday.call(event[:time])][:events] += 1
      if i.positive?
        statistic[:wait] += event[:time] - item[:events][i - 1][:time]
        statistic[:waits] += 1
      end
    end
    frequencies.each do |activity, frequency|
      statistics[activity][:cases] += 1
      statistics[activity][:rework] += 1 if frequency >= 2
    end
    statistics[item[:trace].first][:start] += 1
    statistics[item[:trace].last][:end] += 1
    weekdays[weekday.call(item[:events].first[:time])][:starts] += 1
    weekdays[weekday.call(item[:events].last[:time])][:ends] += 1
    day_counts[item[:duration] / 1440] += 1
    late += 1 if item[:duration] > settings[:sla]
  end
  activities.each do |activity|
    value = statistics[activity]
    wait = value[:waits].zero? ? '-' : fraction(value[:wait], value[:waits])
    lines << "ACTIVITY #{activity} events #{value[:events]} cases #{value[:cases]} start #{value[:start]} end #{value[:end]} rework #{value[:rework]} wait #{wait} resources #{value[:resources].length} model #{net.inputs.key?(activity) ? 'yes' : 'no'}"
  end
  [['LENGTH', cases.map { |item| item[:events].length }], ['DURATION', cases.map { |item| item[:duration] }]].each do |name, values|
    lines << "#{name} min #{values.min} max #{values.max} mean #{fraction(values.sum, values.length)} median #{fraction(Eventlog.median(values))}"
  end
  (0..day_counts.keys.max).each { |day| lines << "DAYS #{day} cases #{day_counts[day]} share #{percentage(day_counts[day], cases.length)}" }
  lines << "SLA limit #{settings[:sla]} late #{late} share #{percentage(late, cases.length)}"
  %w[Mon Tue Wed Thu Fri Sat Sun].each_with_index do |name, i|
    value = weekdays[i]
    lines << "WEEKDAY #{name} events #{value[:events]} starts #{value[:starts]} ends #{value[:ends]}"
  end
  lines
end

def group_variants(cases, follows, settings)
  groups = cases.group_by { |item| item[:trace] }
  variants = groups.map { |trace, group| {trace: trace, cases: group} }.sort_by { |variant| [-variant[:cases].length, variant[:trace]] }
  variants.each_with_index do |variant, i|
    variant[:number] = i + 1
    variant[:keep] = variant[:trace].each_cons(2).all? { |a, b| Dfg.count(follows, a, b) >= settings[:filter] }
    variant[:cases].each { |item| item[:variant] = variant[:number] }
  end
  variants
end

def variant_report(variants, cases, event_count, settings, replay)
  lines = []
  kept_variants = kept_cases = kept_events = 0
  variants.each do |variant|
    count = variant[:cases].length
    first = variant[:cases].first
    durations = variant[:cases].map { |item| item[:duration] }
    late = durations.count { |duration| duration > settings[:sla] }
    fitness = Conformance.fitness(replay[:cases][first[:id]])
    lines << "VARIANT #{variant[:number]} count #{count} share #{percentage(count, cases.length)} length #{variant[:trace].length} first #{first[:id]} duration #{fraction(durations.sum, count)} late #{late} fitness #{fraction(fitness)} #{variant[:keep] ? 'KEEP' : 'DROP'} #{variant[:trace].join(',')}"
    if variant[:keep]
      kept_variants += 1
      kept_cases += count
      kept_events += count * variant[:trace].length
    end
  end
  lines << "FILTER min_follows #{settings[:filter]} variants #{kept_variants} of #{variants.length} cases #{kept_cases} of #{cases.length} events #{kept_events} of #{event_count}"
  lines
end

def directly_follows_report(cases, activities, follows)
  starts, ends, edges = Hash.new(0), {}, {}
  cases.each do |item|
    starts[item[:trace].first] += 1
    (ends[item[:trace].last] ||= []) << item[:duration]
    item[:events].each_cons(2) do |first, second|
      key = [first[:activity], second[:activity]]
      edge = (edges[key] ||= {count: 0, cases: Set.new, waits: []})
      edge[:count] += 1
      edge[:cases].add(item[:id])
      edge[:waits] << second[:time] - first[:time]
    end
  end
  lines = starts.sort_by { |name, count| [-count, name] }.map { |name, count| "START #{name} count #{count}" }
  ends.sort_by { |name, durations| [-durations.length, name] }.each do |name, durations|
    lines << "END #{name} count #{durations.length} duration #{fraction(durations.sum, durations.length)}"
  end
  edges.sort_by { |key, edge| [-edge[:count], key] }.each do |(a, b), edge|
    waits = edge[:waits]
    lines << "EDGE #{a} #{b} count #{edge[:count]} cases #{edge[:cases].length} mean #{fraction(waits.sum, waits.length)} min #{waits.min} max #{waits.max}"
  end
  lines + Dfg.footprint(activities, ->(a, b) { Dfg.basic_relation(follows, a, b) })
end

def discover_alpha(log, activities, relation)
  candidates = []
  known = Set.new
  add = lambda do |pair|
    key = [pair[:a], pair[:b]]
    unless known.include?(key)
      known.add(key)
      candidates << pair.merge(maximal: true)
    end
  end
  causal = 0
  activities.each do |a|
    activities.each do |b|
      next unless relation.call(a, b) == '->'
      causal += 1
      add.call(a: [a], b: [b]) if relation.call(a, a) == '#' && relation.call(b, b) == '#'
    end
  end
  index = 0
  while index < candidates.length
    pair = candidates[index]
    activities.each do |activity|
      [:a, :b].each do |side|
        extended = AlphaMiner.extend_pair(pair, activity, side, relation)
        next unless extended
        pair[:maximal] = false
        add.call(extended)
      end
    end
    index += 1
  end
  pairs = candidates.select { |pair| pair[:maximal] }.sort { |a, b| AlphaMiner.compare_pairs(a, b) }
  starts = log.map { |entry| entry[:trace].first }.uniq.sort
  ends = log.map { |entry| entry[:trace].last }.uniq.sort
  places = ['start'] + pairs.each_index.map { |i| "p#{i + 1}" } + ['end']
  arcs = starts.map { |activity| ['start', activity] } + ends.map { |activity| [activity, 'end'] }
  pairs.each_with_index do |pair, i|
    pair[:a].each { |activity| arcs << [activity, places[i + 1]] }
    pair[:b].each { |activity| arcs << [places[i + 1], activity] }
  end
  {activities: activities, relation: relation, causal: causal, candidates: candidates.length, pairs: pairs,
   starts: starts, ends: ends, net: PetriNet.new(places, activities, arcs, 'start', 'end')}
end

def net_lines(discovery)
  net = discovery[:net]
  lines = ["PLACE start - #{list(discovery[:starts])}"]
  discovery[:pairs].each_with_index { |pair, i| lines << "PLACE p#{i + 1} #{list(pair[:a])} #{list(pair[:b])}" }
  lines << "PLACE end #{list(discovery[:ends])} -"
  net.transitions.each do |transition|
    inputs = net.inputs[transition].map { |i| net.places[i] }
    outputs = net.outputs[transition].map { |i| net.places[i] }
    lines << "TRANSITION #{transition} in #{list(inputs)} out #{list(outputs)}"
  end
  lines << "NET places #{net.places.length} transitions #{net.transitions.length} arcs #{net.arcs.length}"
  lines
end

def alpha_mining(variants)
  filtered = variants.select { |variant| variant[:keep] }.map { |variant| {trace: variant[:trace], weight: variant[:cases].length} }
  activities = filtered.flat_map { |entry| entry[:trace] }.uniq.sort
  follows = Dfg.count_follows(filtered)
  loops = activities.select { |activity| Dfg.count(follows, activity, activity).positive? }
  alpha = discover_alpha(filtered, activities, ->(a, b) { Dfg.basic_relation(follows, a, b) })
  reduced = filtered.map { |entry| {trace: entry[:trace].reject { |activity| loops.include?(activity) }, weight: entry[:weight]} }
  reduced_activities = activities - loops
  triangles = AlphaMiner.triangle_counts(reduced)
  plus = discover_alpha(reduced, reduced_activities, AlphaMiner.alpha_plus_relation(Dfg.count_follows(reduced), triangles))
  arcs = plus[:net].arcs.dup
  loop_lines = loops.map do |activity|
    before = reduced_activities.select { |other| Dfg.count(follows, other, activity).positive? }
    after = reduced_activities.select { |other| Dfg.count(follows, activity, other).positive? }
    index = plus[:pairs].index { |pair| pair[:a] == before && pair[:b] == after }
    place = index ? "p#{index + 1}" : '-'
    arcs.concat([[place, activity], [activity, place]]) if index
    "LOOP #{activity} before #{list(before)} after #{list(after)} place #{place}"
  end
  plus[:net] = PetriNet.new(plus[:net].places, activities, arcs, 'start', 'end')
  lines = ["LOG variants #{filtered.length} cases #{filtered.sum { |entry| entry[:weight] }} activities #{list(activities)}", "LOOPS #{list(loops)}", 'MINER alpha']
  lines.concat(Dfg.footprint(alpha[:activities], alpha[:relation]))
  lines << "PAIRS causal #{alpha[:causal]} candidates #{alpha[:candidates]} maximal #{alpha[:pairs].length}"
  lines.concat(net_lines(alpha))
  lines << 'MINER alpha_plus'
  triangles.sort.each { |(a, b), count| lines << "TRIANGLE #{a} #{b} count #{count}" }
  lines.concat(Dfg.footprint(plus[:activities], plus[:relation]))
  lines << "PAIRS causal #{plus[:causal]} candidates #{plus[:candidates]} maximal #{plus[:pairs].length}"
  lines.concat(loop_lines).concat(net_lines(plus))
  {alpha: alpha[:net], plus: plus[:net], lines: lines}
end

def heuristic_report(log, activities, follows, settings)
  lines = []
  triangles = AlphaMiner.triangle_counts(log)
  loops1, loops2, edges = Set.new, Set.new, Set.new
  loop_pairs = 0
  activities.each do |activity|
    count = Dfg.count(follows, activity, activity)
    next if count.zero?
    measure = HeuristicMiner.loop_measure(count)
    accepted = count >= settings[:observations] && measure >= settings[:loop1]
    lines << "L1 #{activity} count #{count} measure #{fraction(measure)} #{accepted ? 'ACCEPT' : 'REJECT'}"
    if accepted
      loops1.add(activity)
      edges.add([activity, activity])
    end
  end
  activities.combination(2) do |a, b|
    next if loops1.include?(a) || loops1.include?(b)
    count = Dfg.count(triangles, a, b) + Dfg.count(triangles, b, a)
    next if count.zero?
    measure = HeuristicMiner.loop_measure(count)
    accepted = count >= settings[:observations] && measure >= settings[:loop2]
    lines << "L2 #{a} #{b} count #{count} measure #{fraction(measure)} #{accepted ? 'ACCEPT' : 'REJECT'}"
    if accepted
      loops2.add([a, b]).add([b, a])
      loop_pairs += 1
    end
  end
  dependencies, best_out, best_in = [], {}, {}
  activities.each do |a|
    activities.each do |b|
      count = Dfg.count(follows, a, b)
      next if a == b || count.zero?
      measure = HeuristicMiner.dependency(follows, a, b)
      dependencies << [a, b, count, measure]
      best_out[a] = measure if !best_out.key?(a) || measure > best_out[a]
      best_in[b] = measure if !best_in.key?(b) || measure > best_in[b]
    end
  end
  dependencies.each do |a, b, count, measure|
    verdict = if loops2.include?([a, b])
                'LOOP2'
              elsif count < settings[:observations]
                'REJECT_COUNT'
              elsif measure < settings[:dependency]
                'REJECT_MEASURE'
              elsif best_out[a] - measure > settings[:relative] && best_in[b] - measure > settings[:relative]
                'REJECT_BEST'
              else
                'ACCEPT'
              end
    edges.add([a, b]) if %w[ACCEPT LOOP2].include?(verdict)
    lines << "DEP #{a} #{b} count #{count} reverse #{Dfg.count(follows, b, a)} measure #{fraction(measure)} #{verdict}"
  end
  nodes = activities.map do |activity|
    {activity: activity, inputs: activities.select { |other| edges.include?([other, activity]) },
     outputs: activities.select { |other| edges.include?([activity, other]) }}
  end
  nodes.each { |node| lines << "NODE #{node[:activity]} in #{list(node[:inputs])} out #{list(node[:outputs])}" }
  nodes.each do |node|
    [true, false].each do |split|
      neighbors = node[split ? :outputs : :inputs] - [node[:activity]]
      neighbors.combination(2) do |a, b|
        measure = HeuristicMiner.routing_measure(follows, node[:activity], a, b, split)
        lines << "#{split ? 'SPLIT' : 'JOIN'} #{node[:activity]} #{a} #{b} measure #{fraction(measure)} #{measure >= settings[:and] ? 'AND' : 'XOR'}"
      end
    end
  end
  lines << "GRAPH activities #{activities.length} edges #{edges.length} loops1 #{loops1.length} loops2 #{loop_pairs}"
  lines
end

def explore(net)
  initial = net.marking
  states, state_ids, reverse_edges = [initial], {initial => 0}, [[]]
  final = net.marking(true)
  dead = net.transitions.to_set
  follows = {}
  edges = unsafe = deadlocks = 0
  index = 0
  while index < states.length
    marking = states[index]
    enabled = net.enabled_transitions(marking)
    deadlocks += 1 if enabled.empty? && marking != final
    enabled.each do |transition|
      dead.delete(transition)
      following = net.fire(marking, transition)
      if following.any? { |tokens| tokens > 1 }
        unsafe += 1
        next
      end
      edges += 1
      unless state_ids.key?(following)
        state_ids[following] = states.length
        states << following
        reverse_edges << []
      end
      reverse_edges[state_ids[following]] << index
      net.enabled_transitions(following).each { |successor| follows[[transition, successor]] = 1 }
    end
    index += 1
  end
  can_finish = Set.new
  if state_ids.key?(final)
    queue = [state_ids[final]]
    can_finish.add(queue.first)
    index = 0
    while index < queue.length
      reverse_edges[queue[index]].each do |predecessor|
        unless can_finish.include?(predecessor)
          can_finish.add(predecessor)
          queue << predecessor
        end
      end
      index += 1
    end
  end
  stuck = states.length - can_finish.length
  {markings: states.length, edges: edges, unsafe: unsafe, deadlocks: deadlocks, stuck: stuck,
   final: state_ids.key?(final), dead: net.transitions.select { |transition| dead.include?(transition) },
   sound: unsafe.zero? && stuck.zero? && dead.empty?, follows: follows}
end

def footprint_fitness(activities, follows, net, reachability)
  names = (activities + net.transitions).uniq.sort
  differences = []
  differing = 0
  names.each do |a|
    names.each do |b|
      observed = Dfg.basic_relation(follows, a, b)
      model = Dfg.basic_relation(reachability[:follows], a, b)
      next if observed == model
      differing += 1
      differences << "DIFF #{a} #{b} log #{observed} model #{model}" if a <= b
    end
  end
  cells = names.length * names.length
  {activities: names.length, cells: cells, differing: differing, fitness: Rational(cells - differing, cells), differences: differences}
end

def build_prefixes(cases)
  prefixes = {}
  cases.each do |item|
    (0..item[:trace].length).each do |length|
      trace = item[:trace].take(length)
      prefix = (prefixes[trace] ||= {trace: trace, weight: 0, followers: Set.new})
      prefix[:weight] += 1
      prefix[:followers].add(item[:trace][length]) if length < item[:trace].length
    end
  end
  prefixes.values
end

def precision(net, prefixes)
  fitting = allowed = escaping = 0
  escapes = Hash.new(0)
  prefixes.each do |prefix|
    marking = net.marking
    fits = prefix[:trace].all? do |transition|
      if net.enabled?(marking, transition)
        marking = net.fire(marking, transition)
        true
      else
        false
      end
    end
    next unless fits
    fitting += 1
    enabled = net.enabled_transitions(marking)
    allowed += prefix[:weight] * enabled.length
    enabled.each do |transition|
      next if prefix[:followers].include?(transition)
      escaping += prefix[:weight]
      escapes[transition] += prefix[:weight]
    end
  end
  {prefixes: fitting, allowed: allowed, escaping: escaping, escapes: escapes,
   value: allowed.zero? ? Rational(1) : Rational(allowed - escaping, allowed)}
end

def replay_case(net, item)
  record = Conformance.replay_record(net)
  tokens = Array.new(net.places.length) { [] }
  tokens[net.initial] << item[:events].first[:time]
  record[:produced] = 1
  item[:events].each do |event|
    unless net.inputs.key?(event[:activity])
      record[:skipped] += 1
      next
    end
    net.inputs[event[:activity]].each do |place|
      record[:consumed] += 1
      statistic = record[:places][place]
      if tokens[place].empty?
        record[:missing] += 1
        statistic[:missing] += 1
      else
        waiting = event[:time] - tokens[place].shift
        statistic[:waiting_count] += 1
        statistic[:waiting_total] += waiting
        statistic[:waiting_maximum] = [statistic[:waiting_maximum], waiting].max
        statistic[:consumptions][event[:activity]] += 1
      end
    end
    net.outputs[event[:activity]].each do |place|
      tokens[place] << event[:time]
      record[:produced] += 1
    end
  end
  record[:consumed] += 1
  if tokens[net.final].empty?
    record[:missing] += 1
    record[:places][net.final][:missing] += 1
  else
    tokens[net.final].shift
  end
  net.places.each_index do |place|
    remaining = tokens[place].length
    record[:remaining] += remaining
    record[:places][place][:remaining] = remaining
    record[:places][place][:deviating] = record[:places][place][:missing].positive? || remaining.positive? ? 1 : 0
  end
  record[:fitting] = record[:missing].zero? && record[:remaining].zero? ? 1 : 0
  record
end

def replay_all(net, cases)
  totals = Conformance.replay_record(net)
  records = {}
  cases.each do |item|
    record = replay_case(net, item)
    records[item[:id]] = record
    [:missing, :remaining, :consumed, :produced, :skipped, :fitting].each { |field| totals[field] += record[field] }
    net.places.each_index do |place|
      target, source = totals[:places][place], record[:places][place]
      [:missing, :remaining, :deviating, :waiting_count, :waiting_total].each { |field| target[field] += source[field] }
      target[:waiting_maximum] = [target[:waiting_maximum], source[:waiting_maximum]].max
      source[:consumptions].each { |transition, count| target[:consumptions][transition] += count }
    end
  end
  {totals: totals, cases: records}
end

def conformance_report(results, cases)
  reference = results.first[:net]
  lines = ["MODEL places #{reference.places.length} transitions #{reference.transitions.length} arcs #{reference.arcs.length}"]
  results.each do |result|
    name, value = result.values_at(:name, :reachability)
    lines << "REACHABILITY #{name} markings #{value[:markings]} edges #{value[:edges]} unsafe #{value[:unsafe]} deadlocks #{value[:deadlocks]} stuck #{value[:stuck]} final #{value[:final] ? 'yes' : 'no'} dead #{list(value[:dead])} sound #{value[:sound] ? 'yes' : 'no'}"
  end
  results.each do |result|
    name, value = result.values_at(:name, :footprint)
    lines << "FOOTPRINT #{name} activities #{value[:activities]} cells #{value[:cells]} differing #{value[:differing]} fitness #{fraction(value[:fitness])}"
    lines.concat(value[:differences]) if name == 'reference'
  end
  results.each do |result|
    name, value = result.values_at(:name, :precision)
    lines << "PRECISION #{name} prefixes #{value[:prefixes]} allowed #{value[:allowed]} escaping #{value[:escaping]} precision #{fraction(value[:value])}"
    value[:escapes].sort_by { |transition, weight| [-weight, transition] }.each { |transition, weight| lines << "ESCAPE #{name} #{transition} weight #{weight}" }
  end
  results.each do |result|
    name, net = result.values_at(:name, :net)
    value = result[:replay][:totals]
    lines << "REPLAY #{name} cases #{cases.length} fitting #{value[:fitting]} skipped #{value[:skipped]} missing #{value[:missing]} remaining #{value[:remaining]} consumed #{value[:consumed]} produced #{value[:produced]} fitness #{fraction(Conformance.fitness(value))}"
    net.places.each_with_index do |place, i|
      statistic = value[:places][i]
      average = statistic[:waiting_count].zero? ? '-' : fraction(statistic[:waiting_total], statistic[:waiting_count])
      maximum = statistic[:waiting_count].zero? ? '-' : statistic[:waiting_maximum]
      lines << "PLACE #{name} #{place} missing #{statistic[:missing]} remaining #{statistic[:remaining]} deviating #{statistic[:deviating]} tokens #{statistic[:waiting_count]} mean #{average} max #{maximum}"
    end
    net.places.each_with_index do |place, i|
      outputs = net.transitions.select { |transition| net.inputs[transition].include?(i) }
      next if outputs.length < 2
      routes = outputs.map { |transition| "#{transition}=#{value[:places][i][:consumptions][transition]}" }
      lines << "ROUTE #{name} #{place} #{routes.join(',')}"
    end
  end
  lines
end

def conformance_csv(cases, replay)
  ['case_id,variant,events,skipped,missing,remaining,consumed,produced,fitness'] + cases.map do |item|
    value = replay[:cases][item[:id]]
    [item[:id], item[:variant], item[:events].length, value[:skipped], value[:missing], value[:remaining],
     value[:consumed], value[:produced], fraction(Conformance.fitness(value))].join(',')
  end
end

def resource_report(cases, resources)
  statistics = resources.to_h { |resource| [resource, {events: 0, cases: Set.new, work: Hash.new(0)}] }
  handovers, subcontracting, together = {}, Hash.new(0), Hash.new(0)
  total = self_count = 0
  cases.each do |item|
    present = item[:events].map { |event| event[:resource] }.uniq.sort
    item[:events].each do |event|
      statistic = statistics[event[:resource]]
      statistic[:events] += 1
      statistic[:cases].add(item[:id])
      statistic[:work][event[:activity]] += 1
    end
    present.combination(2) { |pair| together[pair] += 1 }
    item[:events].each_cons(2) do |first, second|
      key = [first[:resource], second[:resource]]
      handover = (handovers[key] ||= {count: 0, cases: Set.new})
      handover[:count] += 1
      handover[:cases].add(item[:id])
      total += 1
      self_count += 1 if key[0] == key[1]
    end
    item[:events].each_cons(3) do |a, b, c|
      subcontracting[[a[:resource], b[:resource]]] += 1 if a[:resource] != b[:resource] && a[:resource] == c[:resource]
    end
  end
  lines = resources.each_with_index.map do |resource, i|
    statistic = statistics[resource]
    work = statistic[:work].sort.map { |activity, count| "#{activity}=#{count}" }.join(',')
    "RESOURCE #{i + 1} #{resource} events #{statistic[:events]} cases #{statistic[:cases].length} work #{work}"
  end
  handovers.reject { |(a, b), _| a == b }.sort_by { |key, value| [-value[:count], key] }.each do |(a, b), value|
    lines << "HANDOVER #{a} #{b} count #{value[:count]} cases #{value[:cases].length}"
  end
  cells = resources.map { |a| resources.map { |b| handovers.fetch([a, b], {count: 0})[:count] } }
  lines.concat(Dfg.table(cells, 5))
  subcontracting.sort_by { |key, count| [-count, key] }.each { |(a, b), count| lines << "SUBCONTRACT #{a} #{b} count #{count}" }
  together.sort_by { |key, count| [-count, key] }.each { |(a, b), count| lines << "TOGETHER #{a} #{b} cases #{count}" }
  lines << "TOTAL handovers #{total} self #{self_count} other #{total - self_count}"
  lines
end

def main
  rows, values = Eventlog.read_inputs
  settings = parameters(values)
  events, errors = validate(rows)
  cases = Eventlog.build_cases(events)
  activities = events.map { |event| event[:activity] }.uniq.sort
  resources = events.map { |event| event[:resource] }.uniq.sort
  reference = Conformance.read_model
  full_log = cases.map { |item| {trace: item[:trace], weight: 1} }
  follows = Dfg.count_follows(full_log)
  variants = group_variants(cases, follows, settings)
  discovered = alpha_mining(variants)
  prefixes = build_prefixes(cases)
  results = [['reference', reference], ['alpha', discovered[:alpha]], ['alpha_plus', discovered[:plus]]].map do |name, net|
    reachability = explore(net)
    {name: name, net: net, reachability: reachability, footprint: footprint_fitness(activities, follows, net, reachability),
     precision: precision(net, prefixes), replay: replay_all(net, cases)}
  end
  Report.write_outputs(
    'log_summary.txt' => log_summary(rows, events, errors, cases, activities, resources, reference, settings),
    'variants.txt' => variant_report(variants, cases, events.length, settings, results.first[:replay]),
    'dfg.txt' => directly_follows_report(cases, activities, follows), 'alpha_net.txt' => discovered[:lines],
    'heuristic_net.txt' => heuristic_report(full_log, activities, follows, settings),
    'conformance.csv' => conformance_csv(cases, results.first[:replay]), 'conformance.txt' => conformance_report(results, cases),
    'resources.txt' => resource_report(cases, resources)
  )
end

main if $PROGRAM_NAME == __FILE__
