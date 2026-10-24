require 'set'

KINDS = %w[I O T S Z J L].freeze
MOVEMENTS = %w[L R LL RR SD DD CW CCW].freeze
OPERATIONS = (MOVEMENTS + %w[HD LOCK HOLD]).to_set
COMMANDS = %w[NEW PRINT NEXT PREVIEW STATUS ANALYZE ROW GARBAGE ATTACK TICK UNDO SAVE LOAD SPINS HINT AUTO].to_set
AFTER_END = %w[PRINT NEXT PREVIEW STATUS ANALYZE LOAD].to_set
STATES = %w[0 R 2 L].freeze
CLEAR_NAMES = %w[SINGLE DOUBLE TRIPLE TETRIS TSPIN_MINI TSPIN_MINI_SINGLE TSPIN_MINI_DOUBLE TSPIN TSPIN_SINGLE TSPIN_DOUBLE TSPIN_TRIPLE].freeze
FRAMES = {'I'=>%w[.... #### .... ....], 'O'=>%w[## ##], 'T'=>%w[.#. ### ...],
          'S'=>%w[.## ##. ...], 'Z'=>%w[##. .## ...], 'J'=>%w[#.. ### ...], 'L'=>%w[..# ### ...]}.freeze
SHAPES = FRAMES.to_h do |kind, frame|
  blocks = frame.each_with_index.flat_map { |row,j| row.chars.each_with_index.filter_map { |ch,i| [i,j] if ch == '#' } }
  rotations = [blocks]
  3.times { blocks = blocks.map { |i,j| [frame.length-1-j,i] }; rotations << blocks }
  [kind, rotations]
end.freeze
KICKS = {
  [0,1]=>[[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]], [1,0]=>[[0,0],[1,0],[1,-1],[0,2],[1,2]],
  [1,2]=>[[0,0],[1,0],[1,-1],[0,2],[1,2]], [2,1]=>[[0,0],[-1,0],[-1,1],[0,-2],[-1,-2]],
  [2,3]=>[[0,0],[1,0],[1,1],[0,-2],[1,-2]], [3,2]=>[[0,0],[-1,0],[-1,-1],[0,2],[-1,2]],
  [3,0]=>[[0,0],[-1,0],[-1,-1],[0,2],[-1,2]], [0,3]=>[[0,0],[1,0],[1,1],[0,-2],[1,-2]]
}.freeze
I_KICKS = {
  [0,1]=>[[0,0],[-2,0],[1,0],[-2,-1],[1,2]], [1,0]=>[[0,0],[2,0],[-1,0],[2,1],[-1,-2]],
  [1,2]=>[[0,0],[-1,0],[2,0],[-1,2],[2,-1]], [2,1]=>[[0,0],[1,0],[-2,0],[1,-2],[-2,1]],
  [2,3]=>[[0,0],[2,0],[-1,0],[2,1],[-1,-2]], [3,2]=>[[0,0],[-2,0],[1,0],[-2,-1],[1,2]],
  [3,0]=>[[0,0],[1,0],[-2,0],[1,-2],[-2,1]], [0,3]=>[[0,0],[-1,0],[2,0],[-1,2],[2,-1]]
}.freeze
Statistics = Struct.new(:drops,:holds,:operations,:faults,:perfect,:sent,:cancelled,:received,:combo,:chain,:kinds,:clears, keyword_init: true)
State = Struct.new(:board,:random,:queue,:hold,:used_hold,:kind,:position,:last,:test,:keys,:drop,:fall,:ground,:resets,:lowest,
                   :initial_level,:level,:score,:lines,:pieces,:streak,:chain,:pending,:stats,:ended, keyword_init: true)
Candidate = Data.define(:value,:kind,:keys)
class GameOver < StandardError; end
OUTPUT = []
def emit(text) = OUTPUT << text
def copy(value) = Marshal.load(Marshal.dump(value))
def spawn(kind) = [0, kind == 'O' ? 5 : 4, 22]
def cells(kind, position)
  state,x,y = position
  SHAPES[kind][state].map { |i,j| [x+i,y-j] }
end
def lowest(kind, position) = cells(kind,position).map(&:last).min
def bag(random)
  pieces = KINDS.dup
  6.downto(1) do |i|
    random = 48271 * random % 2147483647
    j = random % (i+1)
    pieces[i],pieces[j] = pieces[j],pieces[i]
  end
  [random,pieces]
end
def fits?(board, kind, position)
  cells(kind,position).all? { |c,r| c.between?(1,10) && r.between?(1,22) && (board[r-1] & (1 << (c-1))).zero? }
end
def move(board, kind, position, operation)
  state,x,y = position
  if %w[CW CCW].include?(operation)
    target = (state + (operation == 'CW' ? 1 : 3)) % 4
    offsets = kind == 'O' ? [[0,0]] : (kind == 'I' ? I_KICKS : KICKS)[[state,target]]
    offsets.each_with_index do |(dx,dy),i|
      result = [target,x+dx,y+dy]
      return [result,i+1] if fits?(board,kind,result)
    end
    return nil
  end
  dx = %w[L LL].include?(operation) ? -1 : %w[R RR].include?(operation) ? 1 : 0
  dy = dx.zero? ? -1 : 0
  repeated = %w[LL RR DD].include?(operation)
  result = position
  loop do
    candidate = [state,result[1]+dx,result[2]+dy]
    break unless fits?(board,kind,candidate)
    result = candidate
    break unless repeated
  end
  result == position ? nil : [result,0]
end
def landing(board, kind, position) = move(board,kind,position,'DD')&.first || position
def placed(board, kind, position)
  result = board.dup
  cells(kind,position).each { |c,r| result[r-1] |= 1 << (c-1) }
  remaining = result.reject { |row| row == 1023 }
  count = 22-remaining.length
  [remaining+Array.new(count,0),count]
end
def evaluation(board, cleared)
  heights = Array.new(10,0)
  holes = 0
  10.times do |c|
    row = 21.downto(0).find { |r| (board[r] & (1 << c)) != 0 }
    heights[c] = row ? row+1 : 0
    heights[c].times { |r| holes += 1 if (board[r] & (1 << c)).zero? }
  end
  bumpiness = heights.each_cons(2).sum { |a,b| (a-b).abs }
  [heights,holes,bumpiness,76*cleared-51*heights.sum-36*holes-18*bumpiness]
end
def routes(board, kind, start, target = nil)
  return [] unless fits?(board,kind,start)
  queue = [[start,[]]]
  seen = Set[start]
  cursor = 0
  while cursor < queue.length
    position,keys = queue[cursor]
    return [queue[cursor]] if target && landing(board,kind,position) == target
    MOVEMENTS.each do |operation|
      result = move(board,kind,position,operation)
      next unless result && seen.add?(result[0])
      queue << [result[0],keys+[operation]]
    end
    cursor += 1
  end
  target ? [] : queue
end
def t_spin(board, position, test)
  state,x,y = position
  blocked = [[x,y],[x+2,y],[x+2,y-2],[x,y-2]].map do |c,r|
    !c.between?(1,10) || !r.between?(1,22) || (board[r-1] & (1 << (c-1))) != 0
  end
  return '' if blocked.count(true) < 3
  (blocked[state] && blocked[(state+1)%4]) || test == 5 ? 'full' : 'mini'
end
def clear_info(spin, lines)
  case spin
  when 'full'; [%w[TSPIN TSPIN_SINGLE TSPIN_DOUBLE TSPIN_TRIPLE][lines],[400,800,1200,1600][lines],[0,2,4,6][lines]]
  when 'mini'; [%w[TSPIN_MINI TSPIN_MINI_SINGLE TSPIN_MINI_DOUBLE][lines],[100,200,400][lines],[0,0,1][lines]]
  else; [['','SINGLE','DOUBLE','TRIPLE','TETRIS'][lines],[0,100,300,500,800][lines],[0,0,1,2,4][lines]]
  end
end

class Game
  attr_reader :state
  def initialize(number, seed, level)
    @number = number
    stats = Statistics.new(drops:0,holds:0,operations:0,faults:0,perfect:0,sent:0,cancelled:0,received:0,combo:0,chain:0,
                           kinds:KINDS.to_h { |k| [k,0] }, clears:CLEAR_NAMES.to_h { |k| [k,0] })
    @state = State.new(board:Array.new(22,0),random:seed,queue:[],hold:nil,used_hold:false,kind:'I',position:spawn('I'),
                       last:'none',test:0,keys:0,drop:0,fall:0,ground:0,resets:0,lowest:0,initial_level:level,level:level,
                       score:0,lines:0,pieces:0,streak:0,chain:0,pending:[],stats:stats,ended:false)
    @history = []
    @saves = {}
    add_bag
    spawn_piece(next_piece)
    @start = copy(@state)
  end
  def add_bag
    @state.random,pieces = bag(@state.random)
    @state.queue.concat(pieces)
  end
  def next_piece
    kind = @state.queue.shift
    add_bag if @state.queue.length < 5
    kind
  end
  def spawn_piece(kind)
    s = @state
    s.kind = kind; s.position = spawn(kind); s.last = 'none'; s.test = 0
    s.keys = s.drop = s.fall = s.ground = s.resets = 0
    s.lowest = lowest(kind,s.position)
    over('block out') unless fits?(s.board,kind,s.position)
  end
  def over(reason)
    emit('game over '+reason)
    summary
    @state.ended = true
    raise GameOver
  end
  def update(position, motion, test = 0)
    s = @state
    s.position = position; s.last = motion; s.test = test
    row = lowest(s.kind,position)
    if row < s.lowest
      s.lowest = row; s.resets = 0
    end
  end
  def grounded? = move(@state.board,@state.kind,@state.position,'SD').nil?
  def drops(points)
    @state.score += points; @state.drop += points; @state.stats.drops += points
  end
  def insert_garbage(rows, hole)
    s = @state
    over('top out') if s.board.last(rows).any? { |row| row != 0 }
    s.board = Array.new(rows,1023 ^ (1 << (hole-1))) + s.board.first(22-rows)
  end
  def operation(operation)
    s = @state
    if MOVEMENTS.include?(operation)
      s.keys += 1
      result = move(s.board,s.kind,s.position,operation)
      unless result
        emit('fail '+operation)
        return
      end
      position,test = result
      if %w[SD DD].include?(operation)
        drops(s.position[2]-position[2]); update(position,'move'); s.fall = s.ground = 0
      else
        update(position,%w[CW CCW].include?(operation) ? 'rotation' : 'move',test)
        if s.ground > 0 && s.resets < 15
          s.ground = 0; s.resets += 1
        end
      end
    elsif operation == 'HD'
      position = landing(s.board,s.kind,s.position)
      rows = s.position[2]-position[2]
      drops(2*rows); update(position,'move') if rows > 0
      lock
    elsif operation == 'LOCK'
      grounded? ? lock : emit('fail LOCK')
    else
      if s.used_hold
        emit('fail HOLD')
        return
      end
      s.used_hold = true; s.stats.holds += 1
      previous = s.hold; s.hold = s.kind
      spawn_piece(previous || next_piece)
    end
  end
  def tick
    s = @state
    if grounded?
      s.ground += 1
      lock if s.ground >= 30
    else
      s.ground = 0; s.fall += 1
      interval = s.level >= 13 ? 1 : [60,48,37,28,21,16,11,8,6,4,3,2][s.level-1]
      if s.fall >= interval
        update([s.position[0],s.position[1],s.position[2]-1],'move'); s.fall = 0
      end
    end
  end
  def lock
    s = @state
    kind,position = s.kind,s.position
    old_cells = cells(kind,position)
    shortest = routes(s.board,kind,spawn(kind),position).first
    spin = kind == 'T' && s.last == 'rotation' ? t_spin(s.board,position,s.test) : ''
    s.board,lines = placed(s.board,kind,position)
    @history << copy(@start)
    s.pieces += 1; s.stats.kinds[kind] += 1; s.stats.operations += s.keys
    name,base,sent = clear_info(spin,lines)
    level = s.level
    points = base*level
    back_to_back = false
    if lines > 0
      s.streak += 1
      if lines == 4 || spin != ''
        s.chain += 1; back_to_back = s.chain >= 2
      else
        s.chain = 0
      end
    else
      s.streak = 0
    end
    if back_to_back
      points = points*3/2; sent += 1
    end
    combo = s.streak-1
    combo_points = combo >= 1 ? 50*combo*level : 0
    sent += [0,1,1,2,2,3,3,4,4,4,5][[combo,10].min] if combo >= 0
    perfect = lines > 0 && s.board.all?(&:zero?)
    perfect_points = perfect ? (lines == 4 && back_to_back ? 3200 : [800,1200,1800,2000][lines-1])*level : 0
    if perfect
      sent += 10; s.stats.perfect += 1
    end
    gained = points+combo_points+perfect_points
    s.score += gained; s.lines += lines; s.stats.sent += sent
    s.stats.combo = [s.stats.combo,combo].max; s.stats.chain = [s.stats.chain,s.chain].max
    emit("lock #{s.pieces} #{kind} #{STATES[position[0]]} #{position[1]} #{position[2]} keys #{s.keys} #{shortest ? shortest[1].length : '-'} drop #{s.drop} lines #{lines} sent #{sent} +#{gained} total #{s.score}")
    if shortest && s.keys > shortest[1].length
      s.stats.faults += 1
      emit('finesse '+(shortest[1].empty? ? 'none' : shortest[1].join(' ')))
    end
    unless name.empty?
      s.stats.clears[name] += 1
      emit("clear #{name} #{points}"+(back_to_back ? ' b2b' : '')+(combo >= 1 ? " combo #{combo} #{combo_points}" : '')+(perfect ? " perfect #{perfect_points}" : ''))
    end
    next_level = s.initial_level+s.lines/10
    if next_level > level
      s.level = next_level; emit("level #{s.level}")
    end
    over('lock out') if old_cells.all? { |_,row| row >= 21 }
    cancelled = [sent,s.pending.sum].min
    remaining = cancelled
    while remaining > 0
      count = [remaining,s.pending[0]].min
      remaining -= count; s.pending[0] -= count; s.pending.shift if s.pending[0].zero?
    end
    if cancelled > 0
      s.stats.cancelled += cancelled; emit("cancel #{cancelled} pending #{s.pending.sum}")
    end
    if lines.zero?
      risen = 0
      while !s.pending.empty? && risen < 8
        count = [s.pending[0],8-risen].min
        s.random = 48271*s.random%2147483647
        hole = s.random%10+1
        insert_garbage(count,hole)
        s.stats.received += count; risen += count; s.pending[0] -= count
        s.pending.shift if s.pending[0].zero?
        emit("rise #{count} hole #{hole} pending #{s.pending.sum}")
      end
    end
    s.used_hold = false; spawn_piece(next_piece); @start = copy(s)
  end
  def candidates(kind, start, prefix)
    result = []; seen = Set.new; board = @state.board
    [[],%w[CW],%w[CW CW],%w[CCW]].each do |turns|
      position = start; valid = true
      turns.each do |turn|
        step = move(board,kind,position,turn)
        unless step
          valid = false; break
        end
        position = step[0]
      end
      next unless valid
      add = lambda do |p,shifts|
        landed = landing(board,kind,p)
        id = cells(kind,landed).map { |c,r| (r-1)*10+c-1 }.sort
        next unless seen.add?(id)
        placed_board,lines = placed(board,kind,landed)
        result << Candidate.new(evaluation(placed_board,lines)[3],kind,prefix+turns+shifts+['HD'])
      end
      add.call(position,[])
      %w[L R].each do |direction|
        p = position; shifts = []
        while (step = move(board,kind,p,direction))
          p = step[0]; shifts << direction; add.call(p,shifts)
        end
      end
    end
    result
  end
  def ranked
    s = @state
    result = candidates(s.kind,s.position,[])
    held = s.hold || s.queue[0]
    result.concat(candidates(held,spawn(held),['HOLD'])) if !s.used_hold && fits?(s.board,held,spawn(held))
    result.each_with_index.sort_by { |c,i| [-c.value,i] }.map(&:first)
  end
  def spins
    s = @state
    if s.kind != 'T'
      emit('spins 0'); return
    end
    found = {}
    routes(s.board,'T',s.position).each do |position,_|
      %w[CW CCW].each do |turn|
        step = move(s.board,'T',position,turn)
        next unless step && move(s.board,'T',step[0],'SD').nil?
        spin = t_spin(s.board,step[0],step[1])
        found[step[0]] = spin if spin != '' && (!found.key?(step[0]) || spin == 'full')
      end
    end
    found.sort_by { |p,_| [p[2],p[1],p[0]] }.each do |position,spin|
      _,lines = placed(s.board,'T',position)
      emit("spin #{STATES[position[0]]} #{position[1]} #{position[2]} #{clear_info(spin,lines)[0]}")
    end
    emit("spins #{found.length}")
  end
  def summary
    s = @state; a = s.stats; c = a.clears
    ratio = lambda { |x,y| q = y.zero? ? 0 : 100*x/y; "#{q/100}.#{(q%100).to_s.rjust(2,'0')}" }
    emit("summary game #{@number} score #{s.score} level #{s.level} lines #{s.lines} pieces #{s.pieces}")
    emit("clears single #{c['SINGLE']} double #{c['DOUBLE']} triple #{c['TRIPLE']} tetris #{c['TETRIS']} perfect #{a.perfect}")
    emit("tspins mini #{c['TSPIN_MINI']} mini_single #{c['TSPIN_MINI_SINGLE']} mini_double #{c['TSPIN_MINI_DOUBLE']} zero #{c['TSPIN']} single #{c['TSPIN_SINGLE']} double #{c['TSPIN_DOUBLE']} triple #{c['TSPIN_TRIPLE']}")
    emit('pieces '+KINDS.map { |k| "#{k} #{a.kinds[k]}" }.join(' '))
    emit("best combo #{a.combo} chain #{a.chain} holds #{a.holds} drops #{a.drops} faults #{a.faults}")
    emit("garbage sent #{a.sent} cancelled #{a.cancelled} received #{a.received}")
    emit("rates app #{ratio.call(a.sent,s.pieces)} apl #{ratio.call(a.sent,s.lines)} kpp #{ratio.call(a.operations,s.pieces)}")
  end
  def command(command, args)
    s = @state
    case command
    when 'PRINT'
      current = s.ended ? Set.new : cells(s.kind,s.position).to_set
      ghost = s.ended ? Set.new : cells(s.kind,landing(s.board,s.kind,s.position)).to_set
      22.downto(1) do |r|
        row = r.to_s.rjust(2)+' '
        1.upto(10) { |c| row += (s.board[r-1] & (1 << (c-1))) != 0 ? '#' : current.include?([c,r]) ? '@' : ghost.include?([c,r]) ? '+' : '.' }
        emit(row)
      end
    when 'NEXT'; emit("hold #{s.hold || '-'} next #{s.queue.first(5).join}")
    when 'PREVIEW'
      n = args[0].to_i; queue = s.queue.dup; random = s.random
      while queue.length < n
        random,pieces = bag(random); queue.concat(pieces)
      end
      emit('preview '+queue.first(n).join)
    when 'STATUS'
      emit("score #{s.score} level #{s.level} lines #{s.lines} pieces #{s.pieces}")
      piece = s.ended ? '-' : "#{s.kind} #{STATES[s.position[0]]} #{s.position[1]} #{s.position[2]}"
      emit("piece #{piece} streak #{s.streak} chain #{s.chain} pending #{s.pending.sum}")
    when 'ANALYZE'
      heights,holes,bumpiness,value = evaluation(s.board,0)
      emit('heights '+heights.join(' ')); emit("holes #{holes} bumpiness #{bumpiness} value #{value}")
    when 'ROW'
      r = args[0].to_i; pattern = args[1]
      if cells(s.kind,s.position).any? { |c,row| row == r && pattern[c-1] == '#' }
        emit('ERROR overlap')
      else
        s.board[r-1] = pattern.chars.each_with_index.sum { |ch,i| ch == '#' ? 1 << i : 0 }; emit('OK')
      end
    when 'GARBAGE'
      n,hole = args.map(&:to_i); insert_garbage(n,hole)
      0.upto(n) do |j|
        position = [s.position[0],s.position[1],s.position[2]+j]
        if fits?(s.board,s.kind,position)
          s.position = position; emit('OK'); return
        end
      end
      over('top out')
    when 'ATTACK'; s.pending << args[0].to_i; emit("pending #{s.pending.sum}")
    when 'TICK'; args[0].to_i.times { tick }
    when 'UNDO'
      if @history.empty?
        emit('ERROR nothing to undo')
      else
        @state = copy(@history.pop); @start = copy(@state); emit("undo #{@state.pieces} #{@state.kind}")
      end
    when 'SAVE'; @saves[args[0]] = copy([s,@history,@start]); emit('OK')
    when 'LOAD'
      if @saves.key?(args[0])
        @state,@history,@start = copy(@saves[args[0]]); emit("load #{@state.pieces} #{@state.kind}")
      else
        emit('ERROR unknown save')
      end
    when 'SPINS'; spins
    when 'HINT'; ranked.first(args[0].to_i).each_with_index { |c,i| emit("hint #{i+1} #{c.kind} #{c.keys.join(' ')} value #{c.value}") }
    when 'AUTO'
      args[0].to_i.times do
        best = ranked.first; emit("auto #{best.kind} #{best.keys.join(' ')}")
        best.keys.each { |op| operation(op) }
      end
    end
  end
end

def valid_arguments?(command, args)
  number = ->(text,low,high) { /\A(?:0|[1-9][0-9]*)\z/.match?(text) && text.to_i.between?(low,high) }
  case command
  when 'NEW'; args.length == 2 && number.call(args[0],1,2147483646) && number.call(args[1],1,15)
  when 'ROW'; args.length == 2 && number.call(args[0],1,22) && /\A[#.]{10}\z/.match?(args[1]) && args[1].include?('.')
  when 'GARBAGE'; args.length == 2 && number.call(args[0],1,10) && number.call(args[1],1,10)
  when 'SAVE','LOAD'; args.length == 1 && /\A[a-z]{1,8}\z/.match?(args[0])
  when 'PREVIEW','ATTACK','TICK','HINT','AUTO'
    args.length == 1 && number.call(args[0],1,{'PREVIEW'=>14,'ATTACK'=>20,'TICK'=>1000,'HINT'=>10,'AUTO'=>50}[command])
  else; args.empty?
  end
end
lines = $stdin.each_line.map(&:chomp)
game = nil; serial = 0
lines.drop(1).first(lines[0].to_i).each do |line|
  command,*args = line.split(' ')
  begin
    if COMMANDS.include?(command)
      if !valid_arguments?(command,args)
        emit('ERROR bad arguments')
      elsif command == 'NEW'
        if game && !game.state.ended
          emit('game stopped'); game.summary
        end
        serial += 1; emit("game #{serial} seed #{args[0].to_i} level #{args[1].to_i}"); game = Game.new(serial,args[0].to_i,args[1].to_i)
      elsif !game
        emit('ERROR no game')
      elsif game.state.ended && !AFTER_END.include?(command)
        emit('ERROR game over')
      else
        game.command(command,args)
      end
    else
      invalid = [command,*args].find { |word| !OPERATIONS.include?(word) }
      if invalid
        emit('ERROR unknown '+invalid)
      elsif !game
        emit('ERROR no game')
      elsif game.state.ended
        emit('ERROR game over')
      else
        [command,*args].each { |op| game.operation(op) }
      end
    end
  rescue GameOver
  end
end
if game && !game.state.ended
  emit('game stopped'); game.summary
end
$stdout.write(OUTPUT.join("\n")+"\n") unless OUTPUT.empty?
