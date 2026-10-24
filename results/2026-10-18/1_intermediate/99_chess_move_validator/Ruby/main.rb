FILES='abcdefgh'; RANKS='12345678'; INITIAL='rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
ROOK=[[0,1],[0,-1],[-1,0],[1,0]].freeze; BISHOP=[[1,1],[-1,1],[1,-1],[-1,-1]].freeze
KING=(ROOK+BISHOP).freeze; KNIGHT=[[1,2],[2,1],[2,-1],[1,-2],[-1,-2],[-2,-1],[-2,1],[-1,2]].freeze
RULES={'K'=>[4,7,6,5,[5,6]],'Q'=>[4,0,2,3,[1,2,3]],'k'=>[60,63,62,61,[61,62]],'q'=>[60,56,58,59,[57,58,59]]}.freeze
Move=Struct.new(:source,:target,:promotion)
Record=Struct.new(:san,:uci,:captured)
def opposite(c) = c=='w' ? 'b' : 'w'
def color(p) = p==p.upcase ? 'w' : 'b'
def colored(p,c) = c=='w' ? p : p.downcase
def step(c) = c=='w' ? 8 : -8
def square(s) = /\A[a-h][1-8]\z/.match?(s) ? FILES.index(s[0])+8*RANKS.index(s[1]) : -1
def name(s) = FILES[s%8]+RANKS[s/8]
def number(s,lo,hi) = /\A(?:0|[1-9][0-9]*)\z/.match?(s) && (lo..hi).cover?(s.to_i) ? s.to_i : -1
def shift(s,dx,dy)
  x=s%8+dx; y=s/8+dy; (0...8).cover?(x) && (0...8).cover?(y) ? 8*y+x : -1
end
def targets(board,s)
  p=board[s]; kind=p.upcase
  if %w[P N K].include?(kind)
    directions=kind=='P' ? [[-1,color(p)=='w' ? 1 : -1],[1,color(p)=='w' ? 1 : -1]] : kind=='N' ? KNIGHT : KING
    return directions.map { |dx,dy| shift(s,dx,dy) }.select { |t| t>=0 }
  end
  directions=kind=='Q' ? KING : kind=='R' ? ROOK : BISHOP; result=[]
  directions.each do |dx,dy|
    t=shift(s,dx,dy)
    while t>=0
      result<<t; break if board[t]!='.'
      t=shift(t,dx,dy)
    end
  end
  result
end
def attackers(board,t,c) = (0...64).select { |s| board[s]!='.' && color(board[s])==c && targets(board,s).include?(t) }
class Position
  attr_reader :board,:side,:rights,:ep,:half,:full
  def initialize(board,side,rights,ep,half,full)
    @board,@side,@rights,@ep,@half,@full=board,side,rights,ep,half,full; @legal=nil
  end
  def check(c=@side) = !attackers(@board,@board.index(colored('K',c)),opposite(c)).empty?
  def castle(m) = @board[m.source].upcase=='K' && (m.target-m.source).abs==2
  def enpassant(m) = @board[m.source].upcase=='P' && m.source%8!=m.target%8 && @board[m.target]=='.'
  def capture(m) = @board[m.target]!='.' || enpassant(m)
  def captured(m) = @board[m.target]!='.' ? @board[m.target].downcase : enpassant(m) ? 'p' : '-'
  def play(m)
    b=@board.dup; piece=b[m.source]; kind=piece.upcase
    b[m.target-step(@side)]='.' if enpassant(m)
    if castle(m)
      r=RULES[colored(m.target>m.source ? 'K' : 'Q',@side)]; b[r[3]]=b[r[1]]; b[r[1]]='.'
    end
    b[m.target]=m.promotion.empty? ? piece : colored(m.promotion,@side); b[m.source]='.'
    rights=@rights.chars.select { |r| (kind!='K'||color(r)!=@side) && ![m.source,m.target].include?(RULES[r][1]) }.join
    Position.new(b,opposite(@side),rights,kind=='P'&&(m.target-m.source).abs==16 ? (m.source+m.target)/2 : -1,kind=='P'||capture(m) ? 0 : @half+1,@full+(@side=='b' ? 1 : 0))
  end
  def pseudo
    result=[]
    @board.each_with_index do |piece,s|
      next if piece=='.'||color(piece)!=@side
      pawn=piece.upcase=='P'; a=[]
      if pawn
        d=step(@side)
        if @board[s+d]=='.'
          a<<s+d; a<<s+2*d if s/8==(@side=='w' ? 1 : 6)&&@board[s+2*d]=='.'
        end
        a+=targets(@board,s).select { |t| (@board[t]!='.'&&color(@board[t])!=@side)||t==@ep }
      else a=targets(@board,s).select { |t| @board[t]=='.'||color(@board[t])!=@side } end
      a.each { |t| (pawn&&t/8==(@side=='w' ? 7 : 0) ? %w[Q R B N] : ['']).each { |p| result<<Move.new(s,t,p) } }
    end
    result
  end
  def castling_move(kingside)
    r=RULES[colored(kingside ? 'K' : 'Q',@side)]; Move.new(r[0],r[2],'')
  end
  def castling_problem(kingside)
    right=colored(kingside ? 'K' : 'Q',@side); r=RULES[right]
    return 'no castling right' unless @rights.include?(right)
    return 'path blocked' if r[4].any? { |s| @board[s]!='.' }
    return 'in check' if check
    return 'through check' unless attackers(@board,r[3],opposite(@side)).empty?
    return 'into check' if play(castling_move(kingside)).check(@side)
    nil
  end
  def legal
    @legal||=begin
      a=pseudo.select { |m| !play(m).check(@side) }; [true,false].each { |k| a<<castling_move(k) unless castling_problem(k) }; a
    end
  end
  def mark(m)
    q=play(m); q.check ? (q.legal.empty? ? '#' : '+') : ''
  end
  def disambiguation(m)
    others=legal.select { |x| !castle(x)&&x.target==m.target&&x.source!=m.source&&@board[x.source]==@board[m.source] }
    return '' if others.empty?
    return FILES[m.source%8] if others.all? { |x| x.source%8!=m.source%8 }
    return RANKS[m.source/8] if others.all? { |x| x.source/8!=m.source/8 }
    name(m.source)
  end
  def san(m)
    kind=@board[m.source].upcase
    text=if castle(m) then m.target>m.source ? 'O-O' : 'O-O-O'
         elsif kind=='P' then (capture(m) ? FILES[m.source%8]+'x' : '')+name(m.target)+(m.promotion.empty? ? '' : '='+m.promotion)
         else kind+disambiguation(m)+(capture(m) ? 'x' : '')+name(m.target) end
    text+mark(m)
  end
  def key = [@board,@side,@rights,(@ep>=0&&legal.any? { |m| enpassant(m) } ? @ep : -1)]
  def state = check ? (legal.empty? ? 'checkmate' : 'check') : (legal.empty? ? 'stalemate' : 'normal')
  def insufficient
    a=(0...64).select { |s| @board[s]!='.'&&@board[s].upcase!='K' }
    return false if a.any? { |s| 'PRQ'.include?(@board[s].upcase) }
    a.size<=1 || a.all? { |s| @board[s].upcase=='B' }&&a.map { |s| (s%8+s/8)%2 }.uniq.size==1
  end
  def pins
    king=@board.index(colored('K',@side)); found=[]
    KING.each do |dx,dy|
      first=-1; t=shift(king,dx,dy)
      while t>=0
        p=@board[t]
        if p!='.'
          if first<0 then break if color(p)!=@side; first=t
          else
            found<<[first,t] if color(p)!=@side&&('Q'+(dx==0||dy==0 ? 'R' : 'B')).include?(p.upcase)
            break
          end
        end
        t=shift(t,dx,dy)
      end
    end
    found.sort
  end
  def fen
    rows=7.downto(0).map { |r| @board[r*8,8].join.gsub(/\.+/) { |run| run.size.to_s } }
    [rows.join('/'),@side,@rights.empty? ? '-' : @rights,@ep<0 ? '-' : name(@ep),@half,@full].join(' ')
  end
end
def parse_fen(a)
  raise 'fields' unless a.size==6
  ranks=a[0].split('/',-1); raise 'placement' unless ranks.size==8
  board=Array.new(64,'.')
  ranks.each_with_index do |row,i|
    f=0; digit=false
    row.each_char do |c|
      if '12345678'.include?(c) then raise 'placement' if digit; f+=c.to_i; digit=true
      else
        raise 'placement' unless 'KQRBNPkqrbnp'.include?(c)&&f<8
        board[(7-i)*8+f]=c; f+=1; digit=false
      end
    end
    raise 'placement' unless f==8
  end
  raise 'kings' unless board.count('K')==1&&board.count('k')==1
  raise 'pawns' if (board[0,8]+board[56,8]).any? { |p| %w[P p].include?(p) }
  side=a[1]; raise 'side' unless %w[w b].include?(side)
  raise 'castling' unless a[2]=='-'||/\A(?=.)K?Q?k?q?\z/.match?(a[2])
  rights=a[2]=='-' ? '' : a[2]
  rights.each_char { |r| rule=RULES[r]; raise 'castling' unless board[rule[0]]==colored('K',color(r))&&board[rule[1]]==colored('R',color(r)) }
  ep=-1
  if a[3]!='-'
    ep=square(a[3]); d=step(side)
    raise 'en passant' unless ep>=0&&ep/8==(side=='w' ? 5 : 2)&&board[ep]=='.'&&board[ep+d]=='.'&&board[ep-d]==colored('P',opposite(side))
  end
  half=number(a[4],0,999); full=number(a[5],1,999); raise 'clocks' if half<0||full<0||(ep>=0&&half!=0)
  p=Position.new(board,side,rights,ep,half,full); raise 'check' if p.check(opposite(side)); p
end
def read_san(pos,text)
  mark=%w[+ #].include?(text[-1]) ? text[-1] : ''; body=mark.empty? ? text : text[0...-1]
  castling=%w[O-O O-O-O].include?(body); promotion=''; target=-1; capture=false; kind='P'; file=''; rank=''
  unless castling
    if body.size>=2&&body[-2]=='='
      promotion=body[-1]; raise 'syntax' unless 'QRBN'.include?(promotion); body=body[0...-2]
    end
    raise 'syntax' if body.size<2
    target=square(body[-2,2]); raise 'syntax' if target<0
    body=body[0...-2]; capture=body.end_with?('x'); body=body[0...-1] if capture
    if !body.empty?&&'KQRBN'.include?(body[0])
      kind=body[0]; hints=/\A([a-h]?)([1-8]?)\z/.match(body[1..]); raise 'syntax' unless hints&&promotion.empty?; file=hints[1]; rank=hints[2]
    else
      raise 'syntax' unless (capture ? /\A[a-h]\z/ : /\A\z/).match?(body); file=body
    end
  end
  legal=pos.legal; raise 'game over' if legal.empty?
  if castling
    kingside=body=='O-O'; problem=pos.castling_problem(kingside); raise problem if problem; move=pos.castling_move(kingside)
  else
    matches=->(m) { pos.board[m.source].upcase==kind&&m.target==target&&!pos.castle(m)&&(file.empty?||FILES[m.source%8]==file)&&(rank.empty?||RANKS[m.source/8]==rank)&&(kind!='P'||(m.source%8!=m.target%8)==capture) }
    candidates=legal.select(&matches); raise(pos.pseudo.any?(&matches) ? 'leaves king in check' : 'no such move') if candidates.empty?
    raise 'ambiguous' if candidates.map(&:source).uniq.size>1
    move=candidates[0]; raise 'capture mark' if pos.capture(move)!=capture
    raise 'missing promotion' if !move.promotion.empty?&&promotion.empty?
    raise 'invalid promotion' if !promotion.empty?&&move.promotion.empty?
    raise 'disambiguation' if kind!='P'&&file+rank!=pos.disambiguation(move)
    move=Move.new(move.source,move.target,promotion)
  end
  raise 'check mark' if pos.mark(move)!=mark
  move
end
def read_uci(pos,text)
  raise 'syntax' unless /\A[a-h][1-8][a-h][1-8][qrbn]?\z/.match?(text)
  s=square(text[0,2]); t=square(text[2,2]); promotion=text[4..].upcase; legal=pos.legal
  raise 'game over' if legal.empty?
  raise 'no piece' if pos.board[s]=='.'||color(pos.board[s])!=pos.side
  move=legal.find { |m| m.source==s&&m.target==t }
  raise(pos.pseudo.any? { |m| m.source==s&&m.target==t } ? 'leaves king in check' : 'no such move') unless move
  raise 'missing promotion' if !move.promotion.empty?&&promotion.empty?
  raise 'invalid promotion' if !promotion.empty?&&move.promotion.empty?
  Move.new(s,t,promotion)
end
def perft(p,d,stats=nil)
  return 1 if d==0
  p.legal.sum do |m|
    q=p.play(m); n=perft(q,d-1,stats)
    if d==1&&stats
      stats[0]+=1; stats[1]+=1 if p.capture(m); stats[2]+=1 if p.enpassant(m); stats[3]+=1 if p.castle(m); stats[4]+=1 unless m.promotion.empty?
      if q.check then stats[5]+=1; stats[6]+=1 if q.legal.empty? end
    end
    n
  end
end
class Game
  attr_reader :positions,:records,:loaded
  def initialize(start=parse_fen(INITIAL.split(' ')),loaded=false) = (@positions=[start]; @records=[]; @loaded=loaded)
  def current = @positions[-1]
  def play(m)
    p=current; @records<<Record.new(p.san(m),name(m.source)+name(m.target)+m.promotion.downcase,p.captured(m)); @positions<<p.play(m)
  end
  def repetition = @positions.count { |p| p.key==current.key }
  def draws
    a=[]; a<<'fifty' if current.half>=100; a<<'threefold' if repetition>=3; a<<'insufficient' if current.insufficient; a
  end
  def result = current.state=='checkmate' ? (current.side=='b' ? '1-0' : '0-1') : current.state=='stalemate'||!draws.empty? ? '1/2-1/2' : '*'
end
class Session
  def initialize = (@game=Game.new)
  def execute(line)
    cmd,*a=line.split(' '); commands=%w[NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN]
    unless commands.include?(cmd) then puts 'ERROR unknown command'; return end
    bad=%w[NEW FEN BOARD STATUS PINS HISTORY PGN].include?(cmd)&&!a.empty? || %w[MOVE UCI].include?(cmd)&&a.empty?
    bad=a.size>1||(a.size==1&&square(a[0])<0) if cmd=='LEGAL'
    bad=a.size!=1||(a.size==1&&square(a[0])<0) if cmd=='ATTACKS'
    n=-1
    if %w[UNDO PERFT DIVIDE].include?(cmd) then n=a.size==1 ? number(a[0],1,cmd=='UNDO' ? 9999 : 3) : -1; bad=n<0 end
    if bad then puts 'ERROR bad arguments'; return end
    p=@game.current
    case cmd
    when 'NEW' then @game=Game.new; puts 'OK'
    when 'LOAD'
      begin q=parse_fen(a); @game=Game.new(q,true); puts 'OK'
      rescue RuntimeError=>e then puts "ERROR bad fen (#{e.message})" end
    when 'FEN' then puts p.fen
    when 'BOARD'
      7.downto(0) { |r| puts ([r+1]+p.board[r*8,8]).join(' ') }; puts '  a b c d e f g h'
    when 'MOVE','UCI'
      played=[]; failure=nil
      a.each_with_index do |text,i|
        begin m=cmd=='MOVE' ? read_san(@game.current,text) : read_uci(@game.current,text); @game.play(m); played<<@game.records[-1].san
        rescue RuntimeError=>e then failure="ILLEGAL move #{i+1}: #{text} (#{e.message})"; break end
      end
      puts 'san '+played.join(' ') if cmd=='UCI'&&!played.empty?
      if failure then puts failure elsif cmd=='MOVE' then puts 'OK' end
    when 'LEGAL'
      from=a.empty? ? -1 : square(a[0]); list=p.legal.select { |m| from<0||m.source==from }.map { |m| p.san(m) }.sort; puts (['legal',list.size]+list).join(' ')
    when 'STATUS' then puts (['status',p.side=='w' ? 'white' : 'black',p.state,'rep',@game.repetition]+@game.draws).join(' ')
    when 'UNDO'
      if n>@game.records.size then puts 'ERROR cannot undo'
      else @game.records.slice!(-n,n); @game.positions.slice!(-n,n); puts 'OK' end
    when 'PERFT'
      stats=Array.new(7,0); perft(p,n,stats); puts (['perft',n]+%w[nodes captures ep castles promotions checks mates].each_with_index.flat_map { |f,i| [f,stats[i]] }).join(' ')
    when 'DIVIDE'
      rows=p.legal.map { |m| [p.san(m),perft(p.play(m),n-1)] }.sort_by(&:first); rows.each { |r| puts r.join(' ') }; puts "total #{rows.sum(&:last)}"
    when 'ATTACKS'
      t=square(a[0]); white=attackers(p.board,t,'w'); black=attackers(p.board,t,'b'); puts (['attacks',a[0],'white',white.size]+white.map { |s| name(s) }+['black',black.size]+black.map { |s| name(s) }).join(' ')
    when 'PINS'
      pins=p.pins; puts (['pins',pins.size]+pins.map { |s,t| name(s)+'-'+name(t) }).join(' ')
    when 'HISTORY'
      puts "history #{@game.records.size}"; @game.records.each_with_index { |r,i| puts "#{i+1} #{r.uci} #{r.san} #{r.captured}" }
    when 'PGN'
      result=@game.result; puts "[Result \"#{result}\"]"
      if @game.loaded then puts '[SetUp "1"]'; puts "[FEN \"#{@game.positions[0].fen}\"]" end
      words=[]; @game.records.each_with_index { |r,i| q=@game.positions[i]; words<<"#{q.full}." if q.side=='w'; words<<"#{q.full}..." if q.side=='b'&&i==0; words<<r.san }; puts (words+[result]).join(' ')
    end
  end
end
lines=STDIN.each_line.map(&:chomp); session=Session.new; lines.drop(1).first(lines[0].to_i).each { |line| session.execute(line) }
