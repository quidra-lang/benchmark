WEIGHTS = [
  100,
  -20,
  10,
  5,
  5,
  10,
  -20,
  100,
  -20,
  -50,
  -2,
  -2,
  -2,
  -2,
  -50,
  -20,
  10,
  -2,
  -1,
  -1,
  -1,
  -1,
  -2,
  10,
  5,
  -2,
  -1,
  -1,
  -1,
  -1,
  -2,
  5,
  5,
  -2,
  -1,
  -1,
  -1,
  -1,
  -2,
  5,
  10,
  -2,
  -1,
  -1,
  -1,
  -1,
  -2,
  10,
  -20,
  -50,
  -2,
  -2,
  -2,
  -2,
  -50,
  -20,
  100,
  -20,
  10,
  5,
  5,
  10,
  -20,
  100
]
TRANSFORMS = %w[rot90 rot180 rot270 mirror flip diag anti]
ZERO = %w[NEW DUMP SHOW SCORE LEGAL HISTORY SHEET STATS EVAL STABLE SOLVE]
NUMERIC = %w[UNDO REDO HINT PV AI ANALYZE RANDOM PERFT DIVIDE]
ACTIVE = %w[FLIPS MOVE PLAY HINT PV AI SOLVE AUTOPLAY RANDOM MC DIVIDE]
COMMANDS = ZERO + NUMERIC + %w[LOAD TRANSFORM AUTOPLAY MC FLIPS MOVE PLAY RECORD]
Position = Data.define(:board, :side, :over)
Move = Data.define(:side, :square, :count, :passed, :before, :after)
def other(s) = s == "B" ? "W" : "B"
def square_name(p) = "abcdefgh"[p % 8] + (p / 8 + 1).to_s
def square_index(s) = (s[1].to_i - 1) * 8 + s[0].ord - 97
def inside(r, c) = r >= 0 && r < 8 && c >= 0 && c < 8
def initial
  b = "." * 64
  b[27] = b[36] = "W"
  b[28] = b[35] = "B"
  b
end

def flips(b, s, p)
  return [] unless b[p] == "."
  row, col = p.divmod(8)
  out = []
  (-1..1).each do |dr|
    (-1..1).each do |dc|
      next if dr == 0 && dc == 0
      r = row + dr
      c = col + dc
      line = []
      while inside(r, c) && b[8 * r + c] == other(s)
        line << 8 * r + c
        r += dr
        c += dc
      end

      out.concat(line) if !line.empty? && inside(r, c) && b[8 * r + c] == s
    end
  end

  out.sort
end

def legal(b, s) = (0...64).select { |p| b[p] == "." && !flips(b, s, p).empty? }
def place(b, s, p)
  a = b.dup
  flips(b, s, p).each { |q| a[q] = s }
  a[p] = s
  a
end

def terminal(b) = legal(b, "B").empty? && legal(b, "W").empty?
def game_over(b)
  x = b.count("B")
  y = b.count("W")
  "game over B #{x} W #{y} #{x > y ? "winner B" : x < y ? "winner W" : "draw"}"
end

def evaluate(b, s)
  w = (0...64).sum { |i| b[i] == s ? WEIGHTS[i] : b[i] == other(s) ? -WEIGHTS[i] : 0 }
  own = legal(b, s).length
  enemy = legal(b, other(s)).length
  [w + 10 * (own - enemy), w, own, enemy]
end

SEARCH_CACHE = {}
PERFT_CACHE = {}
def search(b, s, d)
  key = [b, s, d]
  return SEARCH_CACHE[key] if SEARCH_CACHE.key?(key)
  ms = legal(b, s)
  o = other(s)
  v = if ms.empty? && legal(b, o).empty?
    (d < 0 ? 1 : 1000) * (b.count(s) - b.count(o))
  elsif d == 0
    evaluate(b, s)[0]
  elsif ms.empty?
    -search(b, o, d < 0 ? -1 : d - 1)
  else
    ms.map { |p| -search(place(b, s, p), o, d < 0 ? -1 : d - 1) }.max
  end

  SEARCH_CACHE.clear if SEARCH_CACHE.length > 300000
  SEARCH_CACHE[key] = v
end

def ranked(b, s, d)
  legal(b, s).map { |p| [-search(place(b, s, p), other(s), d < 0 ? -1 : d - 1), p] }.sort_by { |v, p| [-v, p] }
end

def variation(b, s, d)
  steps = []
  until d == 0 || terminal(b)
    ms = ranked(b, s, d)
    if ms.empty?
      steps << "pass"
    else
      p = ms[0][1]
      steps << square_name(p)
      b = place(b, s, p)
    end

    s = other(s)
    d -= 1 if d > 0
  end

  [steps, b]
end

def perft(b, s, d)
  return 1 if d == 0
  key = [b, s, d]
  return PERFT_CACHE[key] if PERFT_CACHE.key?(key)
  ms = legal(b, s)
  o = other(s)
  n = ms.empty? ? (legal(b, o).empty? ? 1 : perft(b, o, d - 1)) : ms.sum { |p| perft(place(b, s, p), o, d - 1) }
  PERFT_CACHE.clear if PERFT_CACHE.length > 200000
  PERFT_CACHE[key] = n
end

def stable(b)
  stable = Array.new(64, false)
  axes = [[0, 1], [1, 0], [1, 1], [1, -1]]
  loop do
    found = (0...64).select do |p|
      next false if b[p] == "." || stable[p]
      row, col = p.divmod(8)
      axes.all? do |dr, dc|
        full = true
        anchor = false
        [-1, 1].each do |sign|
          r = row + dr * sign
          c = col + dc * sign
          anchor = true if !inside(r, c) || (stable[8 * r + c] && b[8 * r + c] == b[p])
          while inside(r, c)
            full = false if b[8 * r + c] == "."
            r += dr * sign
            c += dc * sign
          end
        end

        full || anchor
      end
    end

    break if found.empty?
    found.each { |p| stable[p] = true }
  end

  %w[B W].map { |s| (0...64).count { |p| stable[p] && b[p] == s } }
end

def transform(p, op)
  r, c = p.divmod(8)
  case op
  when "rot90"
    8 * c + 7 - r
  when "rot180"
    63 - p
  when "rot270"
    8 * (7 - c) + r
  when "mirror"
    8 * r + 7 - c
  when "flip"
    8 * (7 - r) + c
  when "diag"
    8 * c + r
  else
    8 * (7 - c) + 7 - r
  end
end

def transform_board(b, op)
  a = "." * 64
  64.times { |p| a[transform(p, op)] = b[p] }
  a
end

class Minstd
  def initialize(seed) = @value = seed
  def draw = @value = 48271 * @value % 2147483647
end

def random_game(b, s, rng)
  loop do
    ms = legal(b, s)
    if ms.empty?
      return b if legal(b, other(s)).empty?
    else
      b = place(b, s, ms[rng.draw % ms.length])
    end

    s = other(s)
  end
end

def average(f, n)
  v = 100 * f / n
  "#{v / 100}.#{(v % 100).to_s.rjust(2, "0")}"
end

class Othello
  attr_reader :history
  def initialize
    reset
  end

  def reset
    @board = initial
    @side = "B"
    @over = false
    @history = []
    @redo = []
  end

  def emit(*xs)
    puts(xs.join(" "))
  end

  def snapshot = Position.new(@board, @side, @over)
  def restore(p)
    @board = p.board
    @side = p.side
    @over = p.over
  end

  def status = @over ? game_over(@board) : @side + " to move"
  def adjust(quiet = false)
    return false unless legal(@board, @side).empty?
    unless legal(@board, other(@side)).empty?
      emit(@side, "passes") unless quiet
      @side = other(@side)
      return true
    end

    @over = true
    emit(game_over(@board)) unless quiet
    false
  end

  def move(p, quiet = false, value = nil)
    before = snapshot
    s = @side
    k = flips(@board, s, p).length
    @board = place(@board, s, p)
    emit(s, square_name(p), "flips", k, *(value.nil? ? [] : ["value", value])) unless quiet
    @side = other(s)
    passed = adjust(quiet)
    @history << Move.new(s, p, k, passed, before, snapshot)
    @redo = []
    passed
  end

  def reason(p) = @over ? "game over" : @board[p] != "." ? "occupied" : flips(@board, @side, p).empty? ? "no flips" : nil
  def record(text)
    engine = Othello.new
    ps = text.scan(/../).map { |s| square_index(s) }
    passes = 0
    ps.each_with_index do |p, i|
      why = engine.reason(p)
      if why
        emit("ILLEGAL move", i + 1, square_name(p), why)
        return
      end

      passes += 1 if engine.move(p, true)
    end

    restore(engine.snapshot)
    @history = engine.history
    @redo = []
    op = {"f5" => nil, "e6" => "diag", "d3" => "anti", "c4" => "rot180"}[square_name(ps[0])]
    emit("record", ps.length, "moves", passes, "passes")
    emit("normal", ps.map { |p| square_name(op ? transform(p, op) : p) }.join)
    emit(status)
  end

  def sheet
    fields = (@history.empty? ? @board : @history[0].before.board).chars
    @history.each_with_index { |r, i| fields[r.square] = (i + 1).to_s }
    emit(" " + "abcdefgh".chars.map { |s| s.rjust(3) }.join)
    8.times { |r| emit((r + 1).to_s + fields[8 * r, 8].map { |s| s.rjust(3) }.join) }
  end

  def stats
    total = @history.sum(&:count)
    @history.empty? ? emit("moves 0") : emit(
      "moves",
      @history.length,
      "flips",
      total,
      "avg",
      average(total, @history.length),
      "passes",
      @history.count(&:passed)
    )
    %w[B W].each do |s|
      rows = @history.select { |r| r.side == s }
      if rows.empty?
        emit(s, "moves 0")
        next
      end

      sum = rows.sum(&:count)
      max = rows.map(&:count).max
      emit(
        s,
        "moves",
        rows.length,
        "flips",
        sum,
        "avg",
        average(sum, rows.length),
        "max",
        max,
        square_name(rows.find { |r| r.count == max }.square),
        "corners",
        rows.count { |r| [0, 7, 56, 63].include?(r.square) }
      )
    end
  end

  def auto(black, white, seed = nil)
    rng = seed && Minstd.new(seed)
    ps = []
    passes = 0
    until @over
      ms = legal(@board, @side)
      p = rng ? ms[rng.draw % ms.length] : ranked(@board, @side, @side == "B" ? black : white)[0][1]
      ps << square_name(p)
      passes += 1 if move(p, true)
    end

    emit(rng ? "random" : "autoplay", ps.length, "moves", passes, "passes")
    emit("moves", ps.join)
    emit(game_over(@board))
  end

  def monte_carlo(k, seed)
    rng = Minstd.new(seed)
    best = -1
    bp = nil
    legal(@board, @side).each do |p|
      w = d = l = 0
      start = place(@board, @side, p)
      k.times do
        b = random_game(start, other(@side), rng)
        diff = b.count(@side) - b.count(other(@side))
        if diff > 0
          w += 1
        elsif diff < 0
          l += 1
        else
          d += 1
        end
      end

      emit(square_name(p), w, d, l)
      if 2 * w + d > best
        best = 2 * w + d
        bp = p
      end
    end

    emit("best", square_name(bp), best)
  end

  def execute(text)
    cmd, *a = text.split(" ")
    error = nil
    if !COMMANDS.include?(cmd)
      error = "unknown command"
    elsif cmd == "LOAD"
      error = "bad board" unless a.length == 2 && /\A[.BW]{64}\z/.match?(a[0]) && %w[B W].include?(a[1])
    elsif %w[MOVE FLIPS].include?(cmd)
      error = a.length != 1 ? "bad arguments" : /\A[a-h][1-8]\z/.match?(a[0]) ? nil : "bad square"
    elsif %w[PLAY RECORD].include?(cmd)
      error = a.length != 1 ? "bad arguments" : a[0].length <= 120 && /\A(?:[a-h][1-8])+\z/.match?(a[0]) ? nil : "bad record"
    elsif ZERO.include?(cmd)
      error = "bad arguments" unless a.empty?
    elsif cmd == "TRANSFORM"
      error = "bad arguments" unless a.length == 1 && TRANSFORMS.include?(a[0])
    else
      n = a.map(&:to_i)
      expected = %w[AUTOPLAY MC].include?(cmd) ? 2 : 1
      valid = a.length == expected && a.all? { |s| /\A[0-9]+\z/.match?(s) }
      valid &&= case cmd
      when "AUTOPLAY"
        n.all? { |x| (1..4).cover?(x) }
      when "HINT", "PV", "AI", "ANALYZE"
        (1..4).cover?(n[0])
      when "PERFT", "DIVIDE"
        (1..8).cover?(n[0])
      when "MC"
        (1..100).cover?(n[0]) && (1..2147483646).cover?(n[1])
      when "RANDOM"
        (1..2147483646).cover?(n[0])
      else
        n[0] >= 1
      end

      error = "bad arguments" unless valid
    end

    if error
      emit("ERROR", error)
      return
    end

    if ACTIVE.include?(cmd) && @over
      emit("ERROR game over")
      return
    end

    n = a[0].to_i
    case cmd
    when "NEW"
      reset
      emit("OK")
    when "LOAD"
      @board = a[0]
      @side = a[1]
      @over = false
      @history = []
      @redo = []
      emit("OK")
      adjust
    when "DUMP"
      emit("board", @board, @side)
    when "SHOW"
      emit("  a b c d e f g h")
      ms = @over ? [] : legal(@board, @side)
      8.times { |r| emit(r + 1, *(0...8).map { |c| ms.include?(8 * r + c) ? "*" : @board[8 * r + c] }) }
      emit(status)
    when "SCORE"
      emit("score B", @board.count("B"), "W", @board.count("W"), "empty", @board.count("."))
    when "LEGAL"
      ms = @over ? [] : legal(@board, @side)
      emit("legal", ms.length, *ms.map { |p| square_name(p) })
    when "MOVE", "FLIPS"
      p = square_index(a[0])
      why = reason(p)
      if why
        emit("ILLEGAL", why)
      elsif cmd == "MOVE"
        move(p)
      else
        f = flips(@board, @side, p)
        emit("flips", a[0], f.length, *f.map { |q| square_name(q) })
      end

    when "PLAY"
      a[0].scan(/../).each_with_index do |s, i|
        p = square_index(s)
        why = reason(p)
        if why
          emit("ILLEGAL move", i + 1, s, why)
          break
        end

        move(p)
      end

    when "RECORD"
      record(a[0])
    when "UNDO"
      if n > @history.length
        emit("ERROR cannot undo")
      else
        removed = @history.pop(n)
        restore(removed[0].before)
        @redo = removed + @redo
        emit(status)
      end

    when "REDO"
      if n > @redo.length
        emit("ERROR cannot redo")
      else
        added = @redo.shift(n)
        @history.concat(added)
        restore(added[-1].after)
        emit(status)
      end

    when "HISTORY"
      emit("history", @history.length)
      @history.each_with_index { |r, i|
        emit(i + 1, r.side, square_name(r.square), r.count, *(r.passed ? ["pass"] : []))
      }
    when "SHEET"
      sheet
    when "STATS"
      stats
    when "TRANSFORM"
      op = a[0]
      @board = transform_board(@board, op)
      transform_record = lambda do |r|
        before = r.before.with(board: transform_board(r.before.board, op))
        after = r.after.with(board: transform_board(r.after.board, op))
        r.with(square: transform(r.square, op), before: before, after: after)
      end

      @history = @history.map(&transform_record)
      @redo = @redo.map(&transform_record)
      emit("OK")
    when "EVAL"
      v, w, x, y = evaluate(@board, @side)
      emit("eval", v, "weights", w, "mobility", x, y)
    when "STABLE"
      b, w = stable(@board)
      emit("stable B", b, "W", w)
    when "HINT"
      ranked(@board, @side, n).each { |v, p| emit(square_name(p), v) }
    when "PV"
      steps, = variation(@board, @side, n)
      emit("pv", search(@board, @side, n), *steps)
    when "AI"
      v, p = ranked(@board, @side, n)[0]
      move(p, false, v)
    when "ANALYZE"
      loss = {"B" => 0, "W" => 0}
      @history.each_with_index do |r, i|
        rows = ranked(r.before.board, r.side, n)
        best, bp = rows[0]
        v = rows.find { |_, p| p == r.square }[0]
        loss[r.side] += best - v
        emit(i + 1, r.side, square_name(r.square), v, "best", square_name(bp), best)
      end

      emit("loss B", loss["B"], "W", loss["W"])
    when "SOLVE"
      if @board.count(".") >= 9
        emit("ERROR too many empties")
      else
        ranked(@board, @side, -1).each { |v, p| emit(square_name(p), v) }
        steps, b = variation(@board, @side, -1)
        emit("line", *steps)
        emit("final B", b.count("B"), "W", b.count("W"))
      end

    when "AUTOPLAY"
      auto(n, a[1].to_i)
    when "RANDOM"
      auto(0, 0, n)
    when "MC"
      monte_carlo(n, a[1].to_i)
    when "PERFT"
      emit("perft", n, perft(@board, @side, n))
    when "DIVIDE"
      total = 0
      legal(@board, @side).each { |p|
        v = perft(place(@board, @side, p), other(@side), n - 1)
        emit(square_name(p), v)
        total += v
      }
      emit("total", total)
    end
  end
end

engine = Othello.new
STDIN.gets.to_i.times { engine.execute(STDIN.gets.chomp) }
