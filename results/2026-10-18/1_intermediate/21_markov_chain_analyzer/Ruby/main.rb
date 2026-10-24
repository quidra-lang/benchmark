MAX_STATES = 10
MAX_GAMBLER_SIZE = 9
MODULUS = 2_147_483_647
MULTIPLIER = 48_271
ZERO = Rational(0)
ONE = Rational(1)

class CommandError < StandardError; end

def delta(i, j)
  i == j ? ONE : ZERO
end

def answer(flag)
  flag ? "yes" : "no"
end

def fraction_text(value)
  "#{value.numerator}/#{value.denominator}"
end

def value_text(value)
  whole, remainder = value.numerator.divmod(value.denominator)
  digits = remainder * 1_000_000 / value.denominator
  "#{fraction_text(value)}(#{whole}.#{format('%06d', digits)})"
end

def time_text(value)
  value.nil? ? "inf" : value_text(value)
end

def parse_probability(text)
  parts = text.split("/", -1)
  numerator = parts[0].to_i
  denominator = parts.length == 2 ? parts[1].to_i : 1
  raise CommandError, "BAD PROBABILITY" if denominator.zero? || numerator > denominator

  Rational(numerator, denominator)
end

def membership(size, states)
  inside = Array.new(size, false)
  states.each { |state| inside[state] = true }
  inside
end

def identity(size)
  Array.new(size) { |i| Array.new(size) { |j| delta(i, j) } }
end

def eliminate(matrix, size)
  (0...size).each do |column|
    pivot_row = column
    pivot_row += 1 while matrix[pivot_row][column].zero?
    matrix[column], matrix[pivot_row] = matrix[pivot_row], matrix[column]
    pivot = matrix[column][column]
    matrix[column] = matrix[column].map { |value| value / pivot }
    (0...size).each do |row|
      next if row == column

      factor = matrix[row][column]
      next if factor.zero?

      matrix[row] = matrix[row].zip(matrix[column]).map do |value, base|
        value - factor * base
      end
    end
  end
  matrix.map { |row| row[size..] }
end

class Chain
  attr_reader :names, :matrix, :positions
  attr_writer :matrix

  def initialize(names)
    @names = names
    @positions = names.each_with_index.to_h
    @matrix = Array.new(names.size) { Array.new(names.size, ZERO) }
  end

  def size
    @names.length
  end

  def state(text)
    @positions.fetch(text) { raise CommandError, "UNKNOWN STATE #{text}" }
  end

  def distinct_states(texts)
    states = []
    texts.each do |text|
      i = state(text)
      raise CommandError, "DUPLICATE STATE #{text}" if states.include?(i)

      states << i
    end
    states
  end

  def labels(states)
    states.map { |i| @names[i] }
  end

  def row_sum(i)
    @matrix[i].sum
  end

  def block_sum(i, block)
    block.sum { |j| @matrix[i][j] }
  end

  def edge?(i, j)
    @matrix[i][j] > ZERO
  end

  def absorbing?(i)
    @matrix[i][i] == ONE
  end

  def advance(distribution)
    Array.new(size) do |j|
      (0...size).sum { |i| distribution[i] * @matrix[i][j] }
    end
  end

  def reachable(start)
    seen = Array.new(size, false)
    seen[start] = true
    stack = [start]
    until stack.empty?
      i = stack.pop
      (0...size).each do |j|
        next unless edge?(i, j) && !seen[j]

        seen[j] = true
        stack << j
      end
    end
    seen
  end
end

class CommunicatingClass
  attr_reader :number, :members, :closed, :levels, :period

  def initialize(chain, number, members)
    @number = number
    @members = members
    inside = membership(chain.size, members)
    @closed = members.none? do |i|
      (0...chain.size).any? { |j| chain.edge?(i, j) && !inside[j] }
    end
    @levels = Array.new(chain.size, -1)
    @levels[members.first] = 0
    queue = [members.first]
    until queue.empty?
      u = queue.shift
      members.each do |v|
        next unless chain.edge?(u, v) && @levels[v] < 0

        @levels[v] = @levels[u] + 1
        queue << v
      end
    end
    @period = 0
    members.each do |u|
      members.each do |v|
        @period = @period.gcd(@levels[u] + 1 - @levels[v]) if chain.edge?(u, v)
      end
    end
  end
end

class Decomposition
  attr_reader :reach, :classes, :class_of

  def initialize(chain)
    size = chain.size
    @reach = (0...size).map { |i| chain.reachable(i) }
    @classes = []
    @class_of = Array.new(size, -1)
    (0...size).each do |i|
      next if @class_of[i] >= 0

      members = (0...size).select { |j| @reach[i][j] && @reach[j][i] }
      members.each { |j| @class_of[j] = @classes.length }
      @classes << CommunicatingClass.new(chain, @classes.length + 1, members)
    end
  end

  def closed_classes
    @classes.select(&:closed)
  end

  def containing(state)
    @classes[@class_of[state]]
  end

  def reaches?(state, targets)
    @reach[state].each_with_index.any? { |found, i| found && targets[i] }
  end
end

class Absorption
  attr_reader :transient, :absorbing, :fundamental, :steps, :probabilities

  def initialize(chain)
    @transient = (0...chain.size).reject { |i| chain.absorbing?(i) }
    @absorbing = (0...chain.size).select { |i| chain.absorbing?(i) }
    count = @transient.size
    matrix = @transient.each_with_index.map do |i, row|
      left = @transient.map { |j| delta(i, j) - chain.matrix[i][j] }
      right = Array.new(count) { |j| delta(row, j) }
      left + right
    end
    @fundamental = eliminate(matrix, count)
    @steps = @fundamental.map(&:sum)
    @probabilities = @fundamental.map do |row|
      @absorbing.map do |a|
        (0...count).sum { |k| row[k] * chain.matrix[@transient[k]][a] }
      end
    end
  end

  def variance(i)
    total = (0...@transient.size).sum do |j|
      (2 * @fundamental[i][j] - delta(i, j)) * @steps[j]
    end
    total - @steps[i]**2
  end
end

def stationary_distribution(chain, members)
  size = members.size
  matrix = []
  (0...(size - 1)).each do |r|
    coefficients = (0...size).map do |k|
      chain.matrix[members[k]][members[r]] - delta(k, r)
    end
    matrix << coefficients + [ZERO]
  end
  matrix << Array.new(size + 1, ONE)
  eliminate(matrix, size).map(&:first)
end

def irreducible_distribution(chain, decomposition)
  raise CommandError, "NOT IRREDUCIBLE" if decomposition.classes.size > 1

  stationary_distribution(chain, decomposition.classes.first.members)
end

def solve_restricted(chain, states, constants)
  matrix = states.each_with_index.map do |i, row|
    states.map { |j| delta(i, j) - chain.matrix[i][j] } + [constants[row]]
  end
  eliminate(matrix, states.length).map(&:first)
end

def hitting_probabilities(chain, decomposition, targets)
  size = chain.size
  probabilities = (0...size).map { |i| targets[i] ? ONE : ZERO }
  remaining = (0...size).select { |i| !targets[i] && decomposition.reaches?(i, targets) }
  unless remaining.empty?
    constants = remaining.map do |i|
      (0...size).sum { |j| targets[j] ? chain.matrix[i][j] : ZERO }
    end
    solve_restricted(chain, remaining, constants).each_with_index do |value, j|
      probabilities[remaining[j]] = value
    end
  end
  probabilities
end

def hitting_times(chain, targets, probabilities)
  size = chain.size
  times = (0...size).map { |i| targets[i] ? ZERO : nil }
  certain = (0...size).select { |i| !targets[i] && probabilities[i] == ONE }
  unless certain.empty?
    solve_restricted(chain, certain, Array.new(certain.length, ONE)).each_with_index do |value, j|
      times[certain[j]] = value
    end
  end
  times
end

def regular_exponent(chain)
  size = chain.size
  edges = Array.new(size) do |i|
    Array.new(size) { |j| chain.edge?(i, j) }
  end
  power = edges
  (1..((size - 1)**2 + 1)).each do |exponent|
    return exponent if power.all? { |row| row.all? }

    power = Array.new(size) do |i|
      Array.new(size) do |j|
        (0...size).any? { |k| power[i][k] && edges[k][j] }
      end
    end
  end
  nil
end

class MarkovAnalyzer
  attr_reader :output

  def initialize
    @chains = {}
    @output = []
  end

  def emit(*parts)
    @output << parts.map(&:to_s).join(" ")
  end

  def display(names, matrix, label = "ROW")
    emit("STATES", *names)
    names.zip(matrix).each do |name, row|
      emit(label, name, *row.map { |value| fraction_text(value) })
    end
  end

  def chain(name)
    @chains.fetch(name) { raise CommandError, "UNKNOWN CHAIN #{name}" }
  end

  def stochastic(name)
    result = chain(name)
    (0...result.size).each do |i|
      raise CommandError, "NOT STOCHASTIC #{result.names[i]}" unless result.row_sum(i) == ONE
    end
    result
  end

  def create_chain(args)
    name, *names = args
    raise CommandError, "TOO MANY STATES" if names.size > MAX_STATES

    names.each_with_index do |state, position|
      raise CommandError, "DUPLICATE STATE #{state}" if names[0...position].include?(state)
    end
    @chains[name] = Chain.new(names)
    emit("CHAIN", name, "states=#{names.size}")
  end

  def set_probability(args)
    name, source, target, text = args
    c = chain(name)
    i, j = c.state(source), c.state(target)
    value = parse_probability(text)
    c.matrix[i][j] = value
    emit("P", name, source, target, fraction_text(value), "rowsum=#{fraction_text(c.row_sum(i))}")
  end

  def set_row(args)
    name, source, *values = args
    c = chain(name)
    i = c.state(source)
    raise CommandError, "BAD LENGTH" unless values.size == c.size

    c.matrix[i] = values.map { |text| parse_probability(text) }
    emit("ROW", name, source, "rowsum=#{fraction_text(c.row_sum(i))}")
  end

  def show(args)
    c = chain(args[0])
    emit("MATRIX", args[0], "states=#{c.size}")
    display(c.names, c.matrix)
  end

  def check(args)
    c = chain(args[0])
    bad = (0...c.size).reject { |i| c.row_sum(i) == ONE }
    if bad.empty?
      emit("CHECK", args[0], "ok")
    else
      emit("CHECK", args[0], "bad=#{bad.size}")
      bad.each { |i| emit("BADROW", c.names[i], "sum=#{fraction_text(c.row_sum(i))}") }
    end
  end

  def build(args)
    name, raw_order, *tokens = args
    order = raw_order.to_i
    raise CommandError, "BAD ORDER" unless [1, 2].include?(order)
    raise CommandError, "TOO FEW TOKENS" if tokens.size <= order

    observations = if order == 1
                     tokens
                   else
                     tokens.each_cons(2).map { |first, second| "#{first}.#{second}" }
                   end
    names = observations.uniq
    raise CommandError, "TOO MANY STATES" if names.size > MAX_STATES

    c = Chain.new(names)
    counts = Array.new(c.size) { Array.new(c.size, 0) }
    observations.each_cons(2) do |source, target|
      counts[c.positions[source]][c.positions[target]] += 1
    end
    emit("BUILD", name, "order=#{order}", "states=#{c.size}",
         "transitions=#{observations.size - 1}")
    (0...c.size).each do |i|
      total = counts[i].sum
      if total.zero?
        c.matrix[i][i] = ONE
        emit("FROM", names[i], "total=0", "absorbing")
        next
      end
      parts = []
      (0...c.size).each do |j|
        next if counts[i][j].zero?

        c.matrix[i][j] = Rational(counts[i][j], total)
        parts << "#{names[j]}:#{counts[i][j]}"
      end
      emit("FROM", names[i], "total=#{total}", *parts)
    end
    @chains[name] = c
  end

  def gambler(args)
    name, raw_goal, raw_start, raw_p = args
    goal, start = raw_goal.to_i, raw_start.to_i
    raise CommandError, "BAD SIZE" if goal.zero? || goal > MAX_GAMBLER_SIZE
    raise CommandError, "BAD START" if start > goal

    p = parse_probability(raw_p)
    raise CommandError, "BAD PROBABILITY" if p == ZERO || p == ONE

    c = Chain.new((0..goal).map { |i| "s#{i}" })
    c.matrix[0][0] = ONE
    c.matrix[goal][goal] = ONE
    (1...goal).each do |i|
      c.matrix[i][i + 1] = p
      c.matrix[i][i - 1] = ONE - p
    end
    @chains[name] = c
    absorption = Absorption.new(c)
    ruin = [ONE] + absorption.probabilities.map(&:first) + [ZERO]
    duration = [ZERO] + absorption.steps + [ZERO]
    emit("GAMBLER", name, "g=#{goal}", "p=#{fraction_text(p)}", "start=s#{start}",
         "ruin=#{value_text(ruin[start])}", "duration=#{value_text(duration[start])}")
    (0..goal).each do |i|
      emit("CAPITAL", "s#{i}", "ruin=#{value_text(ruin[i])}",
           "win=#{value_text(ONE - ruin[i])}", "duration=#{value_text(duration[i])}")
    end
  end

  def classes(args)
    c = stochastic(args[0])
    decomposition = Decomposition.new(c)
    emit("CLASSES", args[0], "count=#{decomposition.classes.size}")
    decomposition.classes.each do |item|
      kind = item.closed ? "RECURRENT" : "TRANSIENT"
      emit("CLASS", item.number, kind, "period=#{item.period}",
           "size=#{item.members.size}", *c.labels(item.members))
      next if item.period < 2

      (0...item.period).each do |remainder|
        states = item.members.select { |i| item.levels[i] % item.period == remainder }
        emit("CYCLIC", remainder, *c.labels(states))
      end
    end
  end

  def classify(args)
    c = stochastic(args[0])
    decomposition = Decomposition.new(c)
    absorbing = (0...c.size).map { |i| c.absorbing?(i) }
    count = absorbing.count(true)
    absorbing_chain = count.positive? && (0...c.size).all? do |i|
      decomposition.reaches?(i, absorbing)
    end
    exponent = regular_exponent(c)
    emit("CLASSIFY", args[0], "absorbing_states=#{count}",
         "absorbing=#{answer(absorbing_chain)}",
         "ergodic=#{answer(decomposition.classes.size == 1)}",
         "regular=#{answer(!exponent.nil?)}",
         "exponent=#{exponent.nil? ? '-' : exponent}")
  end

  def step(args)
    c = stochastic(args[0])
    initial, steps = args[1], args[2].to_i
    distribution = if initial.match?(/\A[0-9]/)
                     values = initial.split(",")
                     raise CommandError, "BAD LENGTH" if values.size != c.size

                     entries = values.map { |text| parse_probability(text) }
                     raise CommandError, "BAD DISTRIBUTION" unless entries.sum == ONE

                     entries
                   else
                     state = c.state(initial)
                     Array.new(c.size) { |j| delta(state, j) }
                   end
    steps.times { distribution = c.advance(distribution) }
    emit("STEP", args[0], "k=#{steps}")
    c.names.zip(distribution).each do |name, value|
      emit("PROB", name, value_text(value))
    end
  end

  def power(args)
    c = stochastic(args[0])
    steps = args[1].to_i
    matrix = identity(c.size)
    steps.times { matrix = matrix.map { |row| c.advance(row) } }
    emit("POWER", args[0], "k=#{steps}")
    display(c.names, matrix)
  end

  def stationary(args)
    c = stochastic(args[0])
    closed = Decomposition.new(c).closed_classes
    emit("STATIONARY", args[0], "count=#{closed.size}")
    closed.each_with_index do |item, number|
      emit("DIST", number + 1, "class=#{item.number}", "size=#{item.members.size}")
      values = stationary_distribution(c, item.members)
      item.members.zip(values).each do |i, value|
        emit("PI", c.names[i], value_text(value))
      end
    end
  end

  def recurrence(args)
    c = stochastic(args[0])
    state = c.state(args[1])
    item = Decomposition.new(c).containing(state)
    raise CommandError, "TRANSIENT STATE #{args[1]}" unless item.closed

    distribution = stationary_distribution(c, item.members)
    rho = distribution[item.members.index(state)]
    emit("RECURRENCE", args[0], args[1], "pi=#{value_text(rho)}",
         "mean=#{value_text(ONE / rho)}", "period=#{item.period}")
  end

  def absorb(args)
    c = stochastic(args[0])
    absorbing = (0...c.size).map { |i| c.absorbing?(i) }
    raise CommandError, "NO ABSORBING STATE" unless absorbing.any?

    decomposition = Decomposition.new(c)
    (0...c.size).each do |i|
      if !absorbing[i] && !decomposition.reaches?(i, absorbing)
        raise CommandError, "NOT ABSORBING #{c.names[i]}"
      end
    end
    result = Absorption.new(c)
    emit("ABSORB", args[0], "transient=#{result.transient.size}",
         "absorbing=#{result.absorbing.size}")
    return if result.transient.empty?

    names = c.labels(result.transient)
    emit("TRANSIENT", *names)
    emit("ABSORBING", *c.labels(result.absorbing))
    names.zip(result.fundamental).each do |name, row|
      emit("N", name, *row.map { |value| fraction_text(value) })
    end
    names.each_with_index do |name, i|
      emit("STEPS", name, "mean=#{value_text(result.steps[i])}",
           "var=#{value_text(result.variance(i))}")
    end
    names.zip(result.probabilities).each do |name, row|
      emit("B", name, *row.map { |value| fraction_text(value) })
    end
  end

  def hitting(args)
    c = stochastic(args[0])
    targets = membership(c.size, c.distinct_states(args[1..]))
    probabilities = hitting_probabilities(c, Decomposition.new(c), targets)
    times = hitting_times(c, targets, probabilities)
    names = (0...c.size).select { |i| targets[i] }.map { |i| c.names[i] }
    emit("HITTING", args[0], "targets=#{names.join(',')}")
    (0...c.size).each do |i|
      emit("HIT", c.names[i], "prob=#{value_text(probabilities[i])}",
           "time=#{time_text(times[i])}")
    end
  end

  def passage(args)
    c = stochastic(args[0])
    decomposition = Decomposition.new(c)
    pi = irreducible_distribution(c, decomposition)
    times = Array.new(c.size) { Array.new(c.size, ZERO) }
    (0...c.size).each do |j|
      targets = membership(c.size, [j])
      probabilities = hitting_probabilities(c, decomposition, targets)
      column = hitting_times(c, targets, probabilities)
      (0...c.size).each do |i|
        times[i][j] = i == j ? ONE / pi[j] : column[i]
      end
    end
    kemeny = (1...c.size).sum { |j| pi[j] * times[0][j] }
    emit("PASSAGE", args[0], "kemeny=#{value_text(kemeny)}")
    display(c.names, times, "M")
  end

  def first_passage(args)
    name, source, target, text = args
    c = stochastic(name)
    x, y = c.state(source), c.state(target)
    steps = text.to_i
    raise CommandError, "BAD STEPS" if steps.zero?

    current = (0...c.size).map { |i| c.matrix[i][y] }
    first = [current[x]]
    (1...steps).each do
      current = (0...c.size).map do |i|
        (0...c.size).sum do |j|
          j == y ? ZERO : c.matrix[i][j] * current[j]
        end
      end
      first << current[x]
    end
    emit("FIRSTPASSAGE", name, source, target, "k=#{steps}",
         "total=#{value_text(first.sum)}")
    cumulative = ZERO
    first.each_with_index do |value, i|
      cumulative += value
      emit("FP", i + 1, value_text(value), "cum=#{value_text(cumulative)}")
    end
  end

  def path_probability(args)
    c = stochastic(args[0])
    path = args[1..].map { |text| c.state(text) }
    probability = ONE
    zero_at = nil
    (1...path.size).each do |t|
      probability *= c.matrix[path[t - 1]][path[t]]
      zero_at = t if probability.zero? && zero_at.nil?
    end
    parts = ["PATHPROB", args[0], "steps=#{path.size - 1}",
             "prob=#{value_text(probability)}"]
    parts << "zero_at=#{zero_at}" unless zero_at.nil?
    emit(*parts)
  end

  def most_likely(args)
    c = stochastic(args[0])
    start = c.state(args[1])
    steps = args[2].to_i
    raise CommandError, "BAD STEPS" if steps.zero?

    best = Array.new(steps + 1) { Array.new(c.size, ONE) }
    (steps - 1).downto(0) do |t|
      best[t] = Array.new(c.size) do |i|
        (0...c.size).map { |j| c.matrix[i][j] * best[t + 1][j] }.max
      end
    end
    path = [start]
    steps.times do |t|
      current = path[-1]
      next_state = (0...c.size).find do |j|
        c.matrix[current][j] * best[t + 1][j] == best[t][current]
      end
      path << next_state
    end
    emit("MOSTLIKELY", args[0], args[1], "k=#{steps}",
         "prob=#{value_text(best[0][start])}")
    emit("PATH", *c.labels(path))
  end

  def reversible(args)
    c = stochastic(args[0])
    pi = irreducible_distribution(c, Decomposition.new(c))
    violations = []
    (0...c.size).each do |i|
      (i + 1...c.size).each do |j|
        forward = pi[i] * c.matrix[i][j]
        backward = pi[j] * c.matrix[j][i]
        violations << [i, j, forward, backward] unless forward == backward
      end
    end
    if violations.empty?
      emit("REVERSIBLE", args[0], "yes")
    else
      emit("REVERSIBLE", args[0], "no", "violations=#{violations.size}")
      violations.each do |i, j, forward, backward|
        emit("VIOLATION", c.names[i], c.names[j], value_text(forward), value_text(backward))
      end
    end
  end

  def reverse(args)
    name, reversed_name = args
    c = stochastic(name)
    pi = irreducible_distribution(c, Decomposition.new(c))
    reversed = Chain.new(c.names.dup)
    (0...c.size).each do |i|
      (0...c.size).each do |j|
        reversed.matrix[i][j] = pi[j] * c.matrix[j][i] / pi[i]
      end
    end
    @chains[reversed_name] = reversed
    emit("REVERSE", name, reversed_name, "reversible=#{answer(reversed.matrix == c.matrix)}")
    display(reversed.names, reversed.matrix)
  end

  def mixing(args)
    c = stochastic(args[0])
    steps = args[1].to_i
    raise CommandError, "BAD STEPS" if steps.zero?

    epsilon = parse_probability(args[2])
    pi = irreducible_distribution(c, Decomposition.new(c))
    matrix = identity(c.size)
    mixing_time = nil
    lines = []
    (1..steps).each do |t|
      matrix = matrix.map { |row| c.advance(row) }
      distances = matrix.map do |row|
        (0...c.size).sum { |j| (row[j] - pi[j]).abs } / 2
      end
      largest = distances.max
      worst = distances.index(largest)
      mixing_time = t if mixing_time.nil? && largest <= epsilon
      lines << [t, largest, c.names[worst]]
    end
    emit("MIXING", args[0], "k=#{steps}", "eps=#{fraction_text(epsilon)}",
         "time=#{mixing_time || 'none'}")
    lines.each do |t, largest, worst|
      emit("TV", t, value_text(largest), "from=#{worst}")
    end
  end

  def lump(args)
    name, lumped_name, partition = args
    c = stochastic(name)
    seen = Array.new(c.size, false)
    blocks = partition.split("|").map do |group|
      block = group.split(",").map do |text|
        index = c.state(text)
        raise CommandError, "BAD PARTITION" if seen[index]

        seen[index] = true
        index
      end
      block.sort
    end
    raise CommandError, "BAD PARTITION" unless seen.all?

    blocks.sort_by!(&:first)
    blocks.each do |block|
      representative = block.first
      blocks.each do |target|
        expected = c.block_sum(representative, target)
        block.each do |i|
          actual = c.block_sum(i, target)
          next if actual == expected

          emit("LUMP", name, "not", "lumpable",
               "block=#{c.names[representative]}", "target=#{c.names[target.first]}",
               "#{c.names[representative]}=#{value_text(expected)}",
               "#{c.names[i]}=#{value_text(actual)}")
          return
        end
      end
    end
    lumped = Chain.new(blocks.map { |block| c.names[block.first] })
    lumped.matrix = blocks.map do |block|
      blocks.map { |target| c.block_sum(block.first, target) }
    end
    @chains[lumped_name] = lumped
    emit("LUMP", name, lumped_name, "blocks=#{blocks.size}")
    display(lumped.names, lumped.matrix)
  end

  def reward(args)
    c = stochastic(args[0])
    texts = args[2..]
    raise CommandError, "BAD LENGTH" unless texts.size == c.size

    gamma = parse_probability(args[1])
    raise CommandError, "BAD DISCOUNT" if gamma == ONE

    rewards = texts.map { |text| Rational(text.to_i) }
    matrix = Array.new(c.size) do |i|
      Array.new(c.size) { |j| delta(i, j) - gamma * c.matrix[i][j] } + [rewards[i]]
    end
    values = eliminate(matrix, c.size).map(&:first)
    decomposition = Decomposition.new(c)
    gains = Array.new(c.size, ZERO)
    decomposition.closed_classes.each do |item|
      distribution = stationary_distribution(c, item.members)
      gain = item.members.zip(distribution).sum { |i, rho| rho * rewards[i] }
      targets = membership(c.size, item.members)
      probabilities = hitting_probabilities(c, decomposition, targets)
      (0...c.size).each { |i| gains[i] += probabilities[i] * gain }
    end
    emit("REWARD", args[0], "gamma=#{fraction_text(gamma)}")
    (0...c.size).each do |i|
      emit("VALUE", c.names[i], "discounted=#{value_text(values[i])}",
           "gain=#{value_text(gains[i])}")
    end
  end

  def restrict(args)
    name, restricted_name, *texts = args
    c = stochastic(name)
    inside = membership(c.size, c.distinct_states(texts))
    (0...c.size).each do |i|
      if inside[i] && (0...c.size).any? { |j| c.edge?(i, j) && !inside[j] }
        raise CommandError, "NOT CLOSED #{c.names[i]}"
      end
    end
    members = (0...c.size).select { |i| inside[i] }
    restricted = Chain.new(c.labels(members))
    restricted.matrix = members.map do |i|
      members.map { |j| c.matrix[i][j] }
    end
    @chains[restricted_name] = restricted
    emit("RESTRICT", name, restricted_name, "states=#{members.size}")
    display(restricted.names, restricted.matrix)
  end

  def simulate(args)
    name, source = args[0..1]
    c = stochastic(name)
    start = c.state(source)
    steps, seed = args[2].to_i, args[3].to_i
    raise CommandError, "BAD STEPS" if steps.zero?
    raise CommandError, "BAD SEED" if seed.zero? || seed >= MODULUS

    random_value = seed
    path = [start]
    steps.times do
      row = c.matrix[path.last]
      common = row.map(&:denominator).reduce(1, :lcm)
      random_value = MULTIPLIER * random_value % MODULUS
      threshold = random_value % common
      cumulative = ZERO
      row.each_with_index do |value, j|
        cumulative += value
        if cumulative * common > threshold
          path << j
          break
        end
      end
    end
    emit("SIMULATE", name, source, "steps=#{steps}", "seed=#{seed}",
         "end=#{c.names[path.last]}")
    emit("PATH", *c.labels(path))
    (0...c.size).each { |i| emit("VISIT", c.names[i], path.count(i)) }
  end

  def execute(line)
    command, *arguments = line.split(" ")
    begin
      case command
      when "CHAIN" then create_chain(arguments)
      when "P" then set_probability(arguments)
      when "ROW" then set_row(arguments)
      when "SHOW" then show(arguments)
      when "CHECK" then check(arguments)
      when "BUILD" then build(arguments)
      when "GAMBLER" then gambler(arguments)
      when "CLASSES" then classes(arguments)
      when "CLASSIFY" then classify(arguments)
      when "STEP" then step(arguments)
      when "POWER" then power(arguments)
      when "STATIONARY" then stationary(arguments)
      when "RECURRENCE" then recurrence(arguments)
      when "ABSORB" then absorb(arguments)
      when "HITTING" then hitting(arguments)
      when "PASSAGE" then passage(arguments)
      when "FIRSTPASSAGE" then first_passage(arguments)
      when "PATHPROB" then path_probability(arguments)
      when "MOSTLIKELY" then most_likely(arguments)
      when "REVERSIBLE" then reversible(arguments)
      when "REVERSE" then reverse(arguments)
      when "MIXING" then mixing(arguments)
      when "LUMP" then lump(arguments)
      when "REWARD" then reward(arguments)
      when "RESTRICT" then restrict(arguments)
      when "SIMULATE" then simulate(arguments)
      end
    rescue CommandError => error
      emit("ERROR", error.message)
    end
  end
end

count = STDIN.gets.to_i
analyzer = MarkovAnalyzer.new
count.times { analyzer.execute(STDIN.gets.chomp) }
puts analyzer.output.join("\n")
