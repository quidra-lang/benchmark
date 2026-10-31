
LIMIT = 7
Ballot = Data.define(:votes, :ranking)
Tallies = Data.define(:first, :last, :borda, :approval, :nonblank)
Outcome = Data.define(:order, :lines)

MethodSpec = Data.define(:name, :argument) do
  def self.parse(words)
    argument = case words[0]
               when 'MINIMAX' then words[1]
               when 'APPROVAL', 'STV' then words[1].to_i
               end
    new(words[0], argument)
  end

  def rankable? = name != 'CONDORCET' && name != 'STV'
  def to_s = argument ? "#{name} #{argument}" : name
end

SUMMARY = %w[PLURALITY RUNOFF IRV COOMBS BUCKLIN BORDA BALDWIN NANSON BLACK VETO
             COPELAND MINIMAX SCHULZE RANKEDPAIRS KEMENY].map do |name|
  MethodSpec.new(name, name == 'MINIMAX' ? 'WINNING' : nil)
end.freeze

class CommandError < StandardError; end

def bit(a) = 1 << a
def members(field) = (0...LIMIT).select { |a| (field & bit(a)) != 0 }
def mask(list) = list.reduce(0) { |field, a| field | bit(a) }
def effective(ranking, field) = ranking.select { |a| (field & bit(a)) != 0 }
def total_scores(field, scores) = members(field).sum { |a| scores[a] }
def majority?(field, scores)
  total = total_scores(field, scores)
  members(field).any? { |a| 2 * scores[a] > total }
end
def tie_mark(tie) = tie ? ' (tie)' : ''
def money(value) = format('%d.%02d', value / 100, value % 100)
def closure(field, relation)
  list = members(field)
  list.each do |via|
    list.each do |a|
      list.each { |b| relation[a][b] ||= relation[a][via] && relation[via][b] }
    end
  end
end

class Election
  attr_reader :number, :names, :tiebreak, :groups, :entry_ends
  attr_accessor :active, :total

  def initialize(number, names)
    @number = number
    @names = names.each(&:freeze).freeze
    @active = bit(names.length) - 1
    @priority = Array.new(LIMIT, 0)
    set_tiebreak(members(@active).sort_by { |a| names[a] })
    @groups = []
    @entry_ends = []
    @total = 0
    @cache = Array.new(1 << LIMIT)
    @pairs = nil
  end

  def set_tiebreak(order)
    order.each_with_index { |a, i| @priority[a] = i }
    @tiebreak = order.freeze
  end

  def candidate(name)
    @names.index(name) || raise(CommandError, "unknown candidate #{name}")
  end

  def checked_names(words)
    result = []
    words.each do |name|
      a = candidate(name)
      raise CommandError, "duplicate candidate #{name}" if result.include?(a)
      result << a
    end
    result
  end

  def names_text(list, separator = ', ') = list.map { |a| @names[a] }.join(separator)
  def values(field, scores, cents = false)
    members(field).map { |a| "#{@names[a]} #{cents ? money(scores[a]) : scores[a]}" }.join(', ')
  end

  def ordered(field, scores, descending = true)
    members(field).sort_by { |a| [descending ? -scores[a] : scores[a], @priority[a]] }
  end

  def finish(order, tie, lines)
    lines << "winner: #{@names[order.first]}#{tie_mark(tie)}"
    Outcome.new(order, lines)
  end

  def invalidate
    @cache.fill(nil)
    @pairs = nil
  end

  def finish_entry
    @entry_ends << @groups.length
    invalidate
  end

  def tallies(field)
    return @cache[field] if @cache[field]
    first, last, borda = Array.new(3) { Array.new(LIMIT, 0) }
    approval = Array.new(LIMIT) { Array.new(LIMIT, 0) }
    nonblank = 0
    candidates = members(field)
    size = candidates.length
    @groups.each do |group|
      ranking = effective(group.ranking, field)
      ranked = mask(ranking)
      unless ranking.empty?
        first[ranking.first] += group.votes
        nonblank += group.votes
      end
      if ranking.length == size
        last[ranking.last] += group.votes
      else
        candidates.each { |a| last[a] += group.votes if (ranked & bit(a)).zero? }
      end
      ranking.each_with_index do |a, j|
        borda[a] += group.votes * (size - j - 1)
        (j...size).each { |depth| approval[depth][a] += group.votes }
      end
    end
    @cache[field] = Tallies.new(first.freeze, last.freeze, borda.freeze, approval.each(&:freeze).freeze, nonblank)
  end

  def pairwise
    return @pairs if @pairs
    matrix = Array.new(LIMIT) { Array.new(LIMIT, 0) }
    @groups.each do |group|
      positions = Array.new(LIMIT, LIMIT)
      group.ranking.each_with_index { |a, i| positions[a] = i }
      @names.each_index do |a|
        @names.each_index { |b| matrix[a][b] += group.votes if positions[a] < positions[b] }
      end
    end
    @pairs = matrix.each(&:freeze).freeze
  end

  def condorcet(field, loser = false)
    matrix = pairwise
    list = members(field)
    list.find do |a|
      list.all? { |b| a == b || (loser ? matrix[a][b] < matrix[b][a] : matrix[a][b] > matrix[b][a]) }
    end
  end

  def look_back(field, history)
    current = history.last
    minimum = members(field).map { |a| current[a] }.min
    choices = members(field).select { |a| current[a] == minimum }
    tie = choices.length > 1
    (history.length - 2).downto(0) do |i|
      scores = history[i]
      low = choices.map { |a| scores[a] }.min
      choices.select! { |a| scores[a] == low }
    end
    [choices.max_by { |a| @priority[a] }, tie]
  end

  def elimination(field, coombs: false, exhausted: false)
    remaining = field
    removed = []
    history = []
    lines = []
    loop do
      scores = tallies(remaining)
      active_votes = total_scores(remaining, scores.first)
      line = "round #{lines.length + 1}: " + if exhausted
        "active #{active_votes}, exhausted #{@total - active_votes}"
      else
        values(remaining, scores.first)
      end
      if members(remaining).length == 1 || majority?(remaining, scores.first)
        lines << line
        order = ordered(remaining, scores.first) + removed.reverse
        return exhausted ? Outcome.new(order, lines) : finish(order, false, lines)
      end
      if coombs
        candidates = members(remaining)
        maximum = candidates.map { |a| scores.last[a] }.max
        choices = candidates.select { |a| scores.last[a] == maximum }
        eliminated = ordered(mask(choices), scores.first).last
        tie = choices.length > 1
        line += "; last #{values(remaining, scores.last)}"
      else
        history << scores.first
        eliminated, tie = look_back(remaining, history)
      end
      line += "; eliminated #{@names[eliminated]}#{tie_mark(tie)}" unless exhausted
      lines << line
      removed << eliminated
      remaining &= ~bit(eliminated)
    end
  end

  def runoff(field)
    first = tallies(field).first
    order = ordered(field, first)
    lines = ["round 1: #{values(field, first)}"]
    tie = false
    unless majority?(field, first)
      a, b = order.first(2)
      finalists = bit(a) | bit(b)
      advancement = order.length >= 3 && first[b] == first[order[2]]
      second = tallies(finalists).first
      tie = second[a] == second[b]
      order[0], order[1] = b, a if second[b] > second[a]
      lines << "finalists: #{names_text(members(finalists))}#{tie_mark(advancement)}"
      lines << "round 2: #{values(finalists, second)}"
    end
    finish(order, tie, lines)
  end

  def bucklin(field)
    scores = tallies(field)
    majority = scores.nonblank / 2 + 1
    lines = ["majority: #{majority}"]
    list = members(field)
    final_depth = 0
    list.each_index do |depth|
      final_depth = depth
      lines << "round #{depth + 1}: #{values(field, scores.approval[depth])}"
      break if list.any? { |a| scores.approval[depth][a] >= majority }
    end
    order = list.sort_by { |a| final_depth.downto(0).map { |depth| -scores.approval[depth][a] } + [@priority[a]] }
    finish(order, scores.approval[final_depth][order[0]] == scores.approval[final_depth][order[1]], lines)
  end

  def borda_elimination(field, nanson)
    remaining = field
    tail = []
    lines = []
    history = []
    while members(remaining).length >= 2
      scores = tallies(remaining).borda
      line = "round #{lines.length + 1}: #{values(remaining, scores)}"
      if nanson
        total = total_scores(remaining, scores)
        size = members(remaining).length
        below = members(remaining).select { |a| scores[a] * size < total }
        if below.empty?
          lines << line
          break
        end
        line += "; eliminated #{names_text(below)}"
        removed = ordered(mask(below), scores)
      else
        history << scores
        a, tie = look_back(remaining, history)
        line += "; eliminated #{@names[a]}#{tie_mark(tie)}"
        removed = [a]
      end
      lines << line
      remaining &= ~mask(removed)
      tail = removed + tail
    end
    final_order = ordered(remaining, Array.new(LIMIT, 0))
    finish(final_order + tail, nanson && final_order.length > 1, lines)
  end

  def pair_lines(field, matrix)
    members(field).combination(2).map do |a, b|
      result = matrix[a][b] == matrix[b][a] ? 'tie' : @names[matrix[a][b] > matrix[b][a] ? a : b]
      "#{@names[a]} vs #{@names[b]}: #{matrix[a][b]}-#{matrix[b][a]} (#{result})"
    end
  end

  def condorcet_report(field)
    winner = condorcet(field)
    loser = condorcet(field, true)
    matrix = pairwise
    list = members(field)
    weak = Array.new(LIMIT) { Array.new(LIMIT, false) }
    strong = Array.new(LIMIT) { Array.new(LIMIT, false) }
    list.each do |a|
      list.each do |b|
        weak[a][b] = matrix[a][b] >= matrix[b][a]
        strong[a][b] = matrix[a][b] > matrix[b][a]
      end
    end
    closure(field, weak)
    closure(field, strong)
    smith = list.select { |a| list.all? { |b| weak[a][b] } }
    schwartz = list.select { |a| list.all? { |b| !strong[b][a] || strong[a][b] } }
    Outcome.new([], ["winner: #{winner ? @names[winner] : 'NONE'}", "loser: #{loser ? @names[loser] : 'NONE'}",
                     "smith: #{names_text(smith)}", "schwartz: #{names_text(schwartz)}"])
  end

  def topological(field, relation)
    remaining = field
    order = []
    tie = false
    until remaining.zero?
      list = members(remaining)
      choices = list.select { |a| list.all? { |b| a == b || !relation[b][a] } }
      tie = choices.length > 1 if order.empty?
      a = choices.min_by { |candidate| @priority[candidate] }
      order << a
      remaining &= ~bit(a)
    end
    [order, tie]
  end

  def schulze(field)
    matrix = pairwise
    list = members(field)
    paths = Array.new(LIMIT) { Array.new(LIMIT, 0) }
    list.each { |a| list.each { |b| paths[a][b] = matrix[a][b] if matrix[a][b] > matrix[b][a] } }
    list.each do |via|
      list.each do |a|
        list.each do |b|
          paths[a][b] = [paths[a][b], [paths[a][via], paths[via][b]].min].max if a != via && b != via && a != b
        end
      end
    end
    relation = Array.new(LIMIT) { Array.new(LIMIT, false) }
    list.each { |a| list.each { |b| relation[a][b] = paths[a][b] > paths[b][a] } }
    order, tie = topological(field, relation)
    lines = pair_lines(field, paths)
    lines << "ranking: #{names_text(order, ' > ')}"
    finish(order, tie, lines)
  end

  def ranked_pairs(field)
    matrix = pairwise
    list = members(field)
    pairs = list.product(list).select { |a, b| matrix[a][b] > matrix[b][a] }
    pairs.sort_by! { |a, b| [-matrix[a][b], matrix[b][a], @priority[a], @priority[b]] }
    locked = Array.new(LIMIT) { Array.new(LIMIT, false) }
    reached = Array.new(LIMIT) { Array.new(LIMIT, false) }
    lines = []
    pairs.each do |a, b|
      skip = reached[b][a]
      lines << "#{skip ? 'skip' : 'lock'} #{@names[a]}>#{@names[b]} #{matrix[a][b]}-#{matrix[b][a]}"
      unless skip
        locked[a][b] = reached[a][b] = true
        closure(field, reached)
      end
    end
    order, tie = topological(field, locked)
    finish(order, tie, lines)
  end

  def kemeny(field)
    matrix = pairwise
    best = Array.new(1 << LIMIT, 0)
    ways = Array.new(1 << LIMIT, 0)
    heads = Array.new(1 << LIMIT, 0)
    ways[0] = 1
    (1..field).each do |subset|
      next unless (subset & ~field).zero?
      best[subset] = -1
      list = members(subset)
      list.each do |a|
        rest = subset & ~bit(a)
        score = best[rest] + list.sum { |b| a == b ? 0 : matrix[a][b] }
        if score > best[subset]
          best[subset] = score
          ways[subset] = heads[subset] = 0
        end
        if score == best[subset]
          ways[subset] += ways[rest]
          heads[subset] |= bit(a)
        end
      end
    end
    order = []
    remaining = field
    until remaining.zero?
      a = @tiebreak.find { |candidate| (heads[remaining] & bit(candidate)) != 0 }
      order << a
      remaining &= ~bit(a)
    end
    lines = ["score: #{best[field]}", "optimal: #{ways[field]}", "ranking: #{names_text(order, ' > ')}"]
    finish(order, members(heads[field]).length > 1, lines)
  end

  def stv(field, seats)
    value = @groups.map { |group| effective(group.ranking, field).empty? ? 0 : 100 }
    owner = Array.new(@groups.length)
    quota = tallies(field).nonblank * 100 / (seats + 1) + 1
    lines = ["quota: #{money(quota)}"]
    continuing = field
    elected = []
    history = []
    loop do
      scores = Array.new(LIMIT, 0)
      exhausted = 0
      owner.fill(nil)
      @groups.each_with_index do |group, i|
        next if value[i].zero?
        owner[i] = group.ranking.find { |a| (continuing & bit(a)) != 0 }
        amount = group.votes * value[i]
        if owner[i].nil?
          exhausted += amount
        else
          scores[owner[i]] += amount
        end
      end
      history << scores
      line = "round #{history.length}: #{values(continuing, scores, true)}; exhausted #{money(exhausted)}"
      order = ordered(continuing, scores)
      if order.length == seats - elected.length
        lines << "#{line}; elected #{names_text(order)}"
        elected.concat(order)
        break
      end
      a = order.first
      if scores[a] >= quota
        surplus = scores[a] - quota
        elected << a
        continuing &= ~bit(a)
        owner.each_with_index { |candidate, i| value[i] = value[i] * surplus / scores[a] if candidate == a }
        lines << "#{line}; elected #{@names[a]} (surplus #{money(surplus)})"
        break if elected.length == seats
      else
        excluded, tie = look_back(continuing, history)
        continuing &= ~bit(excluded)
        lines << "#{line}; excluded #{@names[excluded]}#{tie_mark(tie)}"
      end
    end
    lines << "elected: #{names_text(elected)}"
    Outcome.new([], lines)
  end

  def tally(field, method)
    case method.name
    when 'RUNOFF' then return runoff(field)
    when 'IRV', 'COOMBS' then return elimination(field, coombs: method.name == 'COOMBS')
    when 'BUCKLIN' then return bucklin(field)
    when 'BALDWIN', 'NANSON' then return borda_elimination(field, method.name == 'NANSON')
    when 'CONDORCET' then return condorcet_report(field)
    when 'SCHULZE' then return schulze(field)
    when 'RANKEDPAIRS' then return ranked_pairs(field)
    when 'KEMENY' then return kemeny(field)
    when 'STV' then return stv(field, method.argument)
    end
    base = tallies(field)
    lines = []
    label = 'scores'
    descending = true
    condorcet_winner = nil
    scores = case method.name
             when 'PLURALITY'
               label = 'votes'
               base.first
             when 'BORDA', 'BLACK'
               if method.name == 'BLACK'
                 condorcet_winner = condorcet(field)
                 lines << "condorcet: #{condorcet_winner ? @names[condorcet_winner] : 'NONE'}"
               end
               base.borda
             when 'VETO'
               label = 'vetoes'
               descending = false
               base.last
             when 'APPROVAL'
               label = 'approvals'
               base.approval[[method.argument, members(field).length].min - 1]
             when 'COPELAND'
               matrix = pairwise
               counts = Array.new(LIMIT, 0)
               list = members(field)
               descriptions = list.map do |a|
                 wins = draws = losses = 0
                 list.each do |b|
                   next if a == b
                   case matrix[a][b] <=> matrix[b][a]
                   when 1 then wins += 1
                   when 0 then draws += 1
                   when -1 then losses += 1
                   end
                 end
                 counts[a] = 2 * wins + draws
                 "#{@names[a]} #{counts[a] / 2}.#{counts[a] % 2 * 5} (#{wins}-#{draws}-#{losses})"
               end
               lines << "scores: #{descriptions.join(', ')}"
               label = nil
               counts
             when 'MINIMAX'
               matrix = pairwise
               counts = Array.new(LIMIT, 0)
               list = members(field)
               descending = false
               list.each do |a|
                 list.each do |b|
                   next if a == b
                   opposition = matrix[b][a]
                   support = matrix[a][b]
                   value = if method.argument == 'OPPOSITION'
                     opposition
                   elsif opposition <= support
                     0
                   elsif method.argument == 'MARGIN'
                     opposition - support
                   else
                     opposition
                   end
                   counts[a] = [counts[a], value].max
                 end
               end
               counts
             end
    order = ordered(field, scores, descending)
    tie = scores[order[0]] == scores[order[1]]
    if condorcet_winner
      order.delete(condorcet_winner)
      order.unshift(condorcet_winner)
      tie = false
    end
    lines << "#{label}: #{values(field, scores)}" if label
    finish(order, tie, lines)
  end

  def ballots_report
    counts = Hash.new(0)
    @groups.each do |group|
      ranking = effective(group.ranking, @active)
      notation = ranking.empty? ? '-' : names_text(ranking, '>')
      counts[notation] += group.votes
    end
    ranked = counts.sort_by { |notation, votes| [-votes, notation] }
    ["total #{@total}, blank #{counts['-']}, distinct #{counts.length}"] + ranked.map { |notation, votes| "#{votes} #{notation}" }
  end
end

class Lab
  def initialize
    @election = nil
    @number = 0
  end

  def execute(line)
    words = line.split(' ')
    command = words.first
    if command == 'CANDIDATES'
      names = words.drop(1)
      raise CommandError, 'too few candidates' if names.length < 2
      seen = {}
      names.each do |name|
        raise CommandError, "duplicate candidate #{name}" if seen[name]
        seen[name] = true
      end
      @number += 1
      @election = Election.new(@number, names)
      return ["election #{@number}: #{names.length} candidates"]
    end
    e = @election || raise(CommandError, 'no election')
    case command
    when 'BALLOT'
      ranking = words[2] == '-' ? [] : e.checked_names(words[2].split('>'))
      votes = words[1].to_i
      e.groups << Ballot.new(votes, ranking.freeze)
      e.total += votes
      e.finish_entry
      return []
    when 'RANDOM'
      count = words[1].to_i
      state = words[2].to_i
      count.times do
        ranking = members(e.active)
        (ranking.length - 1).downto(1) do |i|
          state = 48_271 * state % 2_147_483_647
          j = state % (i + 1)
          ranking[i], ranking[j] = ranking[j], ranking[i]
        end
        state = 48_271 * state % 2_147_483_647
        length = state % ranking.length + 1
        e.groups << Ballot.new(1, ranking.first(length).freeze)
      end
      e.total += count
      e.finish_entry
      return []
    when 'UNDO'
      raise CommandError, 'nothing to undo' if e.entry_ends.empty?
      e.entry_ends.pop
      ending = e.entry_ends.last || 0
      removed = e.groups.slice!(ending..)
      e.total -= removed.sum(&:votes)
      e.invalidate
      return []
    when 'WITHDRAW', 'RESTORE'
      a = e.candidate(words[1])
      active = (e.active & bit(a)) != 0
      if command == 'WITHDRAW'
        raise CommandError, "already withdrawn #{words[1]}" unless active
        raise CommandError, 'too few candidates' if members(e.active).length <= 2
        e.active &= ~bit(a)
      else
        raise CommandError, "not withdrawn #{words[1]}" if active
        e.active |= bit(a)
      end
      return []
    when 'TIEBREAK'
      order = e.checked_names(words.drop(1))
      raise CommandError, 'incomplete tiebreak' if order.length != e.names.length
      e.set_tiebreak(order)
      return []
    when 'STATUS'
      withdrawn = members((bit(e.names.length) - 1) & ~e.active)
      return ["[#{line}]", "election #{e.number}", "active: #{e.names_text(members(e.active))}",
              "withdrawn: #{withdrawn.empty? ? 'none' : e.names_text(withdrawn)}",
              "tiebreak: #{e.names_text(e.tiebreak)}", "ballots: #{e.total} in #{e.entry_ends.length} entries"]
    end
    raise CommandError, 'no ballots' if e.entry_ends.empty?
    if %w[RANKING SPOILERS].include?(command)
      requested = MethodSpec.parse(words.drop(1))
      raise CommandError, 'not rankable' unless requested.rankable?
      raise CommandError, 'too few candidates' if command == 'SPOILERS' && members(e.active).length < 3
    end
    compared = []
    if command == 'COMPARE'
      words.drop(1).each do |name|
        a = e.candidate(name)
        raise CommandError, "withdrawn candidate #{name}" if (e.active & bit(a)).zero?
        compared << a
      end
      raise CommandError, 'same candidate' if compared[0] == compared[1]
    end
    raise CommandError, 'too many seats' if command == 'STV' && words[1].to_i >= members(e.active).length
    lines = ["[#{line}]"]
    case command
    when 'RANKING', 'SPOILERS'
      result = e.tally(e.active, requested)
      if command == 'RANKING'
        lines << e.names_text(result.order, ' > ')
      else
        winner = result.order.first
        lines << "winner: #{e.names[winner]}"
        members(e.active).each do |a|
          next if a == winner
          other = e.tally(e.active & ~bit(a), requested).order.first
          lines << "without #{e.names[a]}: #{e.names[other]}#{other != winner ? ' (changed)' : ''}"
        end
      end
    when 'BALLOTS' then lines.concat(e.ballots_report)
    when 'PROFILE'
      scores = e.tallies(e.active)
      size = members(e.active).length
      members(e.active).each do |a|
        counts = (0...size).map { |j| scores.approval[j][a] - (j.zero? ? 0 : scores.approval[j - 1][a]) }
        lines << "#{e.names[a]}: #{counts.join(' ')} unranked #{e.total - scores.approval[size - 1][a]}"
      end
    when 'PAIRWISE' then lines.concat(e.pair_lines(e.active, e.pairwise))
    when 'EXHAUSTED' then lines.concat(e.elimination(e.active, exhausted: true).lines)
    when 'SUMMARY', 'COMPARE'
      wins = Array.new(LIMIT, 0)
      ahead = [[], []]
      SUMMARY.each do |method|
        result = e.tally(e.active, method)
        if command == 'SUMMARY'
          winner = result.order.first
          wins[winner] += 1
          lines << "#{method}: #{e.names[winner]}"
        else
          side = result.order.index(compared[0]) < result.order.index(compared[1]) ? 0 : 1
          ahead[side] << method.to_s
        end
      end
      if command == 'SUMMARY'
        lines << "wins: #{e.values(e.active, wins)}"
      else
        matrix = e.pairwise
        a, b = compared
        lines << "#{e.names[a]} #{matrix[a][b]}, #{e.names[b]} #{matrix[b][a]}, neither #{e.total - matrix[a][b] - matrix[b][a]}"
        2.times { |i| lines << "#{e.names[compared[i]]} ahead: #{ahead[i].empty? ? 'none' : ahead[i].join(', ')}" }
      end
    else
      lines.concat(e.tally(e.active, MethodSpec.parse(words)).lines)
    end
    lines
  end
end

count = STDIN.gets.to_i
lab = Lab.new
count.times do
  line = STDIN.gets.chomp
  begin
    puts lab.execute(line)
  rescue CommandError => error
    puts "ERROR #{error.message}"
  end
end
