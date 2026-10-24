require 'set'
COLUMNS = 'ABCDEFGHJKLMNOPQRST'
HANDICAP = {9 => %w[C3 G7 C7 G3 C5 G5 E3 E7 E5], 13 => %w[D4 K10 D10 K4 D7 K7 G4 G10 G7], 19 => %w[D4 Q16 D16 Q4 D10 Q10 K4 K16 K10]}.freeze
ARITY = {'BOARD'=>2,'KOMI'=>1,'SUPERKO'=>1,'HANDICAP'=>1,'PLAY'=>2,'PASS'=>1,'REPLAY'=>1,'UNDO'=>0,'SHOW'=>0,'MAP'=>0,'STATUS'=>0,'CAPTURES'=>0,'HISTORY'=>0,'MOVES'=>0,'GROUP'=>1,'GROUPS'=>0,'ATARI'=>0,'LEGAL'=>1,'EYES'=>1,'SAFE'=>1,'LADDER'=>1,'DEAD'=>1,'REGIONS'=>0,'SCORE'=>1}.freeze
Group = Data.define(:color, :first, :stones, :liberties)
def other(c) = c == 'B' ? 'W' : 'B'
def half(x) = "#{x < 0 ? '-' : ''}#{x.abs / 2}.#{x.abs.odd? ? 5 : 0}"
def komi(s)
  return nil unless /\A-?(0|[1-9][0-9]*)(?:\.[05])?\z/.match?(s)
  unsigned = s.delete_prefix('-'); parts = unsigned.split('.'); x = parts[0].to_i * 2 + (parts[1] == '5' ? 1 : 0)
  return nil if parts[0].to_i > 100 || (s.start_with?('-') && x.zero?)
  s.start_with?('-') ? -x : x
end
def adjacent(p, n, diagonal = false)
  r, c = p.divmod(n)
  steps = diagonal ? [[-1,-1],[-1,1],[1,-1],[1,1]] : [[-1,0],[1,0],[0,-1],[0,1]]
  steps.filter_map { |dr, dc| (r + dr) * n + c + dc if (0...n).cover?(r + dr) && (0...n).cover?(c + dc) }
end
def flood(b, n, p, allowed)
  seen, todo = Set[p], [p]
  until todo.empty?
    adjacent(todo.pop, n).each { |q| if !seen.include?(q) && allowed.include?(b[q]); seen.add(q); todo << q end }
  end
  seen
end
def group(b, n, p)
  s = flood(b, n, p, b[p]); l = s.flat_map { |q| adjacent(q, n).select { |t| b[t] == '.' } }.to_set
  Group.new(b[p], s.min, s, l)
end
def groups(b, n, color = nil)
  seen = Set.new
  (0...b.length).filter_map do |p|
    next if b[p] == '.' || seen.include?(p) || (color && b[p] != color)
    g = group(b, n, p); seen.merge(g.stones); g
  end
end
def placement(b, n, c, p)
  return [b, 0, 'occupied'] unless b[p] == '.'
  next_board = b.dup; next_board[p] = c; seen = Set.new; captured = 0
  adjacent(p, n).each do |q|
    next unless next_board[q] == other(c) && !seen.include?(q)
    g = group(next_board, n, q); seen.merge(g.stones)
    if g.liberties.empty?
      g.stones.each { |t| next_board[t] = '.' }; captured += g.stones.size
    end
  end
  [next_board, captured, group(next_board, n, p).liberties.empty? ? 'suicide' : nil]
end
def regions(b, n)
  seen = Set.new
  (0...b.length).filter_map do |p|
    next unless b[p] == '.' && !seen.include?(p)
    points = flood(b, n, p, '.'); seen.merge(points)
    border = points.flat_map { |q| adjacent(q, n).map { |t| b[t] }.reject { |v| v == '.' } }.uniq
    [p, points, border.length == 1 ? border[0] : 'neutral']
  end
end
def safe_groups(b, n, c)
  own = groups(b, n, c); areas = []; seen = Set.new
  (0...b.length).each do |p|
    next if b[p] == c || seen.include?(p)
    area = flood(b, n, p, '.' + other(c)); seen.merge(area); empty = area.select { |q| b[q] == '.' }.to_set
    touch = own.each_index.select { |i| area.any? { |q| adjacent(q, n).any? { |t| own[i].stones.include?(t) } } }.to_set
    vital = own.each_index.select { |i| empty.subset?(own[i].liberties) }.to_set
    areas << [touch, vital]
  end
  s, t = own.each_index.to_set, areas.each_index.to_set
  loop do
    count = s.size + t.size
    s.select! { |i| t.count { |j| areas[j][1].include?(i) } >= 2 }
    t.select! { |j| areas[j][0].subset?(s) }
    break if count == s.size + t.size
  end
  s.sort.map { |i| own[i] }
end
def ladder(b, n, p)
  defender, attacker = b[p], other(b[p]); memo = {}
  read = lambda do |current, depth, defending|
    return [defending, nil] if depth >= 40
    key = [current, depth, defending]; return memo[key] if memo.key?(key)
    g = group(current, n, p); candidates = g.liberties.dup; seen = Set.new
    if defending
      g.stones.each do |q|
        adjacent(q, n).each do |t|
          next unless current[t] == attacker && !seen.include?(t)
          enemy = group(current, n, t); seen.merge(enemy.stones)
          candidates.merge(enemy.liberties) if enemy.liberties.size == 1
        end
      end
    end
    candidates.sort.each do |q|
      next_board, _, reason = placement(current, n, defending ? defender : attacker, q)
      next if reason
      if defending
        m = group(next_board, n, p).liberties.size
        success = m >= 3 || (m == 2 && !read.call(next_board, depth + 1, false)[0])
      else success = !read.call(next_board, depth + 1, true)[0] end
      return memo[key] = [true, q] if success
    end
    memo[key] = [false, nil]
  end
  count = group(b, n, p).liberties.size
  return ['safe', nil] if count >= 3
  success, move = read.call(b, 0, count == 1)
  [(count == 1 ? success : !success) ? 'escapes' : 'captured', move]
end
class Game
  def initialize
    @superko = false
    reset(19, 13)
  end
  def emit(*a) = puts(a.join(' '))
  def reset(n, k)
    @n, @komi, @board, @turn = n, k, '.' * (n * n), 'B'
    @captures, @passes, @over = {'B'=>0, 'W'=>0}, 0, false
    @handicap, @history, @positions, @dead = [], [], [@board], Set.new
  end
  def point(s)
    return nil unless /\A[A-HJ-T](?:[1-9]|1[0-9])\z/.match?(s)
    c, r = COLUMNS.index(s[0]), s[1..].to_i
    c < @n && r <= @n ? (r - 1) * @n + c : nil
  end
  def name(p) = COLUMNS[p % @n] + (p / @n + 1).to_s
  def sgf(p) = (97 + p % @n).chr + (97 + @n - 1 - p / @n).chr
  def check(c, p)
    b, captured, reason = placement(@board, @n, c, p)
    reason = 'ko' if !reason && @positions.length >= 2 && b == @positions[-2]
    reason = 'superko' if !reason && @superko && @positions.include?(b)
    [b, captured, reason]
  end
  def move(c, p, checked = nil)
    before = [@board, @turn, @captures.dup, @passes, @over]; captured = 0
    if p.nil?
      @passes += 1; @over = true if @passes == 2
    else
      @board, captured, = checked || check(c, p); @captures[c] += captured; @passes = 0
    end
    @turn = other(c); @history << [c, p, captured, before]; @positions << @board; @dead.clear
    captured
  end
  def clean = @board.chars.each_with_index.map { |c, p| @dead.include?(p) ? '.' : c }.join
  def show(map = false)
    b = map ? clean : @board; chars = b.chars
    stars = HANDICAP[@n].each_with_index.filter_map { |s, i| point(s) if @n == 19 || i < 4 || i == 8 }
    regions(b, @n).each { |_, points, owner| points.each { |p| chars[p] = owner == 'B' ? 'x' : owner == 'W' ? 'o' : '.' } } if map
    b.chars.each_with_index do |c, p|
      if c != '.'
        letter = c == 'B' ? 'X' : 'O'; chars[p] = @dead.include?(p) && !map ? letter.downcase : letter
      elsif !map then chars[p] = stars.include?(p) ? '+' : '.' end
    end
    header = '   ' + COLUMNS[0, @n].chars.join(' '); emit(header)
    @n.downto(1) { |r| emit(format('%2d', r), chars[(r - 1) * @n, @n].join(' '), r) }; emit(header)
  end
  def score(method)
    b = clean; territory = {'B'=>0, 'W'=>0}; totals = {}
    regions(b, @n).each { |_, points, owner| territory[owner] += points.size if territory.key?(owner) }
    %w[B W].each do |c|
      if method == 'AREA'
        stones = b.count(c); totals[c] = 2 * (stones + territory[c]) + (c == 'W' ? @komi : 0)
        emit(c, 'stones', stones, 'territory', territory[c], *(c == 'W' ? ['komi', half(@komi)] : []), 'total', half(totals[c]))
      else
        prisoners = @captures[c] + @dead.count { |p| @board[p] == other(c) }; totals[c] = 2 * (territory[c] + prisoners) + (c == 'W' ? @komi : 0)
        emit(c, 'territory', territory[c], 'prisoners', prisoners, *(c == 'W' ? ['komi', half(@komi)] : []), 'total', half(totals[c]))
      end
    end
    d = totals['B'] - totals['W']; emit('result', d > 0 ? 'B+' + half(d) : d < 0 ? 'W+' + half(-d) : 'Draw')
  end
  def execute(line)
    c, *a = line.split(' ')
    return emit('ERROR unknown command') unless ARITY.key?(c)
    return emit('ERROR bad arguments') unless a.length == ARITY[c]
    valid = case c
            when 'BOARD' then %w[9 13 19].include?(a[0]) && !komi(a[1]).nil?
            when 'KOMI' then !komi(a[0]).nil?
            when 'SUPERKO' then %w[ON OFF].include?(a[0])
            when 'HANDICAP' then /\A[2-9]\z/.match?(a[0])
            when 'PLAY', 'PASS', 'LEGAL', 'EYES', 'SAFE' then %w[B W].include?(a[0])
            when 'SCORE' then %w[AREA TERRITORY].include?(a[0])
            else true end
    return emit('ERROR bad arguments') unless valid
    if %w[PLAY GROUP LADDER DEAD].include?(c)
      p = point(a[c == 'PLAY' ? 1 : 0]); return emit('ERROR bad point') unless p
    end
    if c == 'REPLAY'
      return emit('ERROR bad sequence') unless /\A(?:;[BW]\[[a-z]{0,2}\])+\z/.match?(a[0])
      records = a[0].scan(/;([BW])\[([a-z]*)\]/)
      return emit('ERROR bad sequence') if records.any? { |_, text| !text.empty? && (text.length != 2 || text.bytes.any? { |ch| ch - 97 >= @n }) }
    end
    return emit('ERROR game over') if %w[PLAY PASS REPLAY].include?(c) && @over
    case c
    when 'BOARD' then reset(a[0].to_i, komi(a[1])); emit('board', @n, 'komi', half(@komi))
    when 'KOMI' then @komi = komi(a[0]); emit('komi', half(@komi))
    when 'SUPERKO' then @superko = a[0] == 'ON'; emit('superko', @superko ? 'on' : 'off')
    when 'HANDICAP'
      return emit('ERROR handicap not allowed') unless @history.empty? && !/[BW]/.match?(@board)
      k = a[0].to_i; indices = k == 5 ? [0,1,2,3,8] : k == 7 ? [0,1,2,3,4,5,8] : (0...k).to_a
      @handicap = indices.map { |i| point(HANDICAP[@n][i]) }; @board = @board.dup
      @handicap.each { |q| @board[q] = 'B' }; @turn = 'W'; @positions = [@board]; @dead.clear
      emit('handicap', k, *@handicap.map { |q| name(q) })
    when 'PLAY'
      checked = check(a[0], p); reason = a[0] != @turn ? 'turn' : checked[2]
      if reason then emit('ILLEGAL', a[0], a[1], reason)
      else captured = move(a[0], p, checked); emit(a[0], a[1], *(captured > 0 ? ['captures', captured] : [])) end
    when 'PASS'
      if a[0] != @turn then emit('ILLEGAL', a[0], 'pass turn')
      else move(a[0], nil); emit(a[0], 'pass'); emit('game over') if @over end
    when 'REPLAY'
      count, stopped = 0, []
      records.each do |color, text|
        q = text.empty? ? nil : (@n - 1 - (text.getbyte(1) - 97)) * @n + text.getbyte(0) - 97
        checked = q ? check(color, q) : nil; reason = @over ? 'game over' : color != @turn ? 'turn' : checked && checked[2]
        if reason then stopped = ['stopped', color, q ? name(q) : 'pass', reason]; break end
        move(color, q, checked); count += 1
      end
      emit('replay', count, 'moves', *stopped); emit('game over') if @over
    when 'UNDO'
      return emit('ERROR nothing to undo') if @history.empty?
      color, q, _, before = @history.pop; @board, @turn, @captures, @passes, @over = before
      @positions.pop; @dead.clear; emit('undo', color, q ? name(q) : 'pass')
    when 'SHOW' then show
    when 'MAP' then show(true)
    when 'STATUS'
      emit('size', @n, 'komi', half(@komi), 'handicap', @handicap.length, 'superko', @superko ? 'on' : 'off')
      emit('moves', @history.length, *(@over ? ['game over'] : ['next', @turn, 'passes', @passes]))
    when 'CAPTURES' then emit('captures B', @captures['B'], 'W', @captures['W'])
    when 'HISTORY'
      emit('history', @history.length)
      @history.each_with_index { |(color, q, captured, _), i| emit(i + 1, color, q ? name(q) : 'pass', *(captured > 0 ? ['captures', captured] : [])) }
    when 'MOVES'
      record = "(;GM[1]FF[4]SZ[#{@n}]KM[#{half(@komi)}]"
      record += "HA[#{@handicap.length}]AB" + @handicap.map { |q| "[#{sgf(q)}]" }.join unless @handicap.empty?
      record += @history.map { |color, q, _, _| ";#{color}[#{q ? sgf(q) : ''}]" }.join
      emit(record + ')')
    when 'GROUP', 'DEAD', 'LADDER'
      return emit('ERROR no stone') if @board[p] == '.'
      g = group(@board, @n, p)
      if c == 'GROUP'
        emit('group', g.color, name(g.first), 'size', g.stones.size, 'liberties', g.liberties.size)
        emit('stones', *g.stones.sort.map { |q| name(q) }); emit('liberties', *g.liberties.sort.map { |q| name(q) })
      elsif c == 'DEAD'
        alive = @dead.include?(p); alive ? @dead.subtract(g.stones) : @dead.merge(g.stones)
        emit(alive ? 'alive' : 'dead', g.color, name(g.first), 'size', g.stones.size)
      else status, q = ladder(@board, @n, p); emit('ladder', a[0], status, *(q ? [name(q)] : [])) end
    when 'GROUPS'
      gs = groups(@board, @n); emit('groups', gs.length)
      gs.each { |g| emit(g.color, name(g.first), 'size', g.stones.size, 'liberties', g.liberties.size, *(@dead.include?(g.first) ? ['dead'] : [])) }
    when 'ATARI'
      gs = groups(@board, @n).select { |g| g.liberties.size == 1 }; emit('atari none') if gs.empty?
      gs.each { |g| emit('atari', g.color, name(g.first), 'size', g.stones.size, 'at', name(g.liberties.first)) }
    when 'LEGAL'
      rejected = []; count = 0
      @board.chars.each_with_index { |disc, q| next unless disc == '.'; reason = check(a[0], q)[2]; reason ? rejected << [name(q), reason] : count += 1 }
      emit('legal', a[0], count); rejected.each { |r| emit(*r) }
    when 'EYES'
      found = []
      @board.chars.each_with_index do |disc, q|
        next unless disc == '.'
        ns = adjacent(q, @n); next unless ns.all? { |t| @board[t] == a[0] }
        enemies = adjacent(q, @n, true).count { |t| @board[t] == other(a[0]) }
        found << [name(q), enemies <= (ns.length == 4 ? 1 : 0) ? 'real' : 'false']
      end
      emit('eyes', a[0], found.length); found.each { |r| emit(*r) }
    when 'SAFE'
      gs = safe_groups(@board, @n, a[0]); emit('safe', a[0], gs.length); gs.each { |g| emit(name(g.first), 'size', g.stones.size) }
    when 'REGIONS'
      rs = regions(clean, @n); emit('regions', rs.length); rs.each { |first, points, owner| emit(name(first), 'size', points.size, owner) }
    when 'SCORE' then score(a[0])
    end
  end
end
game = Game.new
gets.to_i.times { game.execute(gets.chomp) }
