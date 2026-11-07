def copy(value)
  Marshal.load(Marshal.dump(value))
end

def initial(score = [0,0])
  own = Array.new(26,0)
  {24=>2,13=>5,8=>3,6=>5}.each { |p,n| own[p] = n }
  {pos:[own.dup,own.dup],side:0,cube:1,owner:-1,pending:false,over:false,score:score.dup}
end

def color(x)
  x == 0 ? 'W' : 'B'
end

def position_key(pos)
  pos.flatten.join(',')
end

def notation(moves, hits)
  key = moves.map(&:dup).sort.reverse
  loop do
    index = key.index { |s,t| t > 0 && !hits.include?(t) && key.any? { |a,_| a == t } }
    break unless index
    a = key.delete_at(index)
    other = key.index { |s,_| s == a[1] }
    b = key.delete_at(other)
    key << [a[0],b[1]]
    key.sort!.reverse!
  end
  parts, marked, i = [],[],0
  while i < key.size
    s,t = key[i]
    j = i+1
    j += 1 while j < key.size && key[j] == key[i]
    text = "#{s == 25 ? 'bar' : s}/#{t == 0 ? 'off' : t}"
    if hits.include?(t) && !marked.include?(t)
      text += '*'
      marked << t
    end
    text += "(#{j-i})" if j-i > 1
    parts << text
    i = j
  end
  [key, parts.empty? ? 'none' : parts.join(' ')]
end

def enumerate(pos, side, d1, d2)
  all = []
  dice = d1 == d2 ? Array.new(4,d1) : [d1,d2]
  visit = lambda do |board, remaining, moves, hits, used|
    key,text = notation(moves,hits)
    all << {pos:board,key:key,text:text,count:moves.size,used:used,id:position_key(board)}
    own, opponent = board[side],board[1-side]
    remaining.uniq.each do |d|
      sources = own[25] > 0 ? [25] : (1..24).select { |p| own[p] > 0 }
      sources.each do |s|
        t = [0,s-d].max
        if t > 0
          next if opponent[25-t] >= 2
        else
          next if own[25] > 0 || (7..24).any? { |p| own[p] > 0 }
          next if s < d && ((s+1)..6).any? { |p| own[p] > 0 }
        end
        next_board = board.map(&:dup)
        next_board[side][s] -= 1
        next_board[side][t] += 1
        next_hits = hits.dup
        if t > 0 && opponent[25-t] == 1
          next_board[1-side][25-t] = 0
          next_board[1-side][25] += 1
          next_hits << t unless next_hits.include?(t)
        end
        rest = remaining.dup
        rest.delete_at(rest.index(d))
        visit.call(next_board,rest,moves+[[s,t]],next_hits,used+[d])
      end
    end
  end
  visit.call(pos,dice,[],[],[])
  maximum = all.map { |p| p[:count] }.max
  candidates = all.select { |p| p[:count] == maximum }
  if maximum == 1 && d1 != d2 && candidates.any? { |p| p[:used][0] == [d1,d2].max }
    candidates.select! { |p| p[:used][0] == [d1,d2].max }
  end
  unique = {}
  candidates.each { |p| unique[p[:id]] ||= p }
  legal = unique.values.sort { |a,b| b[:key] <=> a[:key] }
  [legal,all,maximum]
end

def pips(own)
  (1..25).sum { |p| p*own[p] }
end

def evaluation(pos, side)
  own, opponent = pos[side],pos[1-side]
  p = pips(opponent)-pips(own)
  s = 0
  (1..24).each do |point|
    next unless own[point] == 1
    distances = (0...point).select { |q| opponent[25-q] > 0 }.map { |q| point-q }
    (1..6).each do |a|
      (1..6).each do |b|
        if distances.include?(a) || distances.include?(b) || distances.include?(a+b) || (a == b && (distances.include?(3*a) || distances.include?(4*a)))
          s += 1
        end
      end
    end
  end
  home = (1..6).count { |i| own[i] >= 2 }
  anchors = (19..24).count { |i| own[i] >= 2 }
  run, prime = 0,0
  (1..24).each { |i| run = own[i] >= 2 ? run+1 : 0; prime = [prime,run].max }
  bar = opponent[25]-own[25]
  [2*p-s+4*home+3*prime+3*anchors+6*bar,p,s,home,prime,anchors,bar]
end

def keith(own)
  pips(own)+2*[own[1]-1,0].max+[own[2]-1,0].max+[own[3]-3,0].max+(4..6).count { |i| own[i] == 0 }
end

def contact(pos)
  w = pos[0][25] > 0 ? 25 : ((1..24).select { |p| pos[0][p] > 0 }.max || 0)
  b = pos[1][25] > 0 ? 0 : (25-((1..24).select { |p| pos[1][p] > 0 }.max || 0))
  w > b
end

def cube_decision(state, forbidden = false)
  x = state[:side]
  return 'unavailable' if state[:owner] == 1-x || state[:cube] == 64 || forbidden
  if contact(state[:pos])
    value = evaluation(state[:pos],x)[0]
    return 'no double' if value < 60
    value <= 100 ? 'double take' : 'double drop'
  else
    value = 8*keith(state[:pos][x])-7*keith(state[:pos][1-x])
    limit = state[:owner] == -1 ? 28 : 21
    return 'no double' if value > limit
    value >= 14 ? 'double take' : 'double drop'
  end
end

def end_game(state,winner,kind = nil)
  unless kind
    opponent = state[:pos][1-winner]
    kind = if opponent[0] > 0 then 'single'
           elsif opponent[25] > 0 || (19..24).any? { |p| opponent[p] > 0 } then 'backgammon'
           else 'gammon'
           end
  end
  multiplier = {'single'=>1,'gammon'=>2,'backgammon'=>3,'drop'=>1}[kind]
  points = state[:cube]*multiplier
  state[:pending], state[:over] = false,true
  state[:score][winner] += points
  [winner,kind,points]
end

def apply_play(state,play)
  state[:pos] = copy(play[:pos])
  if state[:pos][state[:side]][0] == 15
    end_game(state,state[:side])
  else
    state[:side] = 1-state[:side]
    nil
  end
end

def ranked(legal,side)
  legal.each_with_index.map { |p,i| [evaluation(p[:pos],side)[0],i,p] }.sort_by { |e,i,_| [-e,i] }
end

def parse_play(tokens)
  return [] if tokens == ['none']
  moves = []
  tokens.each do |token|
    match = token.match(/\A(.+?)(?:\(([234])\))?\z/)
    raise 'syntax' unless match
    path = match[1].split('/',-1)
    raise 'syntax' if path.size < 2
    values = path.each_with_index.map do |word,i|
      if i == 0
        if word == 'bar' then 25
        elsif word.match?(/\A(?:[1-9]|1[0-9]|2[0-4])\z/) then word.to_i
        else raise 'syntax'
        end
      else
        if word == 'off' then 0
        elsif word.match?(/\A(?:[1-9]|1[0-9]|2[0-4])\*?\z/) then word.to_i
        else raise 'syntax'
        end
      end
    end
    raise 'syntax' unless values.each_cons(2).all? { |s,t| s > t }
    values.each_cons(2) { |pair| (match[2] || '1').to_i.times { moves << pair } }
  end
  moves
end

class RandomStream
  def initialize(seed)
    @value = seed
  end
  def next_value
    @value = @value*48271%2147483647
  end
  def die
    next_value%6+1
  end
end

def simulate(state,rng,strategies,opening = false,target = nil,scores = nil,crawford = false,verbose = false)
  state = copy(state)
  dice = nil
  if opening
    loop do
      dice = [rng.die,rng.die]
      break if dice[0] != dice[1]
    end
    state[:side] = dice[0] > dice[1] ? 0 : 1
  end
  first, turn, plays = state[:side],1,0
  loop do
    x = state[:side]
    unless opening && turn == 1
      forbidden = target && (crawford || scores[x]+state[:cube] >= target)
      decision = cube_decision(state,forbidden)
      if decision.start_with?('double')
        puts "#{turn} #{color(x)} doubles #{state[:cube]*2}" if verbose
        if decision == 'double drop'
          puts "#{turn} #{color(1-x)} drops" if verbose
          return [end_game(state,x,'drop'),plays,first]
        end
        puts "#{turn} #{color(1-x)} takes" if verbose
        state[:cube] *= 2
        state[:owner] = 1-x
      end
      dice = [rng.die,rng.die]
    end
    legal = enumerate(state[:pos],x,*dice)[0]
    play = case strategies[x]
           when 'FIRST' then legal[0]
           when 'RANDOM' then legal[rng.next_value%legal.size]
           else ranked(legal,x)[0][2]
           end
    puts "#{turn} #{color(x)} #{dice[0]}-#{dice[1]} #{play[:text]}" if verbose
    result = apply_play(state,play)
    plays += 1
    return [result,plays,first] if result
    turn += 1
  end
end

def result_line(result)
  "result #{color(result[0])} #{result[1]} #{result[2]}"
end

def numeric(s,lo,hi)
  s && s.match?(/\A\d+\z/) && s.to_i.between?(lo,hi)
end

state, history, redo_list = initial,[],[]
noargs = %w[NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY]
known = noargs + %w[POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS]
limited = %w[RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME]
pending_limited = %w[PLAY AUTO CUBE DOUBLE RESIGN GAME]
STDIN.gets.to_i.times do
  command, *args = STDIN.gets.chomp.split
  begin
    raise 'ERROR unknown command' unless known.include?(command)
    valid = true
    if noargs.include?(command)
      valid = args.empty?
    else
      case command
      when 'POS'
        points = (args[0] || '').split(',').map(&:to_i)
        valid = args.size == 4 && points.size == 24 && numeric(args[1],0,15) && numeric(args[2],0,15) && %w[W B].include?(args[3])
        if valid
          pos = [Array.new(26,0),Array.new(26,0)]
          points.each_with_index { |n,i| n > 0 ? pos[0][i+1] = n : pos[1][24-i] = -n }
          pos[0][25],pos[1][25] = args[1].to_i,args[2].to_i
          2.times { |x| pos[x][0] = 15-pos[x].sum }
          valid = pos.all? { |own| own[0].between?(0,14) }
        end
      when 'MOVES','AUTO','PLAY','HINT'
        valid = numeric(args[0],1,6) && numeric(args[1],1,6)
        valid &&= case command
                  when 'PLAY' then args.size >= 3
                  when 'HINT' then args.size == 3 && numeric(args[2],1,1000)
                  else args.size == 2
                  end
      when 'RESIGN' then valid = args.size == 1 && %w[single gammon backgammon].include?(args[0])
      when 'UNDO','REDO' then valid = args.size == 1 && numeric(args[0],1,1000)
      when 'GAME' then valid = args.size == 3 && numeric(args[0],1,2147483646) && args.drop(1).all? { |s| %w[BEST FIRST RANDOM].include?(s) }
      when 'MATCH','STATS' then valid = args.size == 2 && numeric(args[0],1,command == 'MATCH' ? 15 : 50) && numeric(args[1],1,2147483646)
      end
    end
    raise(command == 'POS' ? 'ERROR bad position' : 'ERROR bad arguments') unless valid
    raise 'ERROR game over' if limited.include?(command) && state[:over]
    raise 'ERROR double pending' if pending_limited.include?(command) && state[:pending]
    side = state[:side]
    case command
    when 'NEW','POS'
      state = initial(state[:score])
      if command == 'POS'
        state[:pos],state[:side] = pos,args[3] == 'W' ? 0 : 1
      end
      history,redo_list = [],[]
      puts 'OK'
    when 'SHOW'
      points = (1..24).map { |p| state[:pos][0][p]-state[:pos][1][25-p] }
      puts "POS #{points.join(',')} #{state[:pos][0][25]} #{state[:pos][1][25]} #{color(side)}"
    when 'BOARD'
      line = lambda do |points,row = nil|
        fields = points.map do |p|
          if row
            w,b = state[:pos][0][p],state[:pos][1][25-p]
            count = [w,b].max
            value = row == 5 && count > 5 ? count : (count >= row ? (w > 0 ? 'W' : 'B') : '.')
          else value = p
          end
          value.to_s.rjust(3)
        end
        puts fields[0,6].join+' |'+fields[6,6].join
      end
      line.call((13..24).to_a)
      (1..5).each { |r| line.call((13..24).to_a,r) }
      owner = state[:owner] == -1 ? 'center' : color(state[:owner])
      status = state[:over] ? 'game over' : "#{color(side)} #{state[:pending] ? 'doubles' : 'to move'}"
      puts "bar W#{state[:pos][0][25]} B#{state[:pos][1][25]} | off W#{state[:pos][0][0]} B#{state[:pos][1][0]} | cube #{state[:cube]} #{owner} | #{status}"
      5.downto(1) { |r| line.call((1..12).to_a.reverse,r) }
      line.call((1..12).to_a.reverse)
    when 'PIPS' then puts "pips W #{pips(state[:pos][0])} B #{pips(state[:pos][1])}"
    when 'RACE' then puts(contact(state[:pos]) ? 'contact' : "race W #{keith(state[:pos][0])} B #{keith(state[:pos][1])}")
    when 'EVAL'
      values = evaluation(state[:pos],side)
      puts %w[eval pips blots home prime anchors bar].zip(values).map { |label,v| "#{label} #{v}" }.join(' ')
    when 'MOVES','HINT','AUTO','PLAY'
      d1,d2 = args[0,2].map(&:to_i)
      legal,all,maximum = enumerate(state[:pos],side,d1,d2)
      if command == 'MOVES'
        legal.each { |p| puts p[:text] }
        puts "total #{legal.size}"
      elsif command == 'HINT'
        ranked(legal,side).first(args[2].to_i).each { |value,_,play| puts "#{value} #{play[:text]}" }
      else
        if command == 'AUTO'
          value,_,play = ranked(legal,side)[0]
        else
          begin
            moves = parse_play(args.drop(2))
          rescue RuntimeError
            raise 'ILLEGAL syntax'
          end
          final = copy(state[:pos])
          destinations = []
          moves.each { |s,t| final[side][s] -= 1; final[side][t] += 1; destinations << t if t > 0 }
          destinations.uniq.each do |t|
            if state[:pos][1-side][25-t] == 1
              final[1-side][25-t] = 0
              final[1-side][25] += 1
            end
          end
          raise 'ILLEGAL no checker' if (1..25).any? { |p| final[side][p] < 0 }
          raise 'ILLEGAL bar' if final[side][25] > 0 && moves.any? { |s,_| s != 25 }
          raise 'ILLEGAL blocked' if destinations.any? { |t| state[:pos][1-side][25-t] >= 2 }
          raise 'ILLEGAL bear-off' if moves.any? { |_,t| t == 0 } && (final[side][25] > 0 || (7..24).any? { |p| final[side][p] > 0 })
          key = position_key(final)
          play = legal.find { |p| p[:id] == key }
          unless play
            possible = all.select { |p| p[:id] == key }
            raise 'ILLEGAL impossible' if possible.empty?
            raise(possible.any? { |p| p[:count] < maximum } ? 'ILLEGAL too few dice' : 'ILLEGAL larger die required')
          end
        end
        before = copy(state)
        result = apply_play(state,play)
        puts "OK #{play[:text]}#{command == 'AUTO' ? " eval #{value}" : ''}"
        puts result_line(result) if result
        history << ["#{color(side)} #{d1}-#{d2} #{play[:text]}",before,copy(state)]
        redo_list = []
      end
    when 'SHOTS'
      blots = (1..24).select { |p| state[:pos][side][p] == 1 }.reverse
      counts = blots.to_h { |p| [p,0] }
      total,rolls = 0,[]
      6.downto(1) do |a|
        a.downto(1) do |b|
          legal = enumerate(state[:pos],1-side,a,b)[0]
          hit = blots.select { |p| legal.any? { |play| play[:pos][side][p] == 0 } }
          weight = a == b ? 1 : 2
          unless hit.empty?
            total += weight
            rolls << "#{a}-#{b}"
            hit.each { |p| counts[p] += weight }
          end
        end
      end
      puts (["shots #{total}/36"]+rolls).join(' ')
      blots.each { |p| puts "blot #{p} #{counts[p]}/36" }
    when 'CUBE' then puts "cube #{cube_decision(state)}"
    when 'DOUBLE'
      raise 'ERROR cube unavailable' if state[:owner] == 1-side || state[:cube] == 64
      state[:pending] = true
      redo_list = []
      puts "OK double #{state[:cube]*2}"
    when 'TAKE','DROP'
      raise 'ERROR no double' unless state[:pending]
      redo_list = []
      state[:pending] = false
      if command == 'TAKE'
        state[:cube] *= 2
        state[:owner] = 1-side
        puts "OK take #{state[:cube]} #{color(1-side)}"
      else
        puts 'OK drop'
        puts result_line(end_game(state,side,'drop'))
      end
    when 'RESIGN'
      redo_list = []
      puts 'OK resign'
      puts result_line(end_game(state,1-side,args[0]))
    when 'SCORE' then puts "score W #{state[:score][0]} B #{state[:score][1]}"
    when 'HISTORY'
      puts "history #{history.size}"
      history.each_with_index { |entry,i| puts "#{i+1} #{entry[0]}" }
    when 'UNDO','REDO'
      count = args[0].to_i
      if command == 'UNDO'
        raise 'ERROR cannot undo' if count > history.size
        entries = history.pop(count)
        state = copy(entries[0][1])
        redo_list = entries+redo_list
      else
        raise 'ERROR cannot redo' if count > redo_list.size
        entries = redo_list.shift(count)
        state = copy(entries[-1][2])
        history.concat(entries)
      end
      puts 'OK'
    when 'GAME'
      result, = simulate(state,RandomStream.new(args[0].to_i),args.drop(1),false,nil,nil,false,true)
      puts result_line(result)
    when 'MATCH','STATS'
      count,seed = args.map(&:to_i)
      rng = RandomStream.new(seed)
      points,turns,game,crawford_used = [0,0],0,0,false
      outcomes = %w[single gammon backgammon drop].to_h { |k| [k,[0,0]] }
      loop do
        break if command == 'STATS' ? game == count : points.max >= count
        game += 1
        crawford = command == 'MATCH' && !crawford_used && points.max == count-1
        crawford_used ||= crawford
        result,played,first = simulate(initial,rng,%w[BEST BEST],true,command == 'MATCH' ? count : nil,points,crawford)
        winner,kind,value = result
        points[winner] += value
        outcomes[kind][winner] += 1
        turns += played
        puts "game #{game}#{crawford ? ' crawford' : ''} start #{color(first)} turns #{played} #{result_line(result)} score #{points.join('-')}" if command == 'MATCH'
      end
      if command == 'MATCH'
        puts "match #{color(points[0] >= count ? 0 : 1)} #{points.join('-')}"
      else
        outcomes.each { |kind,values| puts "#{kind} W #{values[0]} B #{values[1]}" }
        puts "points W #{points[0]} B #{points[1]}"
        puts "turns #{turns}"
      end
    end
  rescue RuntimeError => e
    puts e.message
  end
end
