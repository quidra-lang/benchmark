require 'set'
require_relative 'topology'
require_relative 'policy'
require_relative 'decision'
require_relative 'simulator'
require_relative 'report'

class Session
  attr_reader :owner, :link, :incoming, :outgoing, :pending
  attr_accessor :timer, :sent, :received

  def initialize(owner, link)
    @owner, @link = owner, link
    @incoming, @outgoing, @pending = {}, {}, Set.new
    @timer, @sent, @received = nil, 0, 0
  end
end

class Router
  attr_reader :origination, :rib, :sessions
  attr_accessor :changes

  def initialize(owner, links)
    @origination, @rib = {}, {}
    @sessions = links.map { |link| Session.new(owner, link) }
    @changes = 0
  end
end

class Period
  attr_reader :number, :event, :before, :counters, :exploration, :best_lines, :states
  attr_accessor :convergence_time, :delivery_times, :divergence, :status, :routes_changed

  def initialize(number, event, routers)
    @number, @event = number, event
    @before = routers.transform_values { |router| router.rib.dup }
    @counters, @exploration, @best_lines, @states = Hash.new(0), Hash.new(0), [], {}
    @convergence_time, @delivery_times, @routes_changed = 0, 0, 0
  end
end

Forwarding = Data.define(:result, :visits, :hops) do
  def count = hops.count { |_, _, link| link }
  def arrival = result == 'DELIVERED' ? hops.last[0] : nil
end

class Simulation
  CONVERGENCE_HEADER = 'event,time,kind,status,convergence_time,updates,withdrawals,drops,' \
                       'best_changes,routes_changed,max_exploration'

  def initialize(network, policies, defaults, stepcap, traces)
    @network, @policies, @defaults, @stepcap, @traces = network, policies, defaults, stepcap, traces
    @routers = network.ases.to_h { |owner| [owner, Router.new(owner, network.at_as.fetch(owner))] }
    @sessions = @routers.values.flat_map(&:sessions)
    @by_session = @sessions.to_h { |session| [[session.owner, session.link.number], session] }
    @messages = Simulator::MessageQueue.new
    @time, @logs, @periods = 0, [], []
    @changed_prefixes = Set.new
    @trace_records, @ongoing_traces, @ring_records, @ongoing_rings = [], {}, [], {}
  end

  def log(content) = @logs << "#{@time} #{content}"

  def message_text(message)
    "##{message.serial} #{message.sender}->#{message.receiver} #{message.link.name} " \
      "#{Topology.prefix_text(message.prefix)}"
  end

  def import_route(session, prefix, attribute)
    rule = @policies.applied('IMPORT', session.owner, session.link, prefix, attribute.path, attribute.communities)
    return [nil, rule] if rule&.has?('DENY')

    local_pref = @defaults.fetch(session.link.role(session.owner))
    med, communities = attribute.med, attribute.communities
    if rule
      local_pref = rule.value('LOCALPREF', local_pref)
      med = rule.value('MED', med)
      communities = Policy.edit(communities, rule)
    end
    [Decision::Route.new(attribute.path, attribute.origin, med, communities, local_pref, session.link), rule]
  end

  def candidates(owner, prefix)
    @routers.fetch(owner).sessions.filter_map do |session|
      import_route(session, prefix, session.incoming.fetch(prefix))[0] if session.incoming.key?(prefix)
    end
  end

  def advertised(session, prefix)
    owner, link = session.owner, session.link
    route = @routers.fetch(owner).rib[prefix]
    return [nil, nil] unless route
    return [nil, nil] if !route.local? && route.neighbor == link.other(owner)
    return [nil, nil] if route.communities.include?(Policy::NO_EXPORT)

    rule = @policies.applied('EXPORT', owner, link, prefix, route.path, route.communities)
    return [nil, rule] if rule&.has?('DENY')
    if !rule&.has?('ALLOW') && !route.local? && route.link.role(owner) != 'customer' && link.role(owner) != 'customer'
      return [nil, rule]
    end
    prepend = rule ? rule.value('PREPEND', 0) : 0
    med = rule ? rule.value('MED', 0) : 0
    communities = rule ? Policy.edit(route.communities, rule) : route.communities
    [Decision::Attribute.new(([owner] * (1 + prepend) + route.path).freeze, route.origin, med, communities), rule]
  end

  def redecide(owner, prefix)
    router = @routers.fetch(owner)
    route = router.origination[prefix]
    unless route
      options = candidates(owner, prefix)
      route = Decision.best(options, @network.router_ids)[0] unless options.empty?
    end
    return if router.rib[prefix] == route

    if route
      router.rib[prefix] = route
    else
      router.rib.delete(prefix)
    end
    log("BEST #{owner} #{Topology.prefix_text(prefix)} #{Report.route_text(route)}")
    router.changes += 1
    @period.counters[:best_changes] += 1
    @period.exploration[[owner, prefix]] += 1
    @period.best_lines << [@time, owner, prefix, route]
    @changed_prefixes.add(prefix)
    router.sessions.each do |session|
      next unless session.link.up

      session.pending.add(prefix)
      process_pending(session) unless session.timer
    end
  end

  def process_pending(session)
    sent = 0
    session.pending.sort.each do |prefix|
      content, rule = advertised(session, prefix)
      next if session.outgoing[prefix] == content

      if content
        session.outgoing[prefix] = content
      else
        session.outgoing.delete(prefix)
      end
      message = @messages.send(@time, session.owner, session.link.other(session.owner), session.link, prefix, content)
      suffix = content ? "ANNOUNCE #{Report.attribute_text(content)}" : 'WITHDRAW'
      log("SEND #{message_text(message)} #{suffix}")
      session.sent += 1
      sent += 1
      @period.counters[:updates] += 1
      @period.counters[:withdrawals] += 1 unless content
      rule.hits += 1 if rule
    end
    session.pending.clear
    session.timer = sent.positive? && session.link.mrai.positive? ? @time + session.link.mrai : nil
  end

  def receive(message)
    session = @by_session.fetch([message.receiver, message.link.number])
    prefix, content = message.prefix, message.content
    session.received += 1
    @period.convergence_time = @time - @period.event.time
    if content.nil?
      session.incoming.delete(prefix)
      result = 'WITHDRAW'
    elsif content.path.include?(message.receiver)
      session.incoming.delete(prefix)
      result = 'ANNOUNCE loop'
    else
      session.incoming[prefix] = content
      route, rule = import_route(session, prefix, content)
      rule.hits += 1 if rule
      result = route ? 'ANNOUNCE accept' : 'ANNOUNCE deny'
      result += " #{rule.name}" if rule
    end
    log("RECV #{message_text(message)} #{result}")
    redecide(message.receiver, prefix)
  end

  def originate(owner, prefix, origin, communities)
    @routers.fetch(owner).origination[prefix] = Decision::Route.originated(origin, Policy.communities(communities))
    redecide(owner, prefix)
  end

  def link_down(link)
    link.up = false
    link.down_count += 1
    @messages.remove_link(link).each do |message|
      log("DROP #{message_text(message)}")
      @period.counters[:drops] += 1
    end
    remembered = {}
    endpoints = [link.first, link.second].sort
    endpoints.each do |owner|
      session = @by_session.fetch([owner, link.number])
      remembered[owner] = session.incoming.keys.sort
      session.incoming.clear
      session.outgoing.clear
      session.pending.clear
      session.timer = nil
    end
    endpoints.each { |owner| remembered.fetch(owner).each { |prefix| redecide(owner, prefix) } }
  end

  def link_up(link)
    link.up = true
    [link.first, link.second].sort.each do |owner|
      session = @by_session.fetch([owner, link.number])
      session.pending.replace(@routers.fetch(owner).rib.keys)
      process_pending(session)
    end
  end

  def change_policy(rule, active)
    rule.active = active
    router = @routers.fetch(rule.owner)
    if rule.direction == 'IMPORT'
      router.sessions.flat_map { |session| session.incoming.keys }.uniq.sort.each do |prefix|
        redecide(rule.owner, prefix)
      end
    else
      router.sessions.each do |session|
        next unless session.link.up

        session.pending.merge(router.rib.keys).merge(session.outgoing.keys)
        process_pending(session) unless session.timer
      end
    end
  end

  def execute_event(event)
    log("EVENT #{@period.number} #{event.text}")
    fields = event.fields
    case event.kind
    when 'INITIAL'
      @network.initial.each { |entry| originate(*entry) }
    when 'ANNOUNCE'
      originate(fields[1].to_i, Topology.prefix(fields[2]), fields[3], fields.drop(4))
    when 'WITHDRAW'
      owner, prefix = fields[1].to_i, Topology.prefix(fields[2])
      @routers.fetch(owner).origination.delete(prefix)
      redecide(owner, prefix)
    when 'LINK_DOWN' then link_down(@network.by_name.fetch(fields[2]))
    when 'LINK_UP' then link_up(@network.by_name.fetch(fields[2]))
    else change_policy(@policies.by_name.fetch(fields[2]), event.kind == 'POLICY_ON')
    end
  end

  def global_state
    sessions = @sessions.map do |session|
      [session.incoming.sort, session.outgoing.sort, session.pending.sort,
       session.timer && session.timer - @time]
    end
    [sessions, @messages.state(@time)]
  end

  def detect_divergence
    return if @period.divergence || @period.delivery_times > @stepcap

    state = global_state
    if @period.states.key?(state)
      first = @period.states.fetch(state)
      cycle = @period.best_lines.select { |time, _, _, _| time > first && time <= @time }
      @period.divergence = [first, @time, cycle]
    else
      @period.states[state] = @time
    end
  end

  def quiet? = @messages.next_time.nil? && @sessions.all? { |session| session.pending.empty? }

  def run(events)
    events.each_with_index do |event, number|
      boundary = events[number + 1] ? events[number + 1].time - 1 : nil
      @period = Period.new(number, event, @routers)
      @periods << @period
      @time = event.time
      @changed_prefixes.clear
      execute_event(event)
      quiet = false
      loop do
        delivered = false
        while @messages.next_time == @time
          receive(@messages.take)
          delivered = true
        end
        @sessions.each do |session|
          next unless session.timer == @time

          session.timer = nil
          process_pending(session) unless session.pending.empty?
        end
        forwarding_checks unless @changed_prefixes.empty?
        if delivered
          @period.delivery_times += 1
          detect_divergence
        end
        quiet = quiet?
        break if boundary ? @time == boundary : quiet || @period.divergence || @period.delivery_times >= @stepcap

        # Skip times at which none of the four stages can change state.
        @time = ([@messages.next_time, boundary] + @sessions.map(&:timer)).compact.min
        @changed_prefixes.clear
      end
      @period.status = if @period.divergence then 'DIVERGENT'
                       elsif quiet then 'CONVERGED'
                       elsif boundary then 'UNSETTLED'
                       else 'CAPPED'
                       end
      @routers.each do |owner, router|
        before = @period.before.fetch(owner)
        @period.routes_changed += (before.keys | router.rib.keys).count { |prefix| before[prefix] != router.rib[prefix] }
      end
      @period.states.clear
    end
  end

  def trace(source, address)
    owner, visits, hops = source, [source], []
    loop do
      rib = @routers.fetch(owner).rib
      prefix = rib.keys.select { |entry| Topology.contains?(entry, address) }.max_by { |entry| entry[1] }
      return Forwarding.new(hops.empty? ? 'UNREACHABLE' : 'BLACKHOLE', visits, hops) unless prefix

      route = rib.fetch(prefix)
      if route.local?
        hops << [owner, prefix, nil]
        return Forwarding.new('DELIVERED', visits, hops)
      end
      hops << [owner, prefix, route.link]
      owner = route.link.other(owner)
      repeated = visits.include?(owner)
      visits << owner
      return Forwarding.new('LOOP', visits, hops) if repeated
    end
  end

  def prefix_loops(prefix)
    arrows = {}
    @routers.each do |owner, router|
      route = router.rib[prefix]
      arrows[owner] = route.link.other(owner) if route && !route.local?
    end
    finished, loops = Set.new, Set.new
    @network.ases.each do |start|
      next if finished.include?(start)

      path, positions, current = [], {}, start
      while arrows.key?(current) && !finished.include?(current) && !positions.key?(current)
        positions[current] = path.length
        path << current
        current = arrows.fetch(current)
      end
      if positions.key?(current)
        cycle = path.drop(positions.fetch(current))
        loops.add(cycle.rotate(cycle.index(cycle.min)))
      end
      finished.merge(path)
    end
    loops
  end

  def forwarding_checks
    @changed_prefixes.sort.each do |prefix|
      loops = prefix_loops(prefix)
      @ongoing_rings.keys.each do |key|
        next unless key[0] == prefix && !loops.include?(key[1])

        @ongoing_rings.delete(key)[:end] = @time
      end
      loops.sort.each do |cycle|
        key = [prefix, cycle]
        next if @ongoing_rings.key?(key)

        record = { prefix: prefix, path: cycle, start: @time, end: nil }
        @ring_records << record
        @ongoing_rings[key] = record
      end
    end
    @traces.each_with_index do |(source, _, address), index|
      path = trace(source, address)
      status = ['LOOP', 'BLACKHOLE'].include?(path.result) ? [path.result, path.visits] : nil
      record = @ongoing_traces[index]
      @ongoing_traces.delete(index)[:end] = @time if record && record[:status] != status
      next unless status && !@ongoing_traces.key?(index)

      record = { index: index, status: status, start: @time, end: nil }
      @trace_records << record
      @ongoing_traces[index] = record
    end
  end

  def collapse_runs(path) = path.chunk(&:itself).map(&:first)

  def valley_position(pattern)
    position = 0
    position += 1 while pattern[position] == 'U'
    position += 1 if pattern[position] == 'P'
    position += 1 while pattern[position] == 'D'
    position
  end

  def rib_lines
    lines = []
    @routers.each do |owner, router|
      local = router.rib.values.count(&:local?)
      sent, received = router.sessions.sum(&:sent), router.sessions.sum(&:received)
      lines << "AS #{owner} routes #{router.rib.length} local #{local} sent #{sent} received #{received} changes #{router.changes}"
      router.sessions.each do |session|
        accepted = session.incoming.count { |prefix, attribute| import_route(session, prefix, attribute)[0] }
        link = session.link
        lines << "SESSION #{link.name} #{link.other(owner)} #{link.role(owner)} #{link.up ? 'UP' : 'DOWN'} " \
                 "in #{session.incoming.length} accepted #{accepted} out #{session.outgoing.length} " \
                 "sent #{session.sent} received #{session.received} flaps #{link.down_count}"
      end
      router.rib.sort.each do |prefix, route|
        options = candidates(owner, prefix)
        line = "#{Topology.prefix_text(prefix)} #{Report.route_text(route)} candidates #{options.length}"
        line += " reason #{Decision.best(options, @network.router_ids)[1]}" unless route.local?
        lines << line
        remaining = options.reject { |candidate| candidate == route }
        until remaining.empty?
          alternate, = Decision.best(remaining, @network.router_ids)
          lines << "ALT #{Report.route_text(alternate)}"
          remaining.delete(alternate)
        end
      end
    end
    lines
  end

  def trace_lines(source, address, value)
    path = trace(source, value)
    lines = ["TRACE #{source} #{address} #{path.result} hops #{path.count}"]
    path.hops.each do |owner, prefix, link|
      suffix = link ? "next #{link.other(owner)} link #{link.name}" : 'LOCAL'
      lines << "HOP #{owner} #{Topology.prefix_text(prefix)} #{suffix}"
    end
    lines << "HOP #{path.visits.last} REVISIT" if path.result == 'LOOP'
    lines << "HOP #{path.visits.last} NOROUTE" if ['BLACKHOLE', 'UNREACHABLE'].include?(path.result)
    if path.hops.empty?
      lines << 'CONTROL NONE'
    else
      route = @routers.fetch(source).rib.fetch(path.hops.first[1])
      notation = route.local? ? 'LOCAL' : Report.path_text(route.path)
      match = path.result == 'DELIVERED' && collapse_runs(route.path) == path.visits.drop(1)
      lines << "CONTROL #{notation} #{match ? 'MATCH' : 'MISMATCH'}"
    end
    if path.count.positive?
      pattern = path.hops.filter_map { |owner, _, link| link&.direction(owner) }.join
      lines << "PATTERN #{pattern} #{valley_position(pattern) == pattern.length ? 'VALLEYFREE' : 'VALLEY'}"
    end
    lines
  end

  def path_lines
    lines = @traces.flat_map { |entry| trace_lines(*entry) }
    prefixes = @routers.values.flat_map { |router| router.origination.keys }.uniq.sort
    names = prefixes.map { |prefix| Topology.prefix_text(prefix) }.join(',')
    lines << (names.empty? ? 'PREFIXES' : "PREFIXES #{names}")
    @network.ases.each do |source|
      symbols = prefixes.map do |prefix|
        path = trace(source, prefix[0])
        if path.result == 'DELIVERED'
          path.count.zero? ? '*' : (@routers.fetch(path.arrival).origination.key?(prefix) ? '+' : 'X')
        else
          { 'LOOP' => 'L', 'BLACKHOLE' => 'B', 'UNREACHABLE' => 'U' }.fetch(path.result)
        end
      end.join
      lines << (symbols.empty? ? "REACH #{source}" : "REACH #{source} #{symbols}")
    end
    lines
  end

  def audit_lines
    lines, totals = [], Hash.new(0)
    @trace_records.sort_by { |record| [record[:start], record[:index]] }.each do |record|
      source, address, = @traces.fetch(record[:index])
      result, visits = record[:status]
      totals[result] += 1
      line = "#{result} #{source} #{address} from #{record[:start]} to #{record[:end] || 'END'}"
      line += " at #{visits.last}" if result == 'BLACKHOLE'
      lines << "#{line} path #{Report.path_text(visits)}"
    end
    @ring_records.sort_by { |record| [record[:start], record[:prefix], record[:path][0]] }.each do |record|
      lines << "RING #{Topology.prefix_text(record[:prefix])} from #{record[:start]} to #{record[:end] || 'END'} " \
               "path #{Report.path_text(record[:path])}"
    end
    routes, valleys = 0, 0
    @routers.each do |owner, router|
      router.rib.sort.each do |prefix, route|
        next if route.local?

        routes += 1
        path = collapse_runs([owner] + route.path)
        pattern = path.each_cons(2).map { |first, second| @network.connecting(first, second).first.direction(first) }.join
        violation = valley_position(pattern)
        next if violation == pattern.length

        valleys += 1
        lines << "VALLEY #{owner} #{Topology.prefix_text(prefix)} path #{Report.path_text(route.path)} " \
                 "pattern #{pattern} leaker #{path[violation]}"
      end
    end
    @policies.rules.each do |rule|
      lines << "RULE #{rule.name} #{rule.direction} #{rule.active ? 'ON' : 'OFF'} hits #{rule.hits}"
    end
    divergent = 0
    @periods.each do |period|
      next unless period.divergence

      divergent += 1
      first, repeat, cycle = period.divergence
      lines << "DIVERGENT event #{period.number} first #{first} repeat #{repeat} period #{repeat - first}"
      oscillations = Hash.new(0)
      cycle.each do |time, owner, prefix, route|
        lines << "CYCLE #{time} #{owner} #{Topology.prefix_text(prefix)} #{Report.route_text(route)}"
        oscillations[[owner, prefix]] += 1
      end
      oscillations.sort.each do |(owner, prefix), count|
        lines << "OSCILLATE #{owner} #{Topology.prefix_text(prefix)} changes #{count}"
      end
    end
    lines << "SUMMARY loops #{totals['LOOP']} blackholes #{totals['BLACKHOLE']} rings #{@ring_records.length} " \
             "routes #{routes} valleys #{valleys} divergent #{divergent} end #{@time}"
    lines
  end

  def write_outputs
    convergence = @periods.map do |period|
      [period.number, period.event.time, period.event.kind, period.status, period.convergence_time,
       period.counters[:updates], period.counters[:withdrawals], period.counters[:drops],
       period.counters[:best_changes], period.routes_changed, period.exploration.values.max || 0].join(',')
    end
    Report.write('updates.txt' => @logs, 'convergence.csv' => [CONVERGENCE_HEADER] + convergence,
                 'ribs.txt' => rib_lines, 'paths.txt' => path_lines, 'audit.txt' => audit_lines)
  end
end

if $PROGRAM_NAME == __FILE__
  network, policies, events = Topology.read, Policy.read, Simulator.read_events
  simulation = Simulation.new(network, policies, *Simulator.read_params)
  simulation.run(events)
  simulation.write_outputs
end
