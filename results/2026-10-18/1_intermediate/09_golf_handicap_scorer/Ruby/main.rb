class CommandError < StandardError; end

def half_up(n, d)
  (2 * n + d).div(2 * d)
end

def half_away(n, d)
  n.negative? ? -half_up(-n, d) : half_up(n, d)
end

def decimal(n, sign = '-')
  (n.negative? ? sign : '') + "#{n.abs / 10}.#{n.abs % 10}"
end

def index_text(n)
  n.nil? ? 'none' : decimal(n, '+')
end

def hcp_text(n)
  n.nil? ? 'none' : n.negative? ? "+#{-n}" : n.to_s
end

def hundredths(n)
  format('%d.%02d', n / 100, n % 100)
end

def average_text(total, count)
  count.zero? ? '-' : hundredths(total * 100 / count)
end

def status(n)
  n.zero? ? 'AS' : "#{n.abs}#{n.positive? ? ' UP' : ' DN'}"
end

def allocation(h, si)
  q, r = h.abs.divmod(18)
  si.map { |i| h >= 0 ? q + (i <= r ? 1 : 0) : -q - (i >= 19 - r ? 1 : 0) }
end

def handicap(index, course, tee)
  half_up(index * tee.slope + 113 * (tee.rating - 10 * course.par), 1130)
end

def ranked(ids, values, larger = false)
  ids.sort_by do |id|
    v = values[id]
    counts = [v.sum, v[9..].sum, v[12..].sum, v[15..].sum, v[17]]
    [larger ? counts.map { |n| -n } : counts, id]
  end
end

Course = Struct.new(:id, :pars, :si, :par, :tees)
Tee = Struct.new(:id, :rating, :slope)
Event = Struct.new(:id, :form, :course, :tee, :day, :allowance, :players)

class Player
  attr_reader :id, :name
  attr_accessor :index, :rounds, :records, :calculation

  def initialize(id, name, index)
    @id = id
    @name = name
    @index = index
    @rounds = []
    @records = []
    @calculation = nil
  end

  def low(day)
    @records.select { |d, _| d >= day - 365 && d < day }.min_by { |d, i| [i, d] }
  end

  def eligible
    reduction = 0
    rows = []
    (@rounds.length - 1).downto([0, @rounds.length - 20].max) do |i|
      r = @rounds[i]
      reduction += r.exceptional
      rows << [i + 1, r, r.diff - reduction]
    end
    rows.reverse
  end

  def counting(rows)
    n = rows.length
    return [[], 0] if n < 3
    k = if n <= 5
          1
        elsif n <= 8
          2
        elsif n <= 11
          3
        elsif n <= 14
          4
        elsif n <= 16
          5
        elsif n <= 18
          6
        elsif n == 19
          7
        else
          8
        end
    adjustment = n == 3 ? -20 : [4, 6].include?(n) ? -10 : 0
    [rows.sort_by { |number, _, adjusted| [adjusted, -number] }.first(k), adjustment]
  end

  def update(day)
    selected, adjustment = counting(eligible)
    if selected.empty?
      @calculation = nil
      return
    end
    average = half_away(selected.sum { |row| row[2] }, selected.length)
    candidate = average + adjustment
    record = low(day)
    low_index = record&.last
    soft = false
    hard = false
    maximum = false
    unless low_index.nil?
      if candidate - low_index > 30
        candidate = low_index + 30 + (candidate - low_index - 30) / 2
        soft = true
      end
      if candidate - low_index > 50
        candidate = low_index + 50
        hard = true
      end
    end
    if candidate > 540
      candidate = 540
      maximum = true
    end
    @index = candidate
    @calculation = {k: selected.length, average: average, adjustment: adjustment,
                    low: low_index, hard: hard, soft: soft, maximum: maximum}
  end
end

class GolfRound
  attr_reader :course, :tee, :day, :scores, :previous_index, :previous_records,
              :previous_calculation, :hcp, :adjusted, :ags, :diff, :exceptional

  def initialize(player, course, tee, day, scores)
    @course = course
    @tee = tee
    @day = day
    @scores = scores
    @previous_index = player.index
    @previous_records = player.records.length
    @previous_calculation = player.calculation
    @hcp = player.index.nil? ? nil : handicap(player.index, course, tee)
    strokes = allocation(@hcp || 0, course.si)
    @adjusted = scores.each_with_index.map do |score, h|
      limit = @hcp.nil? ? course.pars[h] + 5 : course.pars[h] + 2 + strokes[h]
      score == '-' ? course.pars[h] + strokes[h] : score == 'X' ? limit : [score, limit].min
    end
    @ags = @adjusted.sum
    @diff = half_away(113 * (10 * @ags - tee.rating), tee.slope)
    @exceptional = if !player.index.nil? && player.index - @diff >= 70
                     player.index - @diff >= 100 ? 20 : 10
                   else
                     0
                   end
  end

  def nets(strokes)
    @scores.each_with_index.map { |s, h| s.is_a?(Integer) ? s - strokes[h] : nil }
  end

  def points(nets)
    nets.each_with_index.map { |n, h| n.nil? ? 0 : [0, @course.pars[h] + 2 - n].max }
  end

  def complete?
    @scores.all? { |s| s.is_a?(Integer) }
  end
end

class GolfScorer
  attr_reader :output

  def initialize
    @courses = {}
    @players = {}
    @events = {}
    @output = []
  end

  def emit(*parts)
    @output << parts.join(' ')
  end

  def player(id)
    raise CommandError, 'unknown player' unless @players.key?(id)
    @players[id]
  end

  def course(id)
    raise CommandError, 'unknown course' unless @courses.key?(id)
    @courses[id]
  end

  def tee(cid, tid)
    c = course(cid)
    raise CommandError, 'unknown tee' unless c.tees.key?(tid)
    [c, c.tees[tid]]
  end

  def event_data(e)
    rounds = {}
    hcp = {}
    nets = {}
    points = {}
    e.players.each do |p|
      r = p.rounds.find { |r| r.course.equal?(e.course) && r.tee.equal?(e.tee) && r.day == e.day }
      raise CommandError, 'missing round' unless r
      raise CommandError, 'no index' if r.hcp.nil?
      rounds[p.id] = r
      hcp[p.id] = half_up(r.hcp * e.allowance, 100)
    end
    minimum = %w[MATCH NASSAU FOURBALL].include?(e.form) ? hcp.values.min : 0
    e.players.each do |p|
      nets[p.id] = rounds[p.id].nets(allocation(hcp[p.id] - minimum, e.course.si))
      points[p.id] = rounds[p.id].points(nets[p.id])
    end
    {rounds: rounds, hcp: hcp, nets: nets, points: points}
  end

  def event_ranking(e, d)
    ids = e.players.map(&:id)
    if e.form == 'STROKE'
      complete = ids.select { |id| d[:rounds][id].complete? }
      [ranked(complete, d[:nets]), d[:nets]]
    elsif e.form == 'STABLEFORD'
      [ranked(ids, d[:points], true), d[:points]]
    else
      values = ids.to_h do |id|
        [id, d[:nets][id].each_with_index.map { |n, h| n.nil? || n > e.course.pars[h] ? -1 : n < e.course.pars[h] ? 1 : 0 }]
      end
      [ranked(ids, values, true), values]
    end
  end

  def individual(e, d)
    order, values = event_ranking(e, d)
    order.each_with_index do |id, i|
      if e.form == 'STROKE'
        emit(i + 1, id, 'net', values[id].sum, 'gross', d[:rounds][id].scores.sum, 'hcp', hcp_text(d[:hcp][id]))
      elsif e.form == 'STABLEFORD'
        emit(i + 1, id, 'points', values[id].sum, 'hcp', hcp_text(d[:hcp][id]))
      else
        emit(i + 1, id, status(values[id].sum), 'hcp', hcp_text(d[:hcp][id]))
      end
    end
    return unless e.form == 'STROKE'
    e.players.map(&:id).reject { |id| d[:rounds][id].complete? }.sort.each do |id|
      emit('NR', id, 'hcp', hcp_text(d[:hcp][id]))
    end
    unless order.empty?
      gross = order.to_h { |id| [id, d[:rounds][id].scores] }
      winner = ranked(order, gross).first
      emit('gross', winner, gross[winner].sum)
    end
  end

  def play_match(names, holes, first, last)
    lead = 0
    remaining = last - first
    statuses = []
    (first...last).each do |h|
      lead += holes[h]
      statuses << status(lead)
      remaining = last - h - 1
      break if lead.abs > remaining || remaining.zero?
    end
    result = if lead.zero?
               'AS'
             else
               names[lead.positive? ? 0 : 1] + ' ' + lead.abs.to_s + (remaining.positive? ? "&#{remaining}" : ' UP')
             end
    [statuses, result]
  end

  def matches(e, d)
    ids = e.players.map(&:id)
    sides = e.form == 'FOURBALL' ? [ids.first(2), ids.drop(2)] : [[ids[0]], [ids[1]]]
    names = sides.map { |s| s.join('+') }
    holes = (0...18).map do |h|
      a, b = sides.map { |side| side.filter_map { |id| d[:nets][id][h] }.min }
      a.nil? ? b.nil? ? 0 : -1 : b.nil? || a < b ? 1 : a > b ? -1 : 0
    end
    minimum = d[:hcp].values.min
    parts = ['strokes']
    ids.each { |id| parts.push(id, d[:hcp][id] - minimum) }
    emit(*parts)
    if e.form == 'NASSAU'
      [['front', 0, 9], ['back', 9, 18], ['total', 0, 18]].each do |label, first, last|
        emit(label, play_match(names, holes, first, last)[1])
      end
    else
      statuses, result = play_match(names, holes, 0, 18)
      emit('status', statuses.join(', '))
      emit('result', result)
    end
  end

  def betterball(e, d)
    teams = {}
    values = {}
    e.players.each_slice(2) do |a, b|
      teams[a.id] = b.id
      values[a.id] = (0...18).map { |h| [d[:points][a.id][h], d[:points][b.id][h]].max }
    end
    ranked(teams.keys, values, true).each_with_index do |a, i|
      b = teams[a]
      emit(i + 1, "#{a}+#{b}", 'points', values[a].sum, 'hcp', hcp_text(d[:hcp][a]), hcp_text(d[:hcp][b]))
    end
  end

  def skins(e, d)
    ids = e.players.map(&:id)
    totals = ids.to_h { |id| [id, 0] }
    carry = 0
    winners = []
    18.times do |h|
      carry += 1
      available = ids.reject { |id| d[:nets][id][h].nil? }
      best = available.map { |id| d[:nets][id][h] }.min
      winners = available.select { |id| d[:nets][id][h] == best }
      if winners.length == 1
        emit('hole', h + 1, winners[0], carry)
        totals[winners[0]] += 100 * carry
        carry = 0
      end
    end
    if carry.positive?
      sharing = (winners.empty? ? ids : winners).sort
      share = carry * 100 / sharing.length
      sharing.each { |id| totals[id] += share }
      emit('carry', carry, *sharing)
    end
    ids.sort_by { |id| [-totals[id], id] }.each { |id| emit(id, hundredths(totals[id])) }
  end

  def card_total(label, r, strokes, nets, points, first, last)
    scores = r.scores[first...last]
    complete = scores.all? { |s| s.is_a?(Integer) }
    emit(label, r.course.pars[first...last].sum, complete ? scores.sum : '-',
         r.adjusted[first...last].sum, strokes[first...last].sum,
         complete ? nets[first...last].sum : '-', points[first...last].sum)
  end

  def command(cmd, a)
    case cmd
    when 'COURSE'
      raise CommandError, 'duplicate course' if @courses.key?(a[0])
      pars = a[1, 18].map(&:to_i)
      si = a[19, 18].map(&:to_i)
      raise CommandError, 'invalid course' unless pars.all? { |p| [3, 4, 5].include?(p) } && si.sort == (1..18).to_a
      @courses[a[0]] = Course.new(a[0], pars, si, pars.sum, {})
    when 'TEE'
      c = course(a[0])
      raise CommandError, 'duplicate tee' if c.tees.key?(a[1])
      rating, slope = a[2, 2].map(&:to_i)
      raise CommandError, 'invalid tee' unless (500..900).cover?(rating) && (55..155).cover?(slope)
      c.tees[a[1]] = Tee.new(a[1], rating, slope)
    when 'PLAYER'
      raise CommandError, 'duplicate player' if @players.key?(a[0])
      index = a.length == 3 ? a[2].to_i : nil
      raise CommandError, 'invalid index' if !index.nil? && !(-100..540).cover?(index)
      @players[a[0]] = Player.new(a[0], a[1], index)
    when 'ROUND'
      p = player(a[0])
      c, t = tee(a[1], a[2])
      day = a[3].to_i
      raise CommandError, 'invalid day' if !p.rounds.empty? && day < p.rounds.last.day
      scores = a.drop(4).map { |s| %w[X -].include?(s) ? s : s.to_i }
      raise CommandError, 'too few holes' if scores.count('-') >= 5
      r = GolfRound.new(p, c, t, day, scores)
      p.rounds << r
      p.update(day)
      p.records << [day, p.index] unless p.index.nil?
      parts = ['round', p.id, "#{p.rounds.length}:", 'ags', r.ags, 'diff', decimal(r.diff)]
      parts.push('exceptional', decimal(-r.exceptional)) unless r.exceptional.zero?
      emit(*parts, 'index', index_text(p.index))
    when 'REMOVE'
      p = player(a[0])
      raise CommandError, 'no rounds' if p.rounds.empty?
      number = p.rounds.length
      r = p.rounds.pop
      p.index = r.previous_index
      p.records = p.records.first(r.previous_records)
      p.calculation = r.previous_calculation
      emit('removed', p.id, "#{number}:", 'index', index_text(p.index))
    when 'INDEX'
      p = player(a[0])
      parts = ['index', "#{p.id}:", index_text(p.index), 'rounds', p.rounds.length]
      c = p.calculation
      if c
        parts.push('lowest', c[:k], 'average', decimal(c[:average]), 'adjustment', decimal(c[:adjustment]))
        parts.push('low', index_text(c[:low])) unless c[:low].nil?
        if c[:hard]
          parts.push('hard', 'cap')
        elsif c[:soft]
          parts.push('soft', 'cap')
        end
        parts << 'maximum' if c[:maximum]
      end
      emit(*parts)
    when 'HISTORY'
      p = player(a[0])
      rows = p.eligible
      counted = p.counting(rows)[0].map(&:first)
      emit('history', "#{p.id}:", 'rounds', p.rounds.length)
      rows.each do |number, r, adjusted|
        parts = [number, 'day', r.day, r.course.id, r.tee.id, 'ags', r.ags, 'diff', decimal(r.diff)]
        parts.push('adjusted', decimal(adjusted)) if adjusted != r.diff
        parts << '*' if counted.include?(number)
        emit(*parts)
      end
    when 'LOWINDEX'
      p = player(a[0])
      day = a[1].to_i
      low = p.low(day)
      parts = ['lowindex', p.id, "#{day}:"]
      low ? parts.push(index_text(low[1]), 'day', low[0]) : parts.push('none')
      emit(*parts)
    when 'COURSEHCP'
      p = player(a[0])
      c, t = tee(a[1], a[2])
      raise CommandError, 'no index' if p.index.nil?
      h = handicap(p.index, c, t)
      emit('coursehcp', p.id, c.id, "#{t.id}:", hcp_text(h), 'strokes', *allocation(h, c.si))
    when 'HCPTABLE'
      c, t = tee(a[0], a[1])
      first, last = a[2, 2].map(&:to_i)
      raise CommandError, 'invalid index' unless -100 <= first && first <= last && last <= 540
      emit('hcptable', c.id, "#{t.id}:", index_text(first), 'to', index_text(last))
      start = first
      h = handicap(first, c, t)
      ((first + 1)..last).each do |i|
        following = handicap(i, c, t)
        next if following == h
        emit(index_text(start), 'to', index_text(i - 1) + ':', hcp_text(h))
        start = i
        h = following
      end
      emit(index_text(start), 'to', index_text(last) + ':', hcp_text(h))
    when 'CARD'
      p = player(a[0])
      number = a[1].to_i
      raise CommandError, 'unknown round' if number > p.rounds.length
      r = p.rounds[number - 1]
      c = r.course
      strokes = allocation(r.hcp || 0, c.si)
      nets = r.nets(strokes)
      points = r.points(nets)
      emit('card', p.id, "#{number}:", c.id, r.tee.id, 'day', r.day, 'handicap', hcp_text(r.hcp))
      18.times do |h|
        emit(h + 1, c.pars[h], c.si[h], r.scores[h], r.adjusted[h], strokes[h], nets[h].nil? ? '-' : nets[h], points[h])
        card_total('OUT', r, strokes, nets, points, 0, 9) if h == 8
        if h == 17
          card_total('IN', r, strokes, nets, points, 9, 18)
          card_total('TOTAL', r, strokes, nets, points, 0, 18)
        end
      end
      emit('ags', r.ags, 'diff', decimal(r.diff))
    when 'STATS'
      p = player(a[0])
      labels = %w[eagles birdies pars bogeys doubles others pickups]
      counts = Array.new(7, 0)
      par_scores = {3 => [], 4 => [], 5 => []}
      totals = []
      p.rounds.each do |r|
        totals << r.scores.sum if r.complete?
        r.scores.each_with_index do |score, h|
          if score == 'X'
            counts[6] += 1
          elsif score.is_a?(Integer)
            relative = score - r.course.pars[h]
            category = relative <= -2 ? 0 : relative == -1 ? 1 : relative == 0 ? 2 : relative == 1 ? 3 : relative == 2 ? 4 : 5
            counts[category] += 1
            par_scores[r.course.pars[h]] << score
          end
        end
      end
      parts = ['stats', "#{p.id}:", 'rounds', p.rounds.length, 'best', totals.empty? ? '-' : totals.min,
               'average', average_text(totals.sum, totals.length)]
      labels.each_with_index { |label, i| parts.push(label, counts[i]) }
      [3, 4, 5].each { |par| parts.push("par#{par}", average_text(par_scores[par].sum, par_scores[par].length)) }
      emit(*parts)
    when 'HOLESTATS'
      c = course(a[0])
      rounds = @players.values.flat_map(&:rounds).select { |r| r.course.equal?(c) }
      scores = (0...18).map { |h| rounds.map { |r| r.scores[h] }.select { |s| s.is_a?(Integer) } }
      order = (0...18).sort_by do |h|
        values = scores[h]
        [values.empty? ? 1 : 0, values.empty? ? 0 : -Rational(values.sum - c.pars[h] * values.length, values.length), h]
      end
      emit('holestats', "#{c.id}:", 'rounds', rounds.length)
      18.times do |h|
        emit(h + 1, 'par', c.pars[h], 'si', c.si[h], 'scores', scores[h].length,
             'avg', average_text(scores[h].sum, scores[h].length), 'rank', order.index(h) + 1)
      end
    when 'PLAYERS'
      players = @players.values.sort_by { |p| [p.index.nil? ? 1 : 0, p.index || 0, p.id] }
      emit('players', players.length)
      players.each { |p| emit(p.id, p.name, index_text(p.index), 'rounds', p.rounds.length) }
    when 'EVENT'
      raise CommandError, 'duplicate event' if @events.key?(a[0])
      c, t = tee(a[2], a[3])
      allowance = a[5].to_i
      raise CommandError, 'invalid allowance' unless (1..100).cover?(allowance)
      ids = a.drop(6)
      raise CommandError, 'unknown player' unless ids.all? { |id| @players.key?(id) }
      n = ids.length
      valid = if %w[MATCH NASSAU].include?(a[1])
                n == 2
              elsif a[1] == 'FOURBALL'
                n == 4
              elsif a[1] == 'BETTERBALL'
                [4, 6, 8].include?(n)
              else
                (2..8).cover?(n)
              end
      raise CommandError, 'invalid players' unless valid && ids.uniq.length == n
      @events[a[0]] = Event.new(a[0], a[1], c, t, a[4].to_i, allowance, ids.map { |id| @players[id] })
    when 'RESULTS'
      e = @events[a[0]]
      raise CommandError, 'unknown event' unless e
      d = event_data(e)
      emit('results', "#{e.id}:", e.form, e.course.id, e.tee.id, 'day', e.day, 'allowance', e.allowance)
      if %w[STROKE STABLEFORD PAR].include?(e.form)
        individual(e, d)
      elsif %w[MATCH NASSAU FOURBALL].include?(e.form)
        matches(e, d)
      elsif e.form == 'BETTERBALL'
        betterball(e, d)
      else
        skins(e, d)
      end
    when 'MERIT'
      totals = {}
      awards = [10, 8, 6, 5, 4, 3, 2, 1]
      counted = 0
      @events.each_value do |e|
        next unless %w[STROKE STABLEFORD PAR].include?(e.form)
        begin
          d = event_data(e)
        rescue CommandError
          next
        end
        counted += 1
        e.players.each do |p|
          totals[p.id] ||= [0, 0, 0]
          totals[p.id][2] += 1
        end
        event_ranking(e, d)[0].each_with_index do |id, rank|
          totals[id][0] += awards[rank]
          totals[id][1] += 1 if rank.zero?
        end
      end
      emit('merit:', 'events', counted)
      totals.keys.sort_by { |id| [-totals[id][0], -totals[id][1], id] }.each_with_index do |id, i|
        points, wins, played = totals[id]
        emit(i + 1, id, points, 'wins', wins, 'played', played)
      end
    end
  end

  def execute(line)
    cmd, *args = line.split
    begin
      command(cmd, args)
    rescue CommandError => error
      emit('ERROR', error.message)
    end
  end
end

scorer = GolfScorer.new
STDIN.gets.to_i.times { scorer.execute(STDIN.gets.chomp) }
STDOUT.write(scorer.output.join("\n") + "\n") unless scorer.output.empty?
