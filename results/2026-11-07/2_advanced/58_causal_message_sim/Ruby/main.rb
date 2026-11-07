require 'fileutils'
require_relative 'network'
require_relative 'clocks'
require_relative 'processes'
require_relative 'snapshot'
require_relative 'analysis'

def load_params
  params = { compare: [], cuts: [], predicates: [] }
  File.foreach('input/params.txt') do |line|
    key, *args = line.split
    case key
    when 'COMPARE' then params[:compare] << args
    when 'CUT' then params[:cuts] << args.map(&:to_i)
    when 'PREDICATE' then params[:predicates] << args[0].to_i
    else params[key.downcase.to_sym] = args[0].to_i
    end
  end
  params
end

def yes(value) = value ? 'yes' : 'no'
def message_name(message) = "m#{message[:id]}"

class Simulation
  attr_reader :names, :indices, :params, :processes, :channels, :channel_order,
              :random, :messages, :copies, :events, :snapshots, :timeline

  def initialize(names, channels, scripts, params, raw: false)
    @names, @params, @raw = names, params, raw
    @indices = names.each_with_index.to_h
    @processes = Processes.initialize_states(names, scripts)
    @channels = channels.transform_values { |channel| channel.merge(previous: channel[:previous].dup) }
    @channel_order = channels.keys.sort_by { |a, b| [@indices[a], @indices[b]] }
    @random = Minstd.new(params[:seed])
    @queue, @messages, @copies, @events, @snapshots, @timeline = [], [], [], [], [], []
    @snapshot_by_name = {}
    @creation = @time = 0
    Processes.schedule(names, @processes, params[:end]) { |*item| enqueue(*item) }
  end

  def enqueue(time, destination, kind, payload)
    @creation += 1
    @queue << [time, @indices[destination], @creation, destination, kind, payload]
  end

  def dispatch(source, destination, packet)
    Network.dispatch(@channels, source, destination, packet, @time, @random) { |*item| enqueue(*item) }
  end

  def record_event(process, type, details, sender = nil)
    Clocks.advance(process, @indices[process[:name]], sender)
    event = { number: @events.size + 1, local: process[:events].size + 1,
      process: process[:name], type: type, details: details, time: @time,
      lamport: process[:lamport], vector: process[:vector].dup,
      balance: process[:balance], process_events: process[:events] }
    event[:name] = "#{event[:process]}.#{event[:local]}"
    process[:events] << event
    process[:counts][type] += 1
    process[:min_balance] = [process[:min_balance], process[:balance]].min
    @events << event
    @timeline << [:event, event]
    event
  end

  def action(name, action, sender = nil)
    process = @processes[name]
    kind, destination, value = action
    case kind
    when 'LOCAL'
      record_event(process, 'LOCAL', label: destination)
    when 'SNAPSHOT'
      snapshot = @snapshot_by_name[destination]
      unless snapshot
        snapshot = Snapshots.create(destination, @time, @channel_order)
        @snapshots << snapshot
        @snapshot_by_name[destination] = snapshot
      end
      if snapshot[:records].key?(name)
        snapshot[:ignored] << [name, @time]
      else
        record_snapshot(snapshot, name, 'initiate')
      end
    else
      destination = sender if destination == 'SENDER'
      broadcast = kind == 'BROADCAST'
      amount = kind == 'TRANSFER' ? value : 0
      if amount > process[:balance]
        process[:refused] += 1
        record_event(process, 'NOFUNDS', destination: destination, amount: amount)
        return
      end
      process[:balance] -= amount
      process[:outgoing] += amount
      process[:broadcast][@indices[name]] += 1 if broadcast
      message = { id: @messages.size + 1, source: name, kind: broadcast ? 'BCAST' : 'P2P',
        tag: broadcast ? action[1] : kind == 'TRANSFER' ? 'transfer' : value,
        amount: amount, stamp: broadcast ? process[:broadcast].dup : nil, copies: [], send_time: @time }
      @messages << message
      sending = record_event(process, broadcast ? 'BCAST' : 'SEND', message: message, destination: destination)
      message[:send_event] = sending
      targets = broadcast ? @names.reject { |target| target == name } : [destination]
      targets.each do |target|
        copy = { message: message, kind: message[:kind], tag: message[:tag], amount: amount,
          send_event: sending, stamp: message[:stamp], fifo_wait: false, causal_wait: false,
          missing: [], recv_event: nil }
        @copies << copy
        message[:copies] << copy
        dispatch(name, target, copy)
      end
    end
  end

  def record_snapshot(snapshot, name, reason)
    Snapshots.record(snapshot, @processes[name], @time, reason)
    @timeline << [:snapshot, { name: snapshot[:name], process: name, time: @time }]
    @names.each do |target|
      next if target == name
      snapshot[:markers][[name, target]] = { sent: @time, accepted: nil }
      dispatch(name, target, marker: snapshot[:name])
    end
  end

  def deliver(name, copy)
    process = @processes[name]
    process[:broadcast][@indices[copy[:source]]] += 1 if copy[:kind] == 'BCAST'
    process[:balance] += copy[:amount]
    process[:incoming] += copy[:amount]
    copy[:recv_event] = record_event(process, 'RECV', { copy: copy }, copy[:send_event])
    copy[:delivery] = @time
    process[:delivered] << copy
    process[:on].each { |tag, reaction| action(name, reaction, copy[:source]) if tag == copy[:tag] }
  end

  def deliverable?(name, copy)
    Clocks.deliverable?(copy[:stamp], @processes[name][:broadcast], @indices[copy[:source]])
  end

  def accept(name, packet)
    process = @processes[name]
    source = packet[:source]
    pair = [source, name]
    process[:next_sequence][source] += 1
    if packet[:marker]
      snapshot = @snapshot_by_name.fetch(packet[:marker])
      record_snapshot(snapshot, name, "marker #{source}") unless snapshot[:records].key?(name)
      Snapshots.accept_marker(snapshot, pair, @time)
      return
    end
    @snapshots.each do |snapshot|
      snapshot[:states][pair] << packet if snapshot[:records].key?(name) && !snapshot[:accepted].key?(pair)
    end
    if @raw || packet[:kind] == 'P2P'
      deliver(name, packet)
    elsif deliverable?(name, packet)
      deliver(name, packet)
      while (position = process[:holdback].index { |copy| deliverable?(name, copy) })
        deliver(name, process[:holdback].delete_at(position))
      end
    else
      packet[:causal_wait] = true
      packet[:missing] = Clocks.missing(packet[:stamp], process[:broadcast], @indices[source])
      process[:holdback] << packet
    end
  end

  def arrival(name, packet)
    process = @processes[name]
    source = packet[:source]
    if @raw
      accept(name, packet)
    elsif packet[:sequence] != process[:next_sequence][source]
      packet[:fifo_wait] = true
      process[:reorder][source][packet[:sequence]] = packet
      @channels[[source, name]][:buffered] += 1
    else
      accept(name, packet)
      buffer = process[:reorder][source]
      while (following = buffer.delete(process[:next_sequence][source]))
        accept(name, following)
      end
    end
    process[:max_held] = [process[:max_held], Processes.held_count(process)].max
  end

  def run
    until @queue.empty?
      position = @queue.each_index.min_by { |i| @queue[i].first(3) }
      time, _, _, name, kind, payload = @queue.delete_at(position)
      break if time > @params[:end]
      @time = time
      kind == :action ? action(name, payload) : arrival(name, payload)
    end
    self
  end

  def initial_total = @names.sum { |name| @processes[name][:initial] }
end

def event_line(event)
  details = event[:details]
  type = event[:type]
  info = case type
         when 'LOCAL' then details[:label]
         when 'NOFUNDS' then "to #{details[:destination]} amount #{details[:amount]} balance #{event[:balance]}"
         when 'SEND', 'BCAST'
           message = details[:message]
           text = message_name(message)
           text += " to #{details[:destination]}" if type == 'SEND'
           text += " tag #{message[:tag]}"
           text += " amount #{message[:amount]} balance #{event[:balance]}" if message[:amount].positive?
           text
         when 'RECV'
           copy = details[:copy]
           text = "#{message_name(copy[:message])} from #{copy[:source]} tag #{copy[:tag]}"
           text += " amount #{copy[:amount]} balance #{event[:balance]}" if copy[:amount].positive?
           text
         end
  "#{event[:number]} t=#{event[:time]} #{event[:name]} #{type} #{info} L=#{event[:lamport]} V=#{Clocks.text(event[:vector])}"
end

def trace_lines(sim)
  lines = sim.events.map { |event| event_line(event) }
  delivered = sim.copies.count { |copy| copy[:recv_event] }
  lines << "SUMMARY events #{sim.events.size} messages #{sim.messages.size} copies #{sim.copies.size} delivered #{delivered} undelivered #{sim.copies.size - delivered} draws #{sim.random.draws}"
  sim.names.each do |name|
    p = sim.processes[name]
    lines << "FINAL #{name} events #{p[:events].size} L=#{p[:lamport]} V=#{Clocks.text(p[:vector])} B=#{Clocks.text(p[:broadcast])} balance #{p[:balance]} in #{p[:incoming]} out #{p[:outgoing]} refused #{p[:refused]} min #{p[:min_balance]}"
  end
  sim.names.each do |name|
    c = sim.processes[name][:counts]
    lines << "COUNTS #{name} local #{c['LOCAL']} nofunds #{c['NOFUNDS']} send #{c['SEND']} bcast #{c['BCAST']} recv #{c['RECV']}"
  end
  lines
end

def history(process)
  process[:events].filter_map do |event|
    if event[:type] == 'BCAST'
      message_name(event[:details][:message])
    elsif event[:type] == 'RECV' && event[:details][:copy][:kind] == 'BCAST'
      message_name(event[:details][:copy][:message])
    end
  end
end

def missing_text(copy, sim) = copy[:missing].map { |i| sim.names[i] }.join(',')

def wait_mode(copy, sim)
  return copy[:fifo_wait] ? 'fifo' : 'direct' unless copy[:causal_wait]
  "#{copy[:fifo_wait] ? 'fifo+causal' : 'causal'} #{missing_text(copy, sim)}"
end

def deliveries_lines(sim)
  lines = []
  sim.names.each do |name|
    p = sim.processes[name]
    lines << "PROCESS #{name}"
    modes = Hash.new(0)
    waits = []
    p[:delivered].each_with_index do |copy, i|
      wait = copy[:delivery] - copy[:arrival]
      waits << wait
      mode = copy[:fifo_wait] ? (copy[:causal_wait] ? :both : :fifo) : (copy[:causal_wait] ? :causal : :direct)
      modes[mode] += 1
      lines << "#{i + 1} #{message_name(copy[:message])} from #{copy[:source]} #{copy[:kind]} tag #{copy[:tag]} sent #{copy[:message][:send_time]} arrived #{copy[:arrival]} delivered #{copy[:delivery]} wait #{wait} #{wait_mode(copy, sim)}"
    end
    addressed = sim.copies.select { |copy| copy[:destination] == name }
    addressed.each do |copy|
      next if copy[:arrival] > sim.params[:end] || copy[:recv_event]
      place = p[:reorder][copy[:source]].key?(copy[:sequence]) ? 'fifo' : "causal #{missing_text(copy, sim)}"
      lines << "HELD #{message_name(copy[:message])} from #{copy[:source]} #{copy[:kind]} tag #{copy[:tag]} sent #{copy[:message][:send_time]} arrived #{copy[:arrival]} #{place}"
    end
    addressed.each do |copy|
      next unless copy[:arrival] > sim.params[:end]
      lines << "TRANSIT #{message_name(copy[:message])} from #{copy[:source]} #{copy[:kind]} tag #{copy[:tag]} sent #{copy[:message][:send_time]} arrival #{copy[:arrival]}"
    end
    lines << "TOTAL delivered #{p[:delivered].size} direct #{modes[:direct]} fifo #{modes[:fifo]} causal #{modes[:causal]} both #{modes[:both]} wait #{waits.sum} max_wait #{waits.max || 0} max_held #{p[:max_held]}"
    broadcasts = history(p)
    lines << "BCASTS #{broadcasts.empty? ? 'none' : broadcasts.join(' ')}"
  end
  sim.channel_order.each do |pair|
    c = sim.channels[pair]
    lines << "CHANNEL #{pair.join('->')} #{c[:kind]} #{Network.delay_text(c)} messages #{c[:messages]} markers #{c[:markers]} buffered #{c[:buffered]} max_delay #{c[:max_delay]} entries #{c[:entries]}"
  end
  sim.copies.group_by { |copy| copy[:tag] }.sort.each do |tag, copies|
    latencies = copies.filter_map { |copy| copy[:delivery] - copy[:message][:send_time] if copy[:recv_event] }
    lines << "TAG #{tag} copies #{copies.size} delivered #{latencies.size} latency #{latencies.sum} max #{latencies.max || 0}"
  end
  broadcasts = sim.messages.select { |message| message[:kind] == 'BCAST' }
  broadcasts.each do |message|
    copies = message[:copies]
    stable = copies.all? { |copy| copy[:recv_event] } ? copies.map { |copy| copy[:delivery] }.max : 'none'
    lines << "STABLE #{message_name(message)} #{message[:source]} tag #{message[:tag]} sent #{message[:send_time]} stable #{stable}"
  end
  disagreements = 0
  broadcasts.combination(2) do |a, b|
    earlier, later = [], []
    sim.names.each do |name|
      h = history(sim.processes[name])
      x, y = h.index(message_name(a)), h.index(message_name(b))
      next unless x && y
      (x < y ? earlier : later) << name
    end
    next if earlier.empty? || later.empty?
    disagreements += 1
    lines << "DISAGREE #{message_name(a)} #{message_name(b)} #{earlier.join(',')} #{later.join(',')}"
  end
  lines << "DISAGREEMENTS #{disagreements}"
end

def verdict(details)
  details[:orphans].empty? ? 'yes' : "no #{details[:orphans].map { |copy| Snapshots.copy_label(copy) }.join(' ')}"
end

def snapshots_lines(normal, raw)
  lines = []
  [normal, raw].each do |sim|
    sim.snapshots.each do |snap|
      cut = Snapshots.cut(snap, sim.names)
      details = Snapshots.details(cut, sim.names, sim.processes, sim.copies)
      entries = sim.channel_order.flat_map { |pair| snap[:states][pair] }
      pending = sim.names.flat_map { |name| snap[:records][name][:pending] }
      balances = snap[:records].values.sum { |record| record[:balance] }
      channel_money = entries.sum { |copy| copy[:amount] }
      money = balances + channel_money
      if sim.equal?(raw)
        lines << "RAW #{snap[:name]} completed #{snap[:complete]} cut #{Clocks.text(cut)} consistent #{verdict(details)} money #{money} conserved #{yes(money == sim.initial_total)}"
        next
      end
      lines << "SNAPSHOT #{snap[:name]} started #{snap[:start]} completed #{snap[:complete]}"
      sim.names.each do |name|
        r = snap[:records][name]
        pending_text = r[:pending].map { |copy| message_name(copy[:message]) }
        lines << "RECORD #{name} t=#{r[:time]} #{r[:reason]} balance #{r[:balance]} L=#{r[:lamport]} V=#{Clocks.text(r[:vector])} pending #{pending_text.empty? ? 'none' : pending_text.join(' ')}"
      end
      sim.channel_order.each do |pair|
        values = snap[:states][pair].map { |copy| message_name(copy[:message]) + (copy[:amount].zero? ? '' : ":#{copy[:amount]}") }
        marker = snap[:markers][pair]
        lines << "CHANNEL #{pair.join('->')} marker #{marker[:sent]} #{marker[:accepted]} state #{values.empty? ? 'empty' : values.join(' ')}"
      end
      snap[:ignored].each { |name, time| lines << "IGNORED #{name} t=#{time}" }
      vector_ok = snap[:records].values.all? { |r| r[:vector].each_with_index.all? { |value, i| value <= cut[i] } }
      lines << "CUT #{Clocks.text(cut)} consistent #{verdict(details)} vector #{yes(vector_ok)}"
      lines << "TRANSIT channels #{entries.size} pending #{pending.size} cut #{details[:transit].size} match #{yes(Snapshots.same_copies?(entries + pending, details[:transit]))}"
      lines << "MONEY balances #{balances} channels #{channel_money} total #{money} initial #{sim.initial_total} conserved #{yes(money == sim.initial_total)}"
    end
  end
  lines
end

def range_notation(events)
  groups = []
  events.each do |event|
    if !groups.empty? && groups[-1][-1][:process] == event[:process] && groups[-1][-1][:local] + 1 == event[:local]
      groups[-1] << event
    else
      groups << [event]
    end
  end
  groups.map { |group| group.size == 1 ? group[0][:name] : "#{group[0][:name]}-#{group[-1][:local]}" }.join(' ')
end

def longest_chain(sim)
  current = sim.events.max_by { |event| [event[:lamport], -event[:number]] }
  return [] unless current
  chain = [current]
  while current[:lamport] > 1
    sender = current[:type] == 'RECV' ? current[:details][:copy][:send_event] : nil
    current = if sender && sender[:lamport] == current[:lamport] - 1
                sender
              else
                sim.processes[current[:process]][:events][current[:local] - 2]
              end
    chain << current
  end
  chain.reverse
end

def analysis_lines(sim, raw)
  lines = []
  indexed = sim.events.to_h { |event| [event[:name], event] }
  numbered = sim.events.to_h { |event| [event[:number], event] }
  edges = Analysis.graph(sim.events, sim.copies)
  sim.params[:compare].each do |first, second|
    a, b = indexed.fetch(first), indexed.fetch(second)
    relation = Clocks.relation(a[:vector], b[:vector])
    path = Analysis.path(a[:number], b[:number], edges)
    graph_relation = path ? '->' : '||'
    unless path
      path = Analysis.path(b[:number], a[:number], edges)
      graph_relation = '<-' if path
    end
    lines << "COMPARE #{first} #{relation} #{second} L=#{a[:lamport]},#{b[:lamport]} graph #{graph_relation} agree #{yes(relation == graph_relation)}"
    if path
      events = path.map { |number| numbered[number] }
      messages = events.each_cons(2).count { |x, y| x[:process] != y[:process] }
      lines << "PATH length #{events.size} messages #{messages} #{range_notation(events)}"
    end
    [a, b].each do |event|
      own = sim.indices[event[:process]]
      future = sim.names.map { |name| sim.processes[name][:events].count { |other| other[:vector][own] < event[:local] } }
      lines << "WINDOW #{event[:name]} past #{Clocks.text(event[:vector])} future #{Clocks.text(future)}"
    end
  end
  stats = Analysis.concurrency(sim.events, sim.indices)
  lines << "CONCURRENCY events #{sim.events.size} pairs #{stats[:pairs]} ordered #{stats[:ordered]} concurrent #{stats[:concurrent]} same_lamport #{stats[:same_lamport]} inversions #{stats[:inversions]}"
  sim.names.combination(2) { |a, b| lines << "PAIR #{a} #{b} #{stats[:by_pair][[a, b]]}" }
  chain = longest_chain(sim)
  lines << "CHAIN length #{chain.size} #{range_notation(chain)}"
  races, violations = Analysis.races_and_violations(sim.names, sim.processes)
  races.each { |name, a, b| lines << "RACE #{name} #{message_name(a[:message])} #{a[:source]} #{message_name(b[:message])} #{b[:source]}" }
  lines << "RACES #{races.size}"
  violations.each { |name, a, b| lines << "VIOLATION #{name} #{message_name(a[:message])} #{a[:source]} overtook #{message_name(b[:message])} #{b[:source]}" }
  lines << "VIOLATIONS causal #{violations.size} fifo #{violations.count { |_, a, b| a[:source] == b[:source] }}"
  _, raw_violations = Analysis.races_and_violations(raw.names, raw.processes)
  lines << "RAW events #{raw.events.size} delivered #{raw.copies.count { |copy| copy[:recv_event] }} causal #{raw_violations.size} fifo #{raw_violations.count { |_, a, b| a[:source] == b[:source] }}"
  sim.params[:cuts].each do |cut|
    d = Snapshots.details(cut, sim.names, sim.processes, sim.copies)
    state = d[:orphans].empty? ? 'consistent' : "inconsistent orphans #{d[:orphans].map { |copy| Snapshots.copy_label(copy) }.join(' ')}"
    lines << "CUT #{Clocks.text(cut)} #{state} transit #{d[:transit].size} money #{d[:money]} initial #{sim.initial_total}"
  end
  enumeration = Analysis.enumerate(sim.names, sim.processes, sim.params[:cutcount], sim.params[:predicates])
  lines << "CUTCOUNT t=#{sim.params[:cutcount]} events #{Clocks.text(enumeration[:limits])} product #{enumeration[:product]} consistent #{enumeration[:consistent]}"
  lines << "LEVELS #{enumeration[:levels].join(' ')}"
  sim.params[:predicates].each do |threshold|
    p = enumeration[:predicates][threshold]
    lines << "PREDICATE transit>=#{threshold} cuts #{p[:cuts]} possibly #{yes(p[:possibly])} definitely #{yes(p[:definitely])}"
  end
  lines
end

def diagram_header(letter, names)
  line = "    #{letter} " + ' ' * (8 * names.size - 7)
  names.each_with_index { |name, i| line[8 * i + 6, name.size] = name }
  line.rstrip
end

def diagram_entry(value, name, type, details, sim)
  columns = sim.names.each_with_index.to_h { |process, i| [process, 8 * i + 6] }
  line = value.to_s.rjust(5) + ' ' * (8 * sim.names.size - 6)
  columns.each_value { |column| line[column] = '|' }
  own = columns[name]
  line[own] = { 'LOCAL' => '*', 'NOFUNDS' => 'x', 'SEND' => 'S', 'BCAST' => 'B', 'RECV' => 'R', 'snapshot' => '#' }.fetch(type)
  if type == 'snapshot'
    line[own + 1, details[:name].size] = details[:name]
  elsif %w[SEND BCAST].include?(type)
    text = message_name(details[:message])
    line[own + 1, text.size] = text
  elsif type == 'RECV'
    copy = details[:copy]
    source = columns[copy[:source]]
    low, high = [own, source].minmax
    (low + 1...high).each { |i| line[i] = columns.value?(i) ? '+' : '-' }
    line[source < own ? high - 1 : low + 1] = source < own ? '>' : '<'
    text = message_name(copy[:message])
    line[low + 2, text.size] = text
  end
  line.rstrip
end

def diagram_lines(sim)
  lines = [diagram_header('t', sim.names)]
  sim.timeline.each do |kind, event|
    lines << diagram_entry(event[:time], event[:process], kind == :snapshot ? 'snapshot' : event[:type], kind == :snapshot ? event : event[:details], sim)
  end
  lines << diagram_header('L', sim.names)
  sim.events.sort_by { |event| [event[:lamport], sim.indices[event[:process]]] }.each do |event|
    lines << diagram_entry(event[:lamport], event[:process], event[:type], event[:details], sim)
  end
  lines
end

if $PROGRAM_NAME == __FILE__
  names, channels = Network.read_topology
  scripts = Processes.read_scripts
  params = load_params
  normal = Simulation.new(names, channels, scripts, params).run
  raw = Simulation.new(names, channels, scripts, params, raw: true).run
  FileUtils.mkdir_p('output')
  { 'trace.txt' => trace_lines(normal), 'deliveries.txt' => deliveries_lines(normal),
    'snapshots.txt' => snapshots_lines(normal, raw), 'analysis.txt' => analysis_lines(normal, raw),
    'diagram.txt' => diagram_lines(normal) }.each do |name, lines|
    File.write(File.join('output', name), lines.join("\n") + "\n", encoding: Encoding::US_ASCII)
  end
end
