LF=:10{a.
num=:3 : ',''0'' 8!:2 y'
say=:3 : '1!:2&2 y,LF'
words=:3 : '(<;._1 '' '',y)-.<'''''
join=:4 : 0
 if. 0=#y do. '' return. end.
 (#x)}.;(<x),&.>y
)
fail=:3 : 0
 Reason=:y
 throw.
)
number=:4 : 0
 'lo hi'=.x
 if. 0=#y do. _1 return. end.
 if. (-.*./y e.'0123456789')+.((1<#y)*.'0'={.y) do. _1 return. end.
 v=.0".y
 if. (v<lo)+.v>hi do. _1 else. v end.
)
square=:3 : 0
 if. 2~:#y do. _1 return. end.
 if. (-.({.y)e.'abcdefgh')+.-.({:y)e.'12345678' do. _1 return. end.
 ('abcdefgh'i.{.y)+8*'12345678'i.{:y
)
sqname=:3 : '((8|y){''abcdefgh''),(<.y%8){''12345678'''
piecechar=:3 : 0
 if. y=0 do. '.' elseif. y>0 do. y{' PNBRQK' else. (-y){' pnbrqk' end.
)
attack=:4 : 0
 b=.x
 's t'=.y
 p=.s{b
 if. (p=0)+.s=t do. 0 return. end.
 df=.(8|t)-8|s
 dr=.(<.t%8)-<.s%8
 a=.|df
 z=.|dr
 select. |p
 case. 1 do. (a=1)*.dr=*p return.
 case. 2 do. (<a,z)e.(1 2;2 1) return.
 case. 6 do. (a<:1)*.z<:1 return.
 case. 3 do. if. a~:z do. 0 return. end.
 case. 4 do. if. (a~:0)*.z~:0 do. 0 return. end.
 case. 5 do. if. (a~:z)*.(a~:0)*.z~:0 do. 0 return. end.
 end.
 step=.(*df)+8**dr
 at=.s+step
 while. at~:t do.
  if. 0~:at{b do. 0 return. end.
  at=.at+step
 end.
 1
)
attacked=:4 : 0
 'color target'=.y
 for_s. I.color=*x do.
  if. x attack s,target do. 1 return. end.
 end.
 0
)
incheck=:4 : 0
 b=.0{::x
 king=.b i.6*y
 if. king=64 do. 1 return. end.
 b attacked (-y),king
)
iscapture=:4 : 0
 b=.0{::x
 's t promotion'=.y
 (0~:t{b)+.((1=|s{b)*.(8|s)~:8|t)
)
isep=:4 : 0
 b=.0{::x
 's t promotion'=.y
 (1=|s{b)*.(0=t{b)*.(8|s)~:8|t
)
iscastle=:4 : 0
 b=.0{::x
 's t promotion'=.y
 (6=|s{b)*.2=|t-s
)
after=:4 : 0
 'b side rights ep half full'=.x
 's t promotion'=.y
 p=.s{b
 capture=.x iscapture y
 if. x isep y do. b=.0(t-8*side)}b end.
 if. x iscastle y do.
  base=.8*<.s%8
  if. t>s do. rs=.base+7 [ rt=.base+5 else. rs=.base [ rt=.base+3 end.
  b=.(rs{b)rt}b
  b=.0 rs}b
 end.
 b=.0 s}b
 if. promotion do. p=.side*promotion end.
 b=.p t}b
 if. (1=|s{0{::x)+.capture do. half=.0 else. half=.>:half end.
 if. 6=|s{0{::x do.
  if. side=1 do. rights=.rights-.'KQ' else. rights=.rights-.'kq' end.
 end.
 for_i. i.4 do.
  if. (i{0 7 56 63)e.s,t do. rights=.rights-.i{'QKqk' end.
 end.
 ep=._1
 if. (1=|s{0{::x)*.16=|t-s do. ep=.<.(s+t)%2 end.
 b;(-side);rights;ep;half;(full+side=_1)
)
castlemove=:4 : 0
 side=.1{::x
 base=.56*side=_1
 (base+4),(base+y{6 2),0
)
castlereason=:4 : 0
 'b side rights ep half full'=.x
 right=.((2*side=_1)+y){'KQkq'
 if. -.right e.rights do. 'no castling right' return. end.
 base=.56*side=_1
 path=.base+(y{::5 6;1 2 3)
 if. +./0~:path{b do. 'path blocked' return. end.
 if. x incheck side do. 'in check' return. end.
 if. b attacked (-side),base+y{5 3 do. 'through check' return. end.
 if. (x after x castlemove y)incheck side do. 'into check' return. end.
 ''
)
pseudo=:3 : 0
 'b side rights ep half full'=.y
 moves=.0 3$0
 for_s. I.side=*b do.
  p=.|s{b
  targets=.i.0
  if. p=1 do.
   t=.s+8*side
   if. (t>:0)*.t<64 do.
    if. 0=t{b do.
     targets=.targets,t
     start=.1
     if. side=_1 do. start=.6 end.
     if. start=<.s%8 do.
      u=.s+16*side
      if. 0=u{b do. targets=.targets,u end.
     end.
    end.
   end.
   for_df. _1 1 do.
    file=.(8|s)+df
    t=.s+df+8*side
    if. (file>:0)*.(file<8)*.(t>:0)*.t<64 do.
     if. (t=ep)+.(-side)=*t{b do. targets=.targets,t end.
    end.
   end.
  else.
   for_t. I.side~:*b do.
    if. b attack s,t do. targets=.targets,t end.
   end.
  end.
  for_t. targets do.
   if. (p=1)*.(<.t%8)e.0 7 do.
    for_prom. 5 4 3 2 do. moves=.moves,s,t,prom end.
   else. moves=.moves,s,t,0 end.
  end.
 end.
 moves
)
legal=:3 : 0
 side=.1{::y
 result=.0 3$0
 for_m. pseudo y do.
  if. -. (y after m)incheck side do. result=.result,m end.
 end.
 for_k. i.2 do.
  if. 0=#y castlereason k do. result=.result,y castlemove k end.
 end.
 result
)
disambiguation=:4 : 0
 'p moves'=.x
 b=.0{::p
 's t promotion'=.y
 others=.i.0
 for_m. moves do.
  'u v pr'=.m
  if. (s~:u)*.(v=t)*.(u{b)=s{b do.
   if. -.p iscastle m do. others=.others,u end.
  end.
 end.
 if. 0=#others do. '' return. end.
 if. *./(8|others)~:8|s do. ,(8|s){'abcdefgh' return. end.
 if. *./(<.others%8)~:<.s%8 do. ,(<.s%8){'12345678' return. end.
 sqname s
)
checkmark=:4 : 0
 q=.x after y
 if. -.q incheck 1{::q do. '' return. end.
 if. #legal q do. '+' else. '#' end.
)
san=:4 : 0
 'p moves'=.x
 b=.0{::p
 's t promotion'=.y
 typ=.|s{b
 if. p iscastle y do.
  text=.(t<s){::'O-O';'O-O-O'
 else.
  text=.''
  if. typ=1 do.
   if. p iscapture y do. text=.((8|s){'abcdefgh'),'x' end.
  else.
   text=.(typ{' PNBRQK'),x disambiguation y
   if. p iscapture y do. text=.text,'x' end.
  end.
  text=.text,sqname t
  if. promotion do. text=.text,'=',promotion{' PNBRQK' end.
 end.
 text,p checkmark y
)
readuci=:4 : 0
 p=.x
 w=.y
 if. -. (#w)e.4 5 do. fail 'syntax' end.
 s=.square 2{.w
 t=.square 2{.2}.w
 if. (s<0)+.t<0 do. fail 'syntax' end.
 promotion=.0
 if. 5=#w do.
  if. -.({:w)e.'qrbn' do. fail 'syntax' end.
  promotion=.(' pnbrqk'i.{:w)
 end.
 moves=.legal p
 if. 0=#moves do. fail 'game over' end.
 if. (1{::p)~:*s{0{::p do. fail 'no piece' end.
 choices=.((s=0{"1 moves)*.t=1{"1 moves)#moves
 if. 0=#choices do.
  pm=.pseudo p
  if. +./(s=0{"1 pm)*.t=1{"1 pm do. fail 'leaves king in check' end.
  fail 'no such move'
 end.
 if. (0~:(<0,2){choices)*.promotion=0 do. fail 'missing promotion' end.
 if. (0=(<0,2){choices)*.promotion~:0 do. fail 'invalid promotion' end.
 s,t,promotion
)
matching=:4 : 0
 'p typ target file rank cap'=.x
 b=.0{::p
 result=.0 3$0
 for_m. y do.
  's t pr'=.m
  if. (t~:target)+.typ~:|s{b do. continue. end.
  if. p iscastle m do. continue. end.
  if. file~:_1 do. if. file~:8|s do. continue. end. end.
  if. rank~:_1 do. if. rank~:<.s%8 do. continue. end. end.
  if. typ=1 do. if. cap~:(8|s)~:8|t do. continue. end. end.
  result=.result,m
 end.
 result
)
readsan=:4 : 0
 p=.x
 u=.y
 mark=.''
 if. ({:u)e.'+#' do. mark=.,{:u
  u=.}:u end.
 castle=._1
 if. 'O-O'-:u do. castle=.0 elseif. 'O-O-O'-:u do. castle=.1 end.
 promotion=.0
 if. castle<0 do.
  if. 2<:#u do.
   if. '='=_2{u do.
    if. -.({:u)e.'QRBN' do. fail 'syntax' end.
    promotion=.' PNBRQK'i.{:u
    u=._2}.u
   end.
  end.
  if. 2>#u do. fail 'syntax' end.
  target=.square _2{.u
  if. target<0 do. fail 'syntax' end.
  u=._2}.u
  cap=.0
  if. #u do. if. 'x'={:u do. cap=.1 [ u=.}:u end. end.
  file=.rank=._1
  typ=.1
  if. #u do.
   if. ({.u)e.'KQRBN' do.
    typ=.' PNBRQK'i.{.u
    u=.}.u
    if. promotion do. fail 'syntax' end.
    if. #u do. if. ({.u)e.'abcdefgh' do. file=.'abcdefgh'i.{.u
     u=.}.u end. end.
    if. #u do. if. ({.u)e.'12345678' do. rank=.'12345678'i.{.u
     u=.}.u end. end.
    if. #u do. fail 'syntax' end.
   end.
  end.
  if. typ=1 do.
   if. cap do.
    if. 1~:#u do. fail 'syntax' end.
    if. -.({.u)e.'abcdefgh' do. fail 'syntax' end.
    file=.'abcdefgh'i.{.u
   elseif. #u do. fail 'syntax' end.
  end.
 end.
 moves=.legal p
 if. 0=#moves do. fail 'game over' end.
 if. castle>:0 do.
  why=.p castlereason castle
  if. #why do. fail why end.
  m=.p castlemove castle
 else.
  filter=.p;typ;target;file;rank;cap
  choices=.filter matching moves
  if. 0=#choices do.
   if. #filter matching pseudo p do. fail 'leaves king in check' end.
   fail 'no such move'
  end.
  if. 1<#~.0{"1 choices do. fail 'ambiguous' end.
  m=.0{choices
  if. cap~:p iscapture m do. fail 'capture mark' end.
  if. (0~:2{m)*.promotion=0 do. fail 'missing promotion' end.
  if. (0=2{m)*.promotion~:0 do. fail 'invalid promotion' end.
  if. typ~:1 do.
   dis=.''
   if. file>:0 do. dis=.dis,file{'abcdefgh' end.
   if. rank>:0 do. dis=.dis,rank{'12345678' end.
   if. -.dis-:(p;moves)disambiguation m do. fail 'disambiguation' end.
  end.
  m=.promotion 2}m
 end.
 if. -.mark-:p checkmark m do. fail 'check mark' end.
 m
)
fenread=:3 : 0
 if. 6~:#y do. fail 'fields' end.
 placement=.0{::y
 parts=.<;._1 '/',placement
 if. 8~:#parts do. fail 'placement' end.
 rows=.0$a:
 for_part. parts do.
  row=.i.0
  digit=.0
  for_ch. >part do.
   if. ch e.'12345678' do.
    if. digit do. fail 'placement' end.
    row=.row,('0123456789'i.ch)#0
    digit=.1
   else.
    if. -.ch e.'PNBRQKpnbrqk' do. fail 'placement' end.
    p=.1+6|'PNBRQKpnbrqk'i.ch
    if. ch e.'pnbrqk' do. p=.-p end.
    row=.row,p
    digit=.0
   end.
  end.
  if. 8~:#row do. fail 'placement' end.
  rows=.rows,<row
 end.
 b=.;|.rows
 if. (1~:+/b=6)+.1~:+/b=_6 do. fail 'kings' end.
 if. +./1=|(0 1 2 3 4 5 6 7 56 57 58 59 60 61 62 63){b do. fail 'pawns' end.
 sideword=.1{::y
 if. -.(<sideword)e.'w';'b' do. fail 'side' end.
 side=.1-2*'b'-:sideword
 rights=.2{::y
 if. '-'-:rights do. rights=.'' else.
  if. (0=#rights)+.-.rights-:('KQkq'e.rights)#'KQkq' do. fail 'castling' end.
 end.
 for_i. i.4 do.
  if. (i{'KQkq')e.rights do.
   k=.i{4 4 60 60
   r=.i{7 0 63 56
   color=.1-2*i>:2
   if. ((k{b)~:6*color)+.(r{b)~:4*color do. fail 'castling' end.
  end.
 end.
 epword=.3{::y
 ep=._1
 if. -.'-'-:epword do.
  ep=.square epword
  if. ep<0 do. fail 'en passant' end.
  rank=.5
  if. side=_1 do. rank=.2 end.
  if. rank~:<.ep%8 do. fail 'en passant' end.
  if. (0~:ep{b)+.(0~:(ep+8*side){b)+.(-side)~:(ep-8*side){b do. fail 'en passant' end.
 end.
 half=.0 999 number 4{::y
 full=.1 999 number 5{::y
 if. (half<0)+.(full<0)+.((ep>:0)*.half~:0) do. fail 'clocks' end.
 p=.b;side;rights;ep;half;full
 if. p incheck -side do. fail 'check' end.
 p
)
fen=:3 : 0
 'b side rights ep half full'=.y
 rows=.0$a:
 for_rank. |.i.8 do.
  row=.''
  zeros=.0
  for_p. (8*rank)+i.8 do.
   v=.p{b
   if. v=0 do. zeros=.>:zeros else.
    if. zeros do. row=.row,num zeros
     zeros=.0 end.
    row=.row,piecechar v
   end.
  end.
  if. zeros do. row=.row,num zeros end.
  rows=.rows,<row
 end.
 if. 0=#rights do. rights=.'-' end.
 eps=.'-'
 if. ep>:0 do. eps=.sqname ep end.
 ('/'join rows),' ',((side=_1){'wb'),' ',rights,' ',eps,' ',(num half),' ',num full
)
key=:3 : 0
 p=.y
 have=.0
 for_m. legal p do. if. p isep m do. have=.1 break. end. end.
 if. -.have do. p=.(<_1)3}p end.
 4{.p
)
state=:3 : 0
 p=.Current
 moves=.legal p
 checked=.p incheck 1{::p
 label=.'normal'
 if. checked do. label=.'check' end.
 if. 0=#moves do. label=.checked{::'stalemate';'checkmate' end.
 k=.key p
 rep=.1
 for_record. History do.
  if. k-:key 0{::>record do. rep=.>:rep end.
 end.
 marks=.0$a:
 if. 100<:4{::p do. marks=.marks,<'fifty' end.
 if. rep>:3 do. marks=.marks,<'threefold' end.
 b=.0{::p
 others=.I.(b~:0)*.6~:|b
 insufficient=.0
 if. -.+./(|b)e.1 4 5 do.
  if. 1>:#others do. insufficient=.1 elseif. *./3=|others{b do.
   colors=.2|(8|others)+<.others%8
   insufficient=.1=#~.colors
  end.
 end.
 if. insufficient do. marks=.marks,<'insufficient' end.
 result=.'*'
 if. 'checkmate'-:label do. result=.((1{::p)=_1){::'0-1';'1-0'
 elseif. ('stalemate'-:label)+.0<#marks do. result=.'1/2-1/2' end.
 label;rep;marks;result
)
play=:3 : 0
 p=.Current
 text=.(p;legal p)san y
 's t promotion'=.y
 uci=.(sqname s),sqname t
 if. promotion do. uci=.uci,promotion{' pnbrqk' end.
 captured=.'-'
 if. 0~:t{0{::p do. captured=.,(|t{0{::p){' pnbrqk'
 elseif. p isep y do. captured=.'p' end.
 History=:History,<p;text;uci;captured
 Current=:p after y
 text
)
perft=:4 : 0
 if. y=0 do. 1 0 0 0 0 0 0 return. end.
 result=.7$0
 for_m. legal x do.
  q=.x after m
  if. y=1 do.
   ch=.q incheck 1{::q
   mate=.0
   if. ch do. mate=.0=#legal q end.
   result=.result+1,(x iscapture m),(x isep m),(x iscastle m),(0~:2{m),ch,mate
  else. result=.result+q perft <:y end.
 end.
 result
)
initial=:3 : 0
 Start=:Current=:fenread words 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1'
 History=:0$a:
 Loaded=:0
)
Commands=:words 'NEW LOAD FEN BOARD MOVE UCI LEGAL STATUS UNDO PERFT DIVIDE ATTACKS PINS HISTORY PGN'
Arity=:0 _1 0 0 _2 _2 _3 0 1 1 1 1 0 0 0
command=:3 : 0
 w=.words y
 cmd=.Commands i.{.w
 if. cmd=#Commands do. fail 'ERROR unknown command' end.
 a=.}.w
 ar=.cmd{Arity
 valid=.1
 if. ar>:0 do. valid=.ar=#a elseif. ar=_2 do. valid=.0<#a elseif. ar=_3 do. valid=.1>:#a end.
 if. -.valid do. fail 'ERROR bad arguments' end.
 arg=._1
 if. cmd e.8 9 10 do.
  hi=.3
  if. cmd=8 do. hi=.9999 end.
  arg=.(1,hi)number 0{::a
  if. arg<0 do. fail 'ERROR bad arguments' end.
 end.
 if. (cmd=11)+.((cmd=6)*.0<#a) do.
  arg=.square 0{::a
  if. arg<0 do. fail 'ERROR bad arguments' end.
 end.
 select. cmd
 case. 0 do. initial 0 [ say 'OK'
 case. 1 do.
  try. p=.fenread a catcht. fail 'ERROR bad fen (',Reason,')' end.
  Start=:Current=:p
  Loaded=:1
  History=:0$a:
  say 'OK'
 case. 2 do. say fen Current
 case. 3 do.
  b=.0{::Current
  for_r. |.i.8 do.
   text=.num >:r
   for_s. (8*r)+i.8 do. text=.text,' ',piecechar s{b end.
   say text
  end.
  say '  a b c d e f g h'
 case. 4;5 do.
  played=.0$a:
  error=.''
  for_i. i.#a do.
   try.
    if. cmd=4 do. m=.Current readsan i{::a else. m=.Current readuci i{::a end.
    played=.played,<play m
   catcht.
    error=.'ILLEGAL move ',(num >:i),': ',(i{::a),' (',Reason,')'
    break.
   end.
  end.
  if. cmd=5 do. if. #played do. say 'san ',' 'join played end. end.
  if. #error do. say error elseif. cmd=4 do. say 'OK' end.
 case. 6 do.
  moves=.legal Current
  texts=.0$a:
  for_m. moves do.
   if. (arg<0)+.arg={.m do. texts=.texts,<(Current;moves)san m end.
  end.
  text=.'legal ',num #texts
  if. #texts do. text=.text,' ',' 'join /:~texts end.
  say text
 case. 7 do.
  'label rep marks result'=.state 0
  text=.'status ',(((1{::Current)=_1){::'white';'black'),' ',label,' rep ',num rep
  if. #marks do. text=.text,' ',' 'join marks end.
  say text
 case. 8 do.
  if. arg>#History do. fail 'ERROR cannot undo' end.
  n=.(#History)-arg
  Current=:0{::n{::History
  History=:n{.History
  say 'OK'
 case. 9 do.
  counts=.Current perft arg
  labels=.words 'nodes captures ep castles promotions checks mates'
  text=.'perft ',num arg
  for_i. i.7 do. text=.text,' ',(i{::labels),' ',num i{counts end.
  say text
 case. 10 do.
  moves=.legal Current
  texts=.0$a:
  for_m. moves do. texts=.texts,<(Current;moves)san m end.
  total=.0
  for_i. /:texts do.
   count=.{.(Current after i{moves)perft <:arg
   say (i{::texts),' ',num count
   total=.total+count
  end.
  say 'total ',num total
 case. 11 do.
  b=.0{::Current
  text=.'attacks ',sqname arg
  for_color. 1 _1 do.
   found=.i.0
   for_s. I.color=*b do. if. b attack s,arg do. found=.found,s end. end.
   text=.text,' ',((color=_1){::'white';'black'),' ',num #found
   for_s. found do. text=.text,' ',sqname s end.
  end.
  say text
 case. 12 do.
  b=.0{::Current
  side=.1{::Current
  king=.b i.6*side
  pairs=.0 2$0
  for_d. 8 2$0 1 0 _1 1 0 _1 0 1 1 1 _1 _1 1 _1 _1 do.
   file=.8|king
   rank=.<.king%8
   first=._1
   while. 1 do.
    file=.file+0{d
    rank=.rank+1{d
    if. (file<0)+.(file>7)+.(rank<0)+.rank>7 do. break. end.
    at=.file+8*rank
    p=.at{b
    if. p=0 do. continue. end.
    if. first<0 do.
     if. side~:*p do. break. end.
     first=.at
    else.
     typ=.4
     if. *./d~:0 do. typ=.3 end.
     if. ((-side)=*p)*.(|p)e.5,typ do. pairs=.pairs,first,at end.
     break.
    end.
   end.
  end.
  text=.'pins ',num #pairs
  for_pair. (/:pairs){pairs do. text=.text,' ',(sqname {.pair),'-',sqname {:pair end.
  say text
 case. 13 do.
  say 'history ',num #History
  for_i. i.#History do.
   'p santext uci capture'=.i{::History
   say (num >:i),' ',uci,' ',santext,' ',capture
  end.
 case. 14 do.
  'label rep marks result'=.state 0
  say '[Result "',result,'"]'
  if. Loaded do.
   say '[SetUp "1"]'
   say '[FEN "',(fen Start),'"]'
  end.
  tokens=.0$a:
  for_i. i.#History do.
   'p santext uci capture'=.i{::History
   if. 1=1{::p do. tokens=.tokens,<(num 5{::p),'.'
   elseif. i=0 do. tokens=.tokens,<(num 5{::p),'...' end.
   tokens=.tokens,<santext
  end.
  say ' 'join tokens,<result
 end.
)
main=:3 : 0
 initial 0
 lines=.<;._2 (1!:1&3''),LF
 n=.0".0{::lines
 for_line. n{.}.lines do.
  try. command >line catcht. say Reason end.
 end.
)
main''
