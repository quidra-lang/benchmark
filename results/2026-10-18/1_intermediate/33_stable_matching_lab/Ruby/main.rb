# frozen_string_literal: true

class CommandError < StandardError
  def initialize(message)
    super("ERROR #{message}")
  end
end

class Agent
  attr_reader :name
  attr_accessor :preference, :capacity

  def initialize(name)
    @name = name.freeze
    @preference = [].freeze
    @capacity = 1
  end
end

Saved = Data.define(:source, :partners)
Run = Data.define(:partners, :count, :history)
Rotation = Data.define(:pairs)
Candidate = Data.define(:partners, :origin, :via, :cost, :regret)
Lattice = Data.define(:matchings, :rotations)

def list_text(values)
  values.empty? ? '-' : values.join(' ')
end

class Market
  attr_reader :name, :kind, :agents, :houses, :proposers
  attr_accessor :current

  def initialize(name, kind, names, proposers = 0, houses = [])
    @name = name.freeze
    @kind = kind
    @agents = names.map { |agent| Agent.new(agent) }.freeze
    @houses = houses.map(&:freeze).freeze
    @proposers = proposers
    @current = nil
  end

  def initialize_copy(other)
    super
    @agents = other.agents.map(&:dup).freeze
  end

  def require_kind(expected)
    raise CommandError, "WRONG TYPE #{@name}" unless @kind == expected
  end

  def find_agent(name)
    @agents.index { |agent| agent.name == name }
  end

  def agent(name, side = :any)
    index = find_agent(name)
    raise CommandError, "UNKNOWN AGENT #{name}" if index.nil?
    raise CommandError, "NOT PROPOSER #{name}" if side == :proposer && index >= @proposers
    raise CommandError, "NOT RECEIVER #{name}" if side == :receiver && index < @proposers
    index
  end

  def rank(a, partner)
    preference = @agents[a].preference
    index = preference.index(partner)
    index ? index + 1 : preference.length + 1
  end

  def accepts?(a, b)
    @agents[a].preference.include?(b)
  end

  def partner_name(partner)
    partner.nil? ? '*' : @agents[partner].name
  end

  def pairs(partners)
    @proposers.times.map { |p| "#{@agents[p].name}-#{partner_name(partners[p])}" }.join(' ')
  end

  def allocation_text(allocation)
    @agents.each_index.map do |a|
      house = allocation[a].nil? ? '*' : @houses[allocation[a]]
      "#{@agents[a].name}-#{house}"
    end.join(' ')
  end

  def effective(a)
    preference = @agents[a].preference
    own = preference.index(a)
    own ? preference.take(own + 1) : preference + [a]
  end

  def save(source, partners)
    @current = Saved.new(source.to_sym, partners.dup.freeze)
  end

  def deferred(reverse: false, verbose: false)
    n = @agents.length
    next_position = Array.new(n, 0)
    counts = Array.new(n, 0)
    holding = Array.new(n) { [] }
    queued = Array.new(n, false)
    queue = []
    able = ->(a) { counts[a] < @agents[a].capacity && next_position[a] < @agents[a].preference.length }
    enqueue = lambda do |a|
      if able.call(a) && !queued[a]
        queue << a
        queued[a] = true
      end
    end
    side = reverse ? (@proposers...n) : (0...@proposers)
    side.each { |a| enqueue.call(a) }
    history = []
    head = 0
    while head < queue.length
      x = queue[head]
      head += 1
      queued[x] = false
      y = @agents[x].preference[next_position[x]]
      next_position[x] += 1
      action = 'REJECT'
      held = holding[y]
      if accepts?(y, x)
        if held.length < @agents[y].capacity
          held << x
          counts[x] += 1
          action = 'HOLD'
        else
          worst = held.each_index.max_by { |i| rank(y, held[i]) }
          rejected = held[worst]
          if rank(y, x) < rank(y, rejected)
            held[worst] = x
            counts[rejected] -= 1
            counts[x] += 1
            action = "HOLD REJECT #{@agents[rejected].name}"
            enqueue.call(rejected)
          end
        end
      end
      history << "PROPOSE #{@agents[x].name} #{@agents[y].name} #{action}" if verbose
      enqueue.call(x)
    end
    partners = Array.new(@proposers)
    holding.each_with_index do |held, y|
      held.each { |x| partners[reverse ? y : x] = reverse ? x : y }
    end
    Run.new(partners.freeze, head, history.freeze)
  end

  def boston
    partners = Array.new(@proposers)
    remaining = @agents.map(&:capacity)
    rounds = @agents.take(@proposers).map { |a| a.preference.length }.max
    applications = 0
    rounds.times do |round|
      applicants = Array.new(@proposers)
      @proposers.times do |p|
        next unless partners[p].nil? && round < @agents[p].preference.length
        applicants[p] = @agents[p].preference[round]
        applications += 1
      end
      (@proposers...@agents.length).each do |r|
        @agents[r].preference.each do |p|
          next unless remaining[r].positive? && applicants[p] == r
          partners[p] = r
          remaining[r] -= 1
        end
      end
    end
    Run.new(partners.freeze, applications, [].freeze)
  end

  def rotations(partners)
    owners = Array.new(@agents.length)
    partners.each_with_index { |r, p| owners[r] = p unless r.nil? }
    successors = Array.new(@proposers)
    @proposers.times do |p|
      next if partners[p].nil?
      @agents[p].preference.drop(rank(p, partners[p])).each do |r|
        next unless accepts?(r, p) && (owners[r].nil? || rank(r, p) < rank(r, owners[r]))
        successors[p] = owners[r]
        break
      end
    end
    result = []
    covered = Array.new(@proposers, false)
    @proposers.times do |start|
      next if covered[start]
      seen = Array.new(@proposers, false)
      path = []
      p = start
      until p.nil? || seen[p]
        seen[p] = true
        path << p
        p = successors[p]
      end
      next unless p == start
      path.each { |a| covered[a] = true }
      result << Rotation.new(path.map { |a| [a, partners[a]].freeze }.freeze)
    end
    result
  end

  def candidate(partners, origin, via)
    cost = regret = 0
    partners.each_with_index do |r, p|
      next if r.nil?
      a, b = rank(p, r), rank(r, p)
      cost += a + b
      regret = [regret, a, b].max
    end
    Candidate.new(partners.freeze, origin, via, cost, regret)
  end

  def enumerate
    raise CommandError, 'NOT ONE TO ONE' if @agents.drop(@proposers).any? { |a| a.capacity != 1 }
    matchings = [candidate(deferred.partners, nil, nil)]
    numbered = []
    index = 0
    while index < matchings.length
      partners = matchings[index].partners
      rotations(partners).each do |rotation|
        number = numbered.index(rotation)
        if number.nil?
          number = numbered.length
          numbered << rotation
        end
        next_matching = partners.dup
        rotation.pairs.each_with_index do |(p, _), i|
          next_matching[p] = rotation.pairs[(i + 1) % rotation.pairs.length][1]
        end
        next if matchings.any? { |old| old.partners == next_matching }
        raise CommandError, 'TOO MANY MATCHINGS' if matchings.length == 50
        matchings << candidate(next_matching, index + 1, number + 1)
      end
      index += 1
    end
    Lattice.new(matchings.freeze, numbered.freeze)
  end

  def check(words)
    raise CommandError, "WRONG TYPE #{@name}" if @kind == :housing
    partners = Array.new(@agents.length)
    counts = Array.new(@agents.length, 0)
    words.drop(2).each do |word|
      left, right = word.split('-')
      two = @kind == :two_sided
      x = agent(left, two ? :proposer : :any)
      y = agent(right, two ? :receiver : :any)
      raise CommandError, "DUPLICATE AGENT #{left}" unless partners[x].nil?
      if two
        counts[y] += 1
        raise CommandError, "OVER CAPACITY #{right}" if counts[y] > @agents[y].capacity
      else
        raise CommandError, "DUPLICATE AGENT #{right}" if x == y || !partners[y].nil?
        partners[y] = x
      end
      partners[x] = y
    end
    unacceptable, blocking = [], []
    if @kind == :two_sided
      @proposers.times do |p|
        r = partners[p]
        unacceptable << [p, r] if !r.nil? && (!accepts?(p, r) || !accepts?(r, p))
        (@proposers...@agents.length).each do |receiver|
          next if partners[p] == receiver || !accepts?(p, receiver) || !accepts?(receiver, p) || rank(p, receiver) >= rank(p, partners[p])
          worst = @proposers.times.filter_map { |a| rank(receiver, a) if partners[a] == receiver }.max || 0
          blocking << [p, receiver] if counts[receiver] < @agents[receiver].capacity || rank(receiver, p) < worst
        end
      end
    else
      @agents.each_index do |a|
        (a + 1...@agents.length).each do |b|
          mutual = accepts?(a, b) && accepts?(b, a)
          if partners[a] == b
            unacceptable << [a, b] unless mutual
          elsif mutual && rank(a, b) < rank(a, partners[a]) && rank(b, a) < rank(b, partners[b])
            blocking << [a, b]
          end
        end
      end
    end
    return ["CHECK #{@name} STABLE"] if unacceptable.empty? && blocking.empty?
    output = ["CHECK #{@name} UNSTABLE unacceptable=#{unacceptable.length} blocking=#{blocking.length}"]
    unacceptable.each { |a, b| output << "UNACCEPTABLE #{@agents[a].name} #{@agents[b].name}" }
    blocking.each { |a, b| output << "BLOCKING #{@agents[a].name} #{@agents[b].name}" }
    output
  end

  def table(lists)
    @agents.each_index.map { |a| "TABLE #{@agents[a].name} #{list_text(lists[a].map { |b| @agents[b].name })}" }
  end

  def remove_pair(lists, a, b)
    lists[a].delete(b)
    lists[b].delete(a)
  end

  def roommates(verbose)
    require_kind(:roommate)
    n = @agents.length
    @agents.each do |agent|
      raise CommandError, "INCOMPLETE #{agent.name}" if agent.preference.length < n - 1
    end
    lists = @agents.map { |a| a.preference.dup }
    held = Array.new(n)
    queue = (0...n).to_a
    proposals = 0
    failure = nil
    while proposals < queue.length
      x = queue[proposals]
      proposals += 1
      y = lists[x].first
      queue << held[y] unless held[y].nil?
      held[y] = x
      removed = lists[y].drop(lists[y].index(x) + 1)
      removed.each { |w| remove_pair(lists, y, w) }
      failure = lists.index(&:empty?)
      break unless failure.nil?
    end
    history = []
    rotations = 0
    history.concat(table(lists)) if failure.nil? && verbose
    while failure.nil?
      p = lists.index { |list| list.length >= 2 }
      break if p.nil?
      positions = Array.new(n)
      path = []
      while positions[p].nil?
        positions[p] = path.length
        path << p
        q = lists[p][1]
        p = lists[q].last
      end
      cycle = path.drop(positions[p])
      front = cycle.map { |x| lists[x].first }
      rotations += 1
      notation = cycle.each_index.map { |i| "#{@agents[cycle[i]].name}-#{@agents[front[i]].name}" }.join(' ')
      history << "ROTATION #{rotations} #{notation}"
      removals = []
      cycle.each_with_index do |x, i|
        u = front[(i + 1) % front.length]
        lists[u].drop(lists[u].index(x) + 1).each { |w| removals << [u, w] }
      end
      removals.each { |a, b| remove_pair(lists, a, b) }
      history.concat(table(lists)) if verbose
      failure = lists.index(&:empty?)
    end
    output = ["ROOMMATES #{@name} proposals=#{proposals}", *history]
    if failure.nil?
      pairs = @agents.each_index.filter_map do |a|
        b = lists[a].first
        "#{@agents[a].name}-#{@agents[b].name}" if a < b
      end
      output << "MATCHING #{pairs.join(' ')}"
    else
      output << "NO STABLE MATCHING #{@agents[failure].name}"
    end
    output
  end

  def ttc
    n = @agents.length
    remaining = Array.new(n, true)
    effective = @agents.each_index.map { |a| self.effective(a) }
    allocation = Array.new(n)
    history = []
    while (start = remaining.index(true))
      points = Array.new(n)
      n.times { |a| points[a] = effective[a].find { |house| remaining[house] } if remaining[a] }
      seen = Array.new(n, false)
      p = start
      until seen[p]
        seen[p] = true
        p = points[p]
      end
      first = p
      cycle = []
      loop do
        allocation[p] = points[p]
        remaining[p] = false
        cycle << "#{@agents[p].name}:#{@houses[points[p]]}"
        p = points[p]
        break if p == first
      end
      history << "CYCLE #{history.length + 1} #{cycle.join(' ')}"
    end
    ["TTC #{@name} cycles=#{history.length}", *history, "ALLOCATION #{allocation_text(allocation)}"]
  end

  def serial(words)
    order = []
    words.drop(2).each do |name|
      a = agent(name)
      raise CommandError, "DUPLICATE AGENT #{name}" if order.include?(a)
      order << a
    end
    raise CommandError, 'BAD ORDER' unless order.length == @agents.length
    taken = Array.new(@agents.length, false)
    allocation = Array.new(@agents.length)
    order.each do |a|
      house = @agents[a].preference.find { |h| !taken[h] }
      next if house.nil?
      allocation[a] = house
      taken[house] = true
    end
    worse = @agents.each_index.filter_map do |a|
      @agents[a].name if allocation[a].nil? || !effective(a).include?(allocation[a])
    end
    ["SERIAL #{@name} assigned=#{allocation.count { |house| !house.nil? }}", "ALLOCATION #{allocation_text(allocation)}", "WORSE #{list_text(worse)}"]
  end

  def hr
    a = deferred.partners
    h = deferred(reverse: true).partners
    unmatched = @proposers.times.filter_map { |p| @agents[p].name if a[p].nil? }
    rural = @proposers.times.all? { |p| a[p].nil? == h[p].nil? }
    output = ["HR #{@name} residents=#{@proposers} hospitals=#{@agents.length - @proposers}",
              "RESIDENT-OPTIMAL #{pairs(a)}", "HOSPITAL-OPTIMAL #{pairs(h)}", "UNMATCHED #{list_text(unmatched)}"]
    (@proposers...@agents.length).each do |r|
      first = @proposers.times.select { |p| a[p] == r }
      second = @proposers.times.select { |p| h[p] == r }
      same = first == second
      capacity = @agents[r].capacity
      output << "HOSPITAL #{@agents[r].name} cap=#{capacity} resident=#{first.length} hospital=#{second.length} same=#{same ? 'YES' : 'NO'}"
      rural &&= first.length == second.length && (first.length == capacity || same)
    end
    output << (rural ? 'RURAL HOLDS' : 'RURAL FAILS')
  end

  def manipulate(a)
    truth = @agents[a].preference
    b0 = boston.partners[a]
    g0 = deferred.partners[a]
    output = ["MANIPULATE #{@name} #{@agents[a].name} boston=#{partner_name(b0)} gs=#{partner_name(g0)} swaps=#{[0, truth.length - 1].max}"]
    (truth.length - 1).times do |i|
      trial = dup
      swapped = truth.dup
      swapped[i], swapped[i + 1] = truth[i + 1], truth[i]
      trial.agents[a].preference = swapped.freeze
      b = trial.boston.partners[a]
      g = trial.deferred.partners[a]
      swap = "#{i + 1} #{@agents[truth[i]].name} #{@agents[truth[i + 1]].name}"
      output << "IMPROVE BOSTON #{swap} result=#{partner_name(b)}" if rank(a, b) < rank(a, b0)
      output << "IMPROVE GS #{swap} result=#{partner_name(g)}" if rank(a, g) < rank(a, g0)
    end
    output << 'NO IMPROVEMENT' if output.length == 1
    output
  end

  def stats
    raise CommandError, 'NO MATCHING' if @current.nil?
    sums = [0, 0]
    first = [0, 0]
    occupied = Array.new(@agents.length, false)
    pairs = 0
    @current.partners.each_with_index do |r, p|
      next if r.nil?
      pairs += 1
      occupied[r] = true
      [rank(p, r), rank(r, p)].each_with_index do |value, i|
        sums[i] += value
        first[i] += 1 if value == 1
      end
    end
    unmatched = [@proposers - pairs, occupied.drop(@proposers).count(false)]
    output = ["STATS #{@name} source=#{@current.source} pairs=#{pairs}"]
    %w[PROPOSERS RECEIVERS].each_with_index do |label, i|
      average = truncated = '-'
      if pairs.positive?
        divisor = sums[i].gcd(pairs)
        cents = 100 * sums[i] / pairs
        average = "#{sums[i] / divisor}/#{pairs / divisor}"
        truncated = format('%d.%02d', cents / 100, cents % 100)
      end
      output << "#{label} sum=#{sums[i]} average=#{average} truncated=#{truncated} first=#{first[i]} unmatched=#{unmatched[i]}"
    end
    output
  end

  def show
    header = case @kind
             when :two_sided then "SHOW #{@name} MARKET proposers=#{@proposers} receivers=#{@agents.length - @proposers}"
             when :roommate then "SHOW #{@name} ROOMS agents=#{@agents.length}"
             when :housing then "SHOW #{@name} HOUSES agents=#{@agents.length}"
             end
    output = [header]
    @agents.each_with_index do |agent, a|
      prefix = case @kind
               when :two_sided
                 a < @proposers ? "PROPOSER #{agent.name}" : "RECEIVER #{agent.name} cap=#{agent.capacity}"
               when :roommate then "AGENT #{agent.name}"
               when :housing then "AGENT #{agent.name} house=#{@houses[a]}"
               end
      preference = agent.preference.map { |b| @kind == :housing ? @houses[b] : @agents[b].name }
      output << "#{prefix} #{list_text(preference)}"
    end
    output << "CURRENT #{@current ? @current.source : '-'}" if @kind == :two_sided
    output
  end
end

class Lab
  def initialize
    @markets = {}
  end

  def create(words)
    op, name = words.take(2)
    raise CommandError, "DUPLICATE MARKET #{name}" if @markets.key?(name)
    kind = { 'ROOMS' => :roommate, 'HOUSES' => :housing }.fetch(op, :two_sided)
    if op == 'RANDOM'
      n, seed = words.drop(2).map { |value| Integer(value, 10) }
      state = seed
      names = (0...2 * n).map { |a| "#{a < n ? 'P' : 'R'}#{a % n + 1}" }
      market = Market.new(name, kind, names, n)
      market.agents.each_with_index do |agent, a|
        preference = n.times.map { |i| (a < n ? n : 0) + i }
        n.downto(2) do |i|
          state = 48271 * state % 2147483647
          j = state % i
          preference[i - 1], preference[j] = preference[j], preference[i - 1]
        end
        agent.preference = preference.freeze
      end
      @markets[name] = market
      return ["RANDOM #{name} n=#{n} seed=#{seed}"]
    end
    names, houses = [], []
    proposers = 0
    words.drop(2).each do |word|
      if word == '|'
        proposers = names.length
        next
      end
      agent, house = kind == :housing ? word.split(':') : [word]
      raise CommandError, "DUPLICATE AGENT #{agent}" if names.include?(agent)
      if kind == :housing
        raise CommandError, "DUPLICATE HOUSE #{house}" if houses.include?(house)
        houses << house
      end
      names << agent
    end
    @markets[name] = Market.new(name, kind, names, proposers, houses)
    [kind == :two_sided ? "MARKET #{name} proposers=#{proposers} receivers=#{names.length - proposers}" : "#{op} #{name} agents=#{names.length}"]
  end

  def execute(line)
    words = line.split(' ')
    op, name = words.take(2)
    return create(words) if %w[MARKET ROOMS HOUSES RANDOM].include?(op)
    market = @markets[name]
    raise CommandError, "UNKNOWN MARKET #{name}" if market.nil?
    case op
    when 'SHOW' then return market.show
    when 'PREF'
      a = market.agent(words[2])
      preference = []
      words.drop(3).each do |word|
        b = market.kind == :housing ? market.houses.index(word) : market.find_agent(word)
        if b.nil? || (market.kind == :two_sided && (a < market.proposers) == (b < market.proposers)) || (market.kind == :roommate && a == b)
          raise CommandError, "BAD CHOICE #{word}"
        end
        raise CommandError, "DUPLICATE CHOICE #{word}" if preference.include?(b)
        preference << b
      end
      market.agents[a].preference = preference.freeze
      market.current = nil if market.kind == :two_sided
      return ["PREF #{name} #{words[2]} length=#{preference.length}"]
    when 'CHECK' then return market.check(words)
    when 'ROOMMATES' then return market.roommates(words.length == 3)
    when 'TTC', 'SERIAL'
      market.require_kind(:housing)
      return op == 'TTC' ? market.ttc : market.serial(words)
    end
    market.require_kind(:two_sided)
    case op
    when 'CAPACITY'
      r = market.agent(words[2], :receiver)
      capacity = Integer(words[3], 10)
      market.agents[r].capacity = capacity
      market.current = nil
      ["CAPACITY #{name} #{words[2]} #{capacity}"]
    when 'GS', 'GSR', 'BOSTON'
      result = op == 'BOSTON' ? market.boston : market.deferred(reverse: op == 'GSR', verbose: words.length == 3)
      market.save(op, result.partners)
      ["#{op} #{name} #{op == 'BOSTON' ? 'applications' : 'proposals'}=#{result.count}", *result.history, "MATCHING #{market.pairs(result.partners)}"]
    when 'HR' then market.hr
    when 'MANIPULATE' then market.manipulate(market.agent(words[2], :proposer))
    when 'STATS' then market.stats
    when 'LATTICE', 'EGALITARIAN', 'MINREGRET'
      lattice = market.enumerate
      if op == 'LATTICE'
        output = ["LATTICE #{name} matchings=#{lattice.matchings.length} rotations=#{lattice.rotations.length}"]
        lattice.matchings.each_with_index do |candidate, i|
          output << "MATCHING #{i + 1} from=#{candidate.origin || '-'} via=#{candidate.via || '-'} cost=#{candidate.cost} regret=#{candidate.regret} #{market.pairs(candidate.partners)}"
        end
        lattice.rotations.each_with_index do |rotation, i|
          notation = rotation.pairs.map { |p, r| "#{market.agents[p].name}-#{market.agents[r].name}" }.join(' ')
          output << "ROTATION #{i + 1} #{notation}"
        end
        output
      else
        egalitarian = op == 'EGALITARIAN'
        best = lattice.matchings.each_index.min_by do |i|
          candidate = lattice.matchings[i]
          [egalitarian ? candidate.cost : candidate.regret, i]
        end
        selected = lattice.matchings[best]
        market.save(op, selected.partners)
        metric = egalitarian ? "cost=#{selected.cost}" : "regret=#{selected.regret}"
        ["#{op} #{name} matching=#{best + 1} #{metric}", "MATCHING #{market.pairs(selected.partners)}"]
      end
    else
      raise 'Unknown command in well-formed input'
    end
  end
end

lab = Lab.new
Integer(STDIN.gets, 10).times do
  line = STDIN.gets
  begin
    lab.execute(line).each { |row| STDOUT.puts(row) }
  rescue CommandError => error
    STDOUT.puts(error.message)
  end
end
