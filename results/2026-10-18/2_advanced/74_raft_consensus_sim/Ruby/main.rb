require_relative 'cluster'
require_relative 'minstd'
require_relative 'network'
require_relative 'raft_node'
require_relative 'checker'

class Simulator
  def initialize(settings, controls, requests, network)
    @settings, @requests, @network = settings, requests, network
    @nodes = (1..settings.nodes).map { |number| RaftNode.new(number) }
    @random = Minstd.new(settings.seed)
    @checker = Checker.new
    @controls = controls.group_by(&:time)
    @attempts = Hash.new { |hash, time| hash[time] = [] }
    requests.each { |request| @attempts[request.scheduled] << request }
    @time = 0
    @trace, @elections, @timelines, @gaps = [], [], [], []
    @leaders = {}
    @leader_ticks = @multi_ticks = 0
    @gap_start = nil
  end

  def node(number) = @nodes[number - 1]
  def majority?(count) = 2 * count > @settings.nodes
  def node_set(numbers) = numbers.empty? ? '-' : numbers.sort.map { |number| "n#{number}" }.join(',')
  def trace(content) = @trace << "#{@time} #{content}"
  def command_text(command) = command.join(' ')

  def set_election_timer(node)
    node.election_deadline = @time + @random.between(@settings.election_min, @settings.election_max)
  end

  def send_message(node, destination, kind, data = {})
    @network.send(@time, node.number, destination, node.term, kind, data)
  end

  def send_append(node, destination)
    previous = node.next_index[destination] - 1
    send_message(node, destination, 'AE', {
      previous: previous, previous_term: node.term_at(previous),
      entries: node.log.slice(previous, @settings.batch).dup, commit: node.commit
    })
  end

  def broadcast_append(node)
    @nodes.each { |other| send_append(node, other.number) unless other.equal?(node) }
  end

  def end_leadership(node, reason)
    @leaders[node.term].merge!(ended: @time, reason: reason, commit: node.commit)
    node.cancel_transfer
  end

  def control(event)
    arguments = event.arguments
    case event.kind
    when 'CRASH'
      current = node(arguments[0])
      trace("CRASH n#{current.number} #{current.role} term #{current.term}")
      end_leadership(current, 'CRASH') if current.role == 'LEADER'
      current.crash
    when 'RESTART'
      current = node(arguments[0])
      current.up = true
      set_election_timer(current)
      trace("RESTART n#{current.number} term #{current.term} length #{current.last_index} deadline #{current.election_deadline}")
    when 'PARTITION'
      @network.partition(arguments)
      trace('PARTITION ' + arguments.map { |group| node_set(group) }.join(' '))
    when 'HEAL'
      @network.heal
      trace('HEAL')
    when 'TRANSFER'
      start_transfer(node(arguments[0]), arguments[1])
    end
  end

  def attempt(request)
    request.attempts += 1
    destination = request.destination
    redirected = 0
    current = nil
    reason = nil
    loop do
      current = node(destination)
      if !current.up
        reason = 'down'
        break
      elsif current.role == 'LEADER'
        if current.transfer_target
          reason = 'transfer'
          break
        end
        current.log << Entry.new(current.term, request.command, request.number)
        @leaders[current.term][:appended] += 1
        request.accepted = [current.last_index, current.term]
        request.scheduled = nil
        trace("ACCEPT r#{request.number} n#{current.number} index #{current.last_index} term #{current.term}")
        return
      elsif current.known_leader.nil? || redirected >= @settings.nodes - 1
        reason = 'noleader'
        break
      end
      destination = current.known_leader
      trace("REDIRECT r#{request.number} n#{current.number} n#{destination}")
      redirected += 1
      request.redirects += 1
    end
    prefix = "REJECT r#{request.number} n#{current.number} #{reason}"
    if request.attempts < @settings.attempts
      request.destination = current.number % @settings.nodes + 1
      request.scheduled = @time + @settings.retry
      @attempts[request.scheduled] << request
      trace("#{prefix} retry n#{request.destination} at #{request.scheduled}")
    else
      request.abandoned = true
      request.scheduled = nil
      trace(prefix + ' giveup')
    end
  end

  def start_election(node, trigger)
    node.term += 1
    node.role = 'CANDIDATE'
    node.voted_for = node.number
    node.votes = Set[node.number]
    node.known_leader = nil
    set_election_timer(node)
    node.stats['elections'] += 1
    node.election_record = { time: @time, node: node.number, term: node.term,
                             trigger: trigger, votes: node.votes, won: nil }
    @elections << node.election_record
    trace("ELECTION n#{node.number} term #{node.term} last #{node.last_index}/#{node.last_term} deadline #{node.election_deadline}")
    @nodes.each do |other|
      next if other.equal?(node)
      send_message(node, other.number, 'RV', { last_index: node.last_index, last_term: node.last_term })
    end
  end

  def vote_request(node, message)
    reason = if message.term < node.term
               'term'
             elsif node.voted_for && node.voted_for != message.source
               'voted'
             elsif !node.accepts_log(message.data[:last_index], message.data[:last_term])
               'log'
             end
    if reason
      trace("DENY n#{node.number} n#{message.source} term #{node.term} #{reason}")
    else
      node.voted_for = message.source
      node.stats['votes_granted'] += 1
      set_election_timer(node)
      trace("VOTE n#{node.number} n#{message.source} term #{node.term} deadline #{node.election_deadline}")
    end
    send_message(node, message.source, 'RVR', { granted: reason.nil? })
  end

  def vote_response(node, message)
    return unless node.role == 'CANDIDATE' && message.term == node.term && message.data[:granted]
    node.votes.add(message.source)
    become_leader(node) if majority?(node.votes.length)
  end

  def become_leader(node)
    node.role = 'LEADER'
    node.known_leader = node.number
    node.next_index = @nodes.reject { |other| other.equal?(node) }.to_h { |other| [other.number, node.last_index + 1] }
    node.match = node.next_index.transform_values { 0 }
    node.log << Entry.new(node.term, ['NOOP'].freeze, 0)
    node.stats['leader_terms'] += 1
    node.election_record[:won] = @time
    @checker.leader(node)
    @leaders[node.term] = { node: node.number, elected: @time, votes: node.votes.dup,
                            appended: 1, ended: nil, reason: nil, commit: nil }
    trace("LEADER n#{node.number} term #{node.term} votes #{node_set(node.votes)} noop #{node.last_index}")
    broadcast_append(node)
    node.heartbeat_deadline = @time + @settings.heartbeat
    node.quorum_deadline = @time + @settings.quorum
    node.heard = Set.new
  end

  def truncate(node, first)
    removed = node.log.slice!(first - 1..)
    node.stats['truncated'] += removed.length
    @checker.truncate(first, removed)
    trace("TRUNCATE n#{node.number} from #{first} removed #{removed.length}")
  end

  def append_request(node, message)
    if message.term < node.term
      send_message(node, message.source, 'AER', { success: false, match: 0 })
      return
    end
    if node.role == 'CANDIDATE'
      node.role = 'FOLLOWER'
      trace("YIELD n#{node.number} term #{node.term} n#{message.source}")
    end
    node.known_leader = message.source
    set_election_timer(node)
    previous = message.data[:previous]
    if previous > node.last_index || node.term_at(previous) != message.data[:previous_term]
      node.stats['ae_fail'] += 1
      hint = previous > node.last_index ? node.last_index : previous - 1
      send_message(node, message.source, 'AER', { success: false, match: hint })
      return
    end
    node.stats['ae_ok'] += 1
    message.data[:entries].each_with_index do |entry, offset|
      index = previous + offset + 1
      truncate(node, index) if index <= node.last_index && node.term_at(index) != entry.term
      if index > node.last_index
        node.log << entry
        node.stats['appended'] += 1
      end
    end
    confirmed = previous + message.data[:entries].length
    commit = [message.data[:commit], confirmed].min
    advance_commit(node, commit) if commit > node.commit
    send_message(node, message.source, 'AER', { success: true, match: confirmed })
  end

  def append_response(node, message)
    return unless node.role == 'LEADER' && message.term == node.term
    source, confirmed = message.source, message.data[:match]
    node.heard.add(source)
    if message.data[:success]
      node.match[source] = [node.match[source], confirmed].max
      node.next_index[source] = [node.next_index[source], confirmed + 1].max
      check_commit(node)
      if source == node.transfer_target && !node.transfer_sent && node.match[source] == node.last_index
        send_timeout_now(node)
      elsif node.next_index[source] <= node.last_index
        send_append(node, source)
      end
    else
      node.next_index[source] = [node.match[source] + 1, [node.next_index[source] - 1, confirmed + 1].min].max
      trace("BACKTRACK n#{node.number} n#{source} next #{node.next_index[source]}")
      send_append(node, source)
    end
  end

  def check_commit(node)
    node.last_index.downto(node.commit + 1) do |index|
      return if node.term_at(index) != node.term
      next unless majority?(1 + node.match.values.count { |confirmed| confirmed >= index })
      trace("COMMIT n#{node.number} #{node.commit + 1}-#{index} term #{node.term}")
      advance_commit(node, index)
      return
    end
  end

  def advance_commit(node, index)
    (node.commit + 1..index).each { |position| @checker.commit(position, node.term_at(position), @time) }
    node.commit = index
    first = node.applied + 1
    (first..index).each do |position|
      entry = node.log[position - 1]
      result = RaftNode.apply_command(node.store, entry.command)
      node.stats['applies'] += 1
      @checker.apply(position, entry, result)
    end
    node.applied = index
    trace("APPLY n#{node.number} #{first}-#{index}")
  end

  def receive(message)
    current = node(message.destination)
    if message.term > current.term
      role = current.role
      trace("TERM n#{current.number} #{current.term}->#{message.term} #{message.kind} n#{message.source} #{role}")
      end_leadership(current, 'STEPDOWN') if role == 'LEADER'
      current.term = message.term
      current.voted_for = current.known_leader = nil
      current.role = 'FOLLOWER'
      set_election_timer(current) if role == 'LEADER'
    end
    case message.kind
    when 'RV' then vote_request(current, message)
    when 'RVR' then vote_response(current, message)
    when 'AE' then append_request(current, message)
    when 'AER' then append_response(current, message)
    when 'TN'
      if message.term != current.term || current.role != 'FOLLOWER'
        trace("IGNORE n#{current.number} TN n#{message.source} term #{message.term}")
      else
        start_election(current, 'transfer')
      end
    end
  end

  def start_transfer(node, destination)
    prefix = "TRANSFER n#{node.number} n#{destination}"
    if !node.up || node.role != 'LEADER' || node.transfer_target || node.number == destination
      trace(prefix + ' ignored')
      return
    end
    trace("#{prefix} start match #{node.match[destination]}/#{node.last_index}")
    node.transfer_target = destination
    node.transfer_sent = false
    node.transfer_deadline = @time + @settings.election_min
    node.match[destination] == node.last_index ? send_timeout_now(node) : send_append(node, destination)
  end

  def send_timeout_now(node)
    trace("TIMEOUTNOW n#{node.number} n#{node.transfer_target} term #{node.term} index #{node.last_index}")
    node.transfer_sent = true
    send_message(node, node.transfer_target, 'TN')
  end

  def timers(node)
    if node.role != 'LEADER'
      start_election(node, 'timeout') if node.election_deadline == @time
      return
    end
    if node.quorum_deadline == @time
      unless majority?(1 + node.heard.length)
        trace("STEPDOWN n#{node.number} term #{node.term} heard #{node_set(node.heard)}")
        end_leadership(node, 'QUORUM')
        node.role = 'FOLLOWER'
        node.known_leader = nil
        set_election_timer(node)
        return
      end
      node.heard = Set.new
      node.quorum_deadline = @time + @settings.quorum
    end
    if node.transfer_target && node.transfer_deadline == @time
      trace("TRANSFER n#{node.number} n#{node.transfer_target} abort")
      node.cancel_transfer
    end
    if node.heartbeat_deadline == @time
      broadcast_append(node)
      node.heartbeat_deadline = @time + @settings.heartbeat
    end
  end

  def end_of_tick
    @checker.check_logs(@nodes)
    leaders = @nodes.select { |node| node.up && node.role == 'LEADER' }
    leaders.each { |node| node.stats['leader_ticks'] += 1 }
    if leaders.empty?
      @gap_start ||= @time
    else
      @leader_ticks += 1
      @multi_ticks += 1 if leaders.length >= 2
      if @gap_start
        @gaps << [@gap_start, @time - 1]
        @gap_start = nil
      end
    end
    if (@time % @settings.sample).zero?
      fields = @nodes.map { |node| "#{node.up ? node.role[0] : 'D'}#{node.term}" }
      @timelines << "TIMELINE #{@time} #{fields.join(' ')}"
    end
  end

  def run
    @nodes.each do |node|
      set_election_timer(node)
      trace("START n#{node.number} deadline #{node.election_deadline}")
    end
    (0..@settings.end_time).each do |time|
      @time = time
      (@controls[time] || []).each { |event| control(event) }
      (@attempts.delete(time) || []).sort_by(&:number).each { |request| attempt(request) }
      @network.arrivals(time).each do |message|
        receive(message) if @network.deliver(message, node(message.destination).up)
      end
      @nodes.each { |node| timers(node) if node.up }
      end_of_tick
    end
    @gaps << [@gap_start, @settings.end_time] if @gap_start
    finish_statistics
  end

  def finish_statistics
    @maximum_term = @nodes.map(&:term).max
    @committed_count = @checker.committed.length
    needed = @nodes.map(&:applied).to_set
    @reference_states = { 0 => {} }
    @reference_state = {}
    (1..@committed_count).each do |index|
      RaftNode.apply_command(@reference_state, @checker.applied[index][0].command)
      @reference_states[index] = @reference_state.dup if needed.include?(index)
    end
    @status_counts, @key_requests, @key_committed = Hash.new(0), Hash.new(0), Hash.new(0)
    @latencies = []
    @requests.each do |request|
      key = request.command[1]
      @key_requests[key] += 1
      if request.accepted
        index, term = request.accepted
        committed = @checker.committed[index]
        if committed && committed[0] == term
          request.status = 'COMMITTED'
          request.latency = committed[1] - request.time
          request.result = @checker.applied[index][1]
          @latencies << request.latency
          @key_committed[key] += 1
        elsif @nodes.any? { |node| node.last_index >= index && node.term_at(index) == term }
          request.status = 'UNCOMMITTED'
        else
          request.status = 'LOST'
        end
      else
        request.status = request.abandoned ? 'FAILED' : 'WAITING'
      end
      @status_counts[request.status] += 1
    end
  end

  def leader_lines
    lines = @elections.map do |record|
      outcome = record[:won] ? "WON #{record[:won]}" : 'LOST'
      "ELECTION #{record[:time]} n#{record[:node]} term #{record[:term]} trigger #{record[:trigger]} votes #{record[:votes].length} #{outcome}"
    end
    by_term = @elections.group_by { |record| record[:term] }
    (1..@maximum_term).each do |term|
      elections = by_term.fetch(term, [])
      candidates = node_set(elections.map { |record| record[:node] }.uniq)
      record = @leaders[term]
      unless record
        lines << "TERM #{term} NONE candidates #{candidates}"
        next
      end
      ended = record[:ended] || '-'
      reason = record[:reason] || 'ACTIVE'
      commit = record[:ended] ? record[:commit] : node(record[:node]).commit
      start = elections.first[:time]
      lines << "TERM #{term} LEADER n#{record[:node]} elected #{record[:elected]} votes #{node_set(record[:votes])} ended #{ended} #{reason} appended #{record[:appended]} commit #{commit} candidates #{candidates} started #{start} wait #{record[:elected] - start}"
    end
    @nodes.each do |node|
      stats = node.stats
      lines << "NODE n#{node.number} elections #{stats['elections']} leader_terms #{stats['leader_terms']} leader_ticks #{stats['leader_ticks']} votes_granted #{stats['votes_granted']}"
    end
    lines.concat(@timelines)
    @gaps.each { |first, last| lines << "GAP #{first}-#{last} length #{last - first + 1}" }
    longest = @gaps.map { |first, last| last - first + 1 }.max || 0
    lines << "SUMMARY terms #{@maximum_term} leaders #{@leaders.length} elections #{@elections.length} leader_ticks #{@leader_ticks} multi_ticks #{@multi_ticks} ticks #{@settings.end_time + 1} gaps #{@gaps.length} longest #{longest}"
    lines
  end

  def log_lines
    lines = []
    @nodes.each do |node|
      voted = node.voted_for ? "n#{node.voted_for}" : '-'
      lines << "NODE n#{node.number} #{node.up ? node.role : 'DOWN'} term #{node.term} voted #{voted} commit #{node.commit} applied #{node.applied} length #{node.last_index}"
      node.log.each_with_index do |entry, offset|
        text = "#{offset + 1} #{entry.term} #{command_text(entry.command)}"
        text += " r#{entry.request}" unless entry.request.zero?
        lines << text
      end
    end
    prefix = 0
    @nodes.map(&:last_index).min.times do |index|
      break unless @nodes.all? { |node| node.log[index] == @nodes.first.log[index] }
      prefix += 1
    end
    lines << "AGREE prefix #{prefix} committed #{@committed_count}"
    @nodes.each do |node|
      common = 0
      (1..[node.last_index, @committed_count].min).each do |index|
        break if node.term_at(index) != @checker.committed[index][0]
        common = index
      end
      stats = node.stats
      lines << "DIFF n#{node.number} common #{common} behind #{@committed_count - common} extra #{node.last_index - common} ae_ok #{stats['ae_ok']} ae_fail #{stats['ae_fail']} appended #{stats['appended']} truncated #{stats['truncated']} applies #{stats['applies']}"
    end
    lines
  end

  def request_line(request)
    line = "REQUEST r#{request.number} at #{request.time} n#{request.initial_destination} #{command_text(request.command)} attempts #{request.attempts} redirects #{request.redirects} "
    if request.accepted
      index, term = request.accepted
      line += "#{request.status} index #{index} term #{term}"
      line += " latency #{request.latency} result #{request.result}" if request.status == 'COMMITTED'
    elsif request.status == 'FAILED'
      line += 'FAILED'
    else
      line += "WAITING next #{request.scheduled}"
    end
    line
  end

  def state_lines
    lines = []
    @nodes.each do |node|
      replay = node.store == @reference_states[node.applied] ? 'match' : 'mismatch'
      lines << "NODE n#{node.number} #{node.up ? 'UP' : 'DOWN'} applied #{node.applied} keys #{node.store.length} replay #{replay}"
      node.store.keys.sort.each { |key| lines << "#{key} #{node.store[key]}" }
    end
    lines.concat(@requests.map { |request| request_line(request) })
    @key_requests.keys.sort.each do |key|
      lines << "KEY #{key} requests #{@key_requests[key]} committed #{@key_committed[key]} final #{@reference_state.fetch(key, 'missing')}"
    end
    statuses = %w[COMMITTED UNCOMMITTED LOST FAILED WAITING].map { |name| "#{name.downcase} #{@status_counts[name]}" }.join(' ')
    lines << "REQUESTS total #{@requests.length} #{statuses}"
    lines << "LATENCY count #{@latencies.length} total #{@latencies.sum} min #{@latencies.min || 0} max #{@latencies.max || 0}"
    lines
  end

  def safety_lines
    lines = @checker.lines(@maximum_term)
    lines << 'MESSAGES ' + Network::FIELDS.map { |field| "#{field} #{@network.total[field]}" }.join(' ')
    Network::TYPES.each do |kind|
      lines << "TYPE #{kind} " + Network::FIELDS.map { |field| "#{field} #{@network.by_type[kind][field]}" }.join(' ')
    end
    @network.links.each do |(source, destination), link|
      dropped = Network::REASONS.sum { |reason| link.stats[reason] }
      lines << "LINK n#{source}->n#{destination} delay #{link.delay} loss #{link.loss} sent #{link.stats['sent']} delivered #{link.stats['delivered']} dropped #{dropped}"
    end
    lines << "DRAWS #{@random.draws}"
    lines << (@checker.violations.values.any?(&:positive?) ? 'RESULT UNSAFE' : 'RESULT SAFE')
    lines
  end

  def write_outputs
    Dir.mkdir('output') unless Dir.exist?('output')
    { 'trace.txt' => @trace, 'leaders.txt' => leader_lines, 'logs.txt' => log_lines,
      'state.txt' => state_lines, 'safety.txt' => safety_lines }.each do |filename, lines|
      File.write(File.join('output', filename), lines.join("\n") + "\n")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  settings = Cluster.read_settings
  controls, requests = Cluster.read_script
  simulation = Simulator.new(settings, controls, requests, Network.new(settings.nodes))
  simulation.run
  simulation.write_outputs
end
