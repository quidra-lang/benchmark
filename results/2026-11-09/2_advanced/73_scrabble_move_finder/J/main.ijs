ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'board.ijs'
load SourceDirectory,'dictionary_trie.ijs'
load SourceDirectory,'scoring.ijs'
load SourceDirectory,'move_generator.ijs'
load SourceDirectory,'game.ijs'
words =: 3 : '<;._1 '' '',y'
lines =: 3 : '<;._2 (1!:1 <''input/'',y)'
num =: 3 : '0".''_''(I.y=''-'')}y'
str =: 3 : 0
 if. 2=3!:0 y do. y return. end.
 n =. <.|y
 text =. ''
 while. n>0 do.
  text =. ((10|n){'0123456789'),text
  n =. <.n%10
 end.
 if. 0=#text do. text =. '0' end.
 if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
 s =. ''
 for_i. i.#y do. if. i do. s =. s,x end.
 s =. s,str i{::y end.
 s
)
emit =: 3 : ''' ''join y'
render =: 4 : 0
 p =. <;._1 '|',x
 t =. 0{::p
 for_i. i.#y do. t =. t,(str i{::y),(i+1){::p end.
 t
)
notation =: 3 : 0
 if. #y do. /:~y else. '-' end.
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
paragraph =: 4 : 0
 if. #x do. x,(<''),y else. y end.
)
valid_name =: 3 : '((0<#y)*.((#y)<:20))*.*./y e.''abcdefghijklmnopqrstuvwxyz0123456789_'''
valid_rack =: 3 : '(0<#y)*.((#y)<:7)*.*./y e.Tiles'
valid_number =: 4 : 0
 if. (0=#y)+.-.*./y e.'0123456789' do. 0 return. end.
 if. (1<#y)*.'0'={.y do. 0 return. end.
 v =. num y
 (v>:{.x)*.v<:{:x
)
leave_value =: 3 : 0
 value =. +/LeaveWeights{~Tiles i.y
 duplicate =. 0
 for_ch. Letters do. duplicate =. duplicate+0>._1++/y=ch end.
 v =. +/y e.'AEIOU'
 c =. +/y e.Letters-.'AEIOU'
 (value-4*duplicate)-3*0>.(|v-c)-1
)
best_leave =: 3 : 0
 candidates =. 0$a:
 keys =. 0$a:
 for_i. i.(2^#y)-1 do.
  bits =. ((#y)$2)#:i
  keep =. /:~bits#y
  if. (<keep)e.candidates do. continue. end.
  candidates =. candidates,<keep
  keys =. keys,<(-leave_value keep);(-#keep);keep
 end.
 ({./:keys){::candidates
)
strategy_order =: 4 : 0
 if. x-:'score' do. y return. end.
 keys =. 0 2$0
 for_i. i.#y do.
  m =. i{::y
  if. x-:'tiles' do. v =. #4{::m else. v =. (3{::m)+7{::m end.
  keys =. keys,(-v),i
 end.
 (/:keys){y
)
move_notation =: 3 : ' (position (0{::y),1{::y),'' '',2{::y'
tile_count_check =: 3 : 0
 'board rack' =. y
 used =. (kind_tiles board#~board~:'.'),rack
 for_i. i.27 do. if. (+/used=i{Tiles)>i{Counts do. 'too many ',i{Tiles return. end. end.
 ''
)
unseen =: 3 : 0
 'board rack' =. y
 used =. (kind_tiles board#~board~:'.'),rack
 out =. ''
 for_i. i.27 do. out =. out,((i{Counts)-+/used=i{Tiles)#i{Tiles end.
 out
)
board_check =: 3 : 0
 'rows rack' =. y
 if. 15~:#rows do. 'board rows ',str #rows return. end.
 for_i. i.15 do.
  row =. i{::rows
  if. (15~:#row)+.-.*./row e.'.',Letters,Lower do. 'bad board row ',str i+1 return. end.
 end.
 board =. ;rows
 reason =. tile_count_check board;rack
 if. #reason do. reason return. end.
 if. +./board~:'.' do.
  if. '.'=112{board do. 'center empty' return. end.
  if. -.connected board do. 'disconnected' return. end.
 end.
 for_w. board_words board do.
  'p dir word ids' =. >w
  if. -.contains word do. 'unknown word ',word,' at ',position p,dir return. end.
 end.
 ''
)
position_summary =: 3 : 0
 ws =. board_words y
 longest =. '-'
 len =. 0
 for_w. ws do. word =. 2{::>w
 if. (#word)>len do. longest =. word
 len =. #word end. end.
 counts =. i.0
 for_ch. '#*^+' do. counts =. counts,+/(y~:'.')*.Premium=ch end.
 'position tiles=| words=| longest=| blanks=| premiums=TW:|,DW:|,TL:|,DL:|'render (+/y~:'.');(#ws);longest;(+/y e.Lower);(0{counts);(1{counts);(2{counts);3{counts
)
check_move =: 3 : 0
 'board rack pos word' =. y
 parsed =. parse_position pos
 if. 0=#parsed do. 'bad position';i.0 return. end.
 'p dir' =. parsed
 if. ((#word)<2)+.((#word)>15)+.-.*./word e.Letters,Lower do. 'bad word';i.0 return. end.
 step =. dir{1 15
 ids =. p+step*i.#word
 if. (225<:{:ids)+.((dir=0)*.(<.p%15)~:<.({:ids)%15) do. 'off board';i.0 return. end.
 for_i. i.#ids do.
  q =. i{ids
  if. ('.'~:q{board)*.(q{board)~:i{word do. ('mismatch at ',square q);i.0 return. end.
 end.
 before =. p-step
 after =. step+{:ids
 if. (inside before)*.(step step_valid p) do. if. '.'~:before{board do. 'not whole word';i.0 return. end. end.
 if. (inside after)*.(step step_valid after) do. if. '.'~:after{board do. 'not whole word';i.0 return. end. end.
 new =. ids#~'.'=ids{board
 if. 0=#new do. 'no new tiles';i.0 return. end.
 placed =. word ids}board
 used =. kind_tiles new{placed
 remain =. rack
 for_ch. used do.
  i =. remain i.ch
  if. i=#remain do. ('rack lacks ',ch);i.0 return. end.
  remain =. ((i.#remain)-.i){remain
 end.
 if. *./board='.' do.
  if. -.112 e.new do. 'center not covered';i.0 return. end.
 else.
  connected =. 0
  for_q. new do. connected =. connected++/'.'~:(adjacents q){board end.
  if. connected=0 do. 'not connected';i.0 return. end.
 end.
 if. -.contains word do. ('unknown word ',word,' at ',pos);i.0 return. end.
 for_q. new do.
  cross =. run placed;q;dir{15 1
  if. 1<#cross do.
   w =. cross{placed
   if. -.contains w do. ('unknown word ',w,' at ',position ({.cross),-.dir);i.0 return. end.
  end.
 end.
 '';score_move board;rack;p;dir;word
)
topn_job =: 3 : 0
 'name count order rack board' =. y
 moves =. generate_moves board;rack
 aa =. anchors board
 unseenrack =. unseen board;rack
 'ca sa' =. cross_checks board;0
 'cd sd' =. cross_checks board;1
 kept =. best_leave rack
 an =. anagrams rack
 nm =. #moves
 across =. down =. bingo =. blanks =. 0
 scores =. 7$< '-'
 for_m. moves do.
  m =. >m
  dir =. 1{::m
  across =. across+-.dir
  down =. down+dir
  nt =. #4{::m
  bingo =. bingo+nt=7
  blanks =. blanks++./(5{::m)e.Lower
  i =. nt-1
  old =. i{::scores
  if. 2=3!:0 old do. scores =. (<3{::m)i}scores
  elseif. (3{::m)>old do. scores =. (<3{::m)i}scores end.
 end.
 out =. (<'TOPN | n=| order=| rack=|'render name;count;order;notation rack),(<'board tiles=| anchors=|'render (+/board~:'.');#aa),(<'unseen count=| tiles=|'render (#unseenrack);notation unseenrack),(<'rack vowels=| consonants=| blanks=| value=|'render (+/rack e.'AEIOU');(+/rack e.Letters-.'AEIOU');(+/rack='?');collection_points rack),<'checks across=|,|,| down=|,|,|'render (#sa);(+/0=#&>sa{ca);(+/#&>sa{ca);(#sd);(+/0=#&>sd{cd);+/#&>sd{cd
 out =. out,<'moves total=| across=| down=| bingos=| blanks=|'render nm;across;down;bingo;blanks
 text =. 'best_by_tiles'
 for_i. i.7 do. text =. text,' ',(str i+1),'=',str i{::scores end.
 out =. out,(<text),(<'exchange keep=| value=|'render (notation kept);leave_value kept)
 text =. '-'
 if. #an do. text =. ','join (10<.#an){.an end.
 out =. out,<'anagrams total=| top=|'render (#an);text
 for_w. board_words board do.
  'p dir word ids' =. >w
  if. 3>#word do. continue. end.
  u =. upper word
  front =. back =. ''
  for_ch. Letters do. if. contains ch,u do. front =. front,ch end.
  if. contains u,ch do. back =. back,ch end. end.
  if. (#front)+#back do. out =. out,<'hook | | front=| back=|'render (position p,dir);word;(notation front);notation back end.
 end.
 shown =. (count<.nm){.order strategy_order moves
 nets =. i.0
 endgame =. ((#unseenrack)>0)*.((#unseenrack)<:7)*.0<#shown
 if. endgame do.
  for_m. shown do.
   m =. >m
   replies =. generate_moves (9{::m);unseenrack
   score =. 0
   if. #replies do. score =. 3{::0{::replies end.
   nets =. nets,(3{::m)-score
  end.
  at =. nets i.>./nets
  out =. out,<'endgame opponent=| best=| net=|'render (notation unseenrack);(at+1);at{nets
 end.
 for_i. i.#shown do.
  m =. i{::shown
  text =. '| | score=| tiles=| leave=| value=|'render (i+1);(move_notation m);(3{::m);(#4{::m);(notation 6{::m);7{::m
  if. endgame do. text =. text,' net=',str i{nets end.
  out =. out,<text,' words=',8{::m
 end.
 TopTotals =: TopTotals+0 0,nm,bingo
 out
)
validate_job =: 3 : 0
 'name board records' =. y
 out =. <'VALIDATE ',name
 players =. 0$a:
 totals =. 0 4$0
 counts =. 5$0
 for_k. i.#records do.
  f =. words k{::records
  player =. 1{::f
  rack =. 2{::f
  action =. ' 'join 3}.f
  prefix =. emit 'move';(k+1);player;action
  reason =. ''
  if. -.valid_name player do. reason =. 'bad player'
  else.
   if. -.(<player)e.players do. players =. players,<player
   totals =. totals,4$0 end.
   pi =. players i.<player
   totals =. (1+(<pi,0){totals)(<pi,0)}totals
   if. -.valid_rack rack do. reason =. 'bad rack' else. reason =. tile_count_check board;rack end.
  end.
  placing =. 0
  if. 0=#reason do.
   act =. 3{::f
   if. act-:'EXCHANGE' do.
    tiles =. 4{::f
    if. -.valid_rack tiles do. reason =. 'bad exchange'
    else. for_ch. tiles do. if. (+/tiles=ch)>+/rack=ch do. reason =. 'rack lacks ',ch
    break. end. end. end.
   elseif. -.act-:'PASS' do.
    placing =. 1
    'reason move' =. check_move board;rack;act;4{::f
   end.
  end.
  if. #reason do. out =. out,<prefix,' invalid ',reason
  counts =. counts+0 1 0 0 0
  continue. end.
  moves =. generate_moves board;rack
  best =. 0
  if. #moves do. best =. 3{::0{::moves end.
  score =. 0
  if. placing do. score =. 3{::move end.
  loss =. best-score
  totals =. ((pi{totals)+0 1,score,loss)pi}totals
  total =. (<pi,2){totals
  if. placing do.
   rank =. 0
   for_i. i.#moves do.
    candidate =. i{::moves
    if. ((4{::move)-:4{::candidate)*.(5{::move)-:5{::candidate do. rank =. i+1
    break. end.
   end.
   out =. out,<prefix,(' score=| total=| tiles=| rank=|/| best=| words=|'render score;total;(#4{::move);rank;(#moves);best;8{::move)
   board =. 9{::move
  else. out =. out,<prefix,(' score=0 total=| moves=| best=|'render total;(#moves);best) end.
  counts =. counts+1 0,score,best,loss
 end.
 for_i. i.#players do.
  'a b c d' =. i{totals
  out =. out,<'player | moves=| valid=| score=| loss=|'render (i{::players);a;b;c;d
 end.
 'valid invalid score best loss' =. counts
 out =. out,<'total valid=| invalid=| score=| best=| loss=|'render valid;invalid;score;best;loss
 out =. out,(<position_summary board),board_display board
 ValidationTotals =: ValidationTotals+0 0,(#records),valid,invalid,loss
 out
)
play_game =: 3 : 0
 'kind name seed players' =. y
 RNG =: seed
 new_bag ''
 board =. 225#'.'
 np =. #players
 names =. 1{&>players
 strategies =. 2{&>players
 scores =. np$0
 stats =. (np,6)$0
 out =. <'| | seed=| players=|'render kind;name;seed;np
 for_i. i.np do.
  text =. 'player | | strategy=|'render (i+1);(i{::names);i{::strategies
  if. kind-:'GAME' do. text =. text,' threshold=',3{::i{::players end.
  out =. out,<text
 end.
 turns =. rounds =. mastertotal =. scoreless =. 0
 highlight =. i.0
 if. kind-:'DUPLICATE' do.
  rack =. draw 7
  endreason =. 'stuck'
  while. 1 do.
   moves =. generate_moves board;rack
   if. 0=#moves do. break. end.
   rounds =. rounds+1
   master =. 0{::moves
   picks =. i.0
   for_i. i.np do. chosen =. 0{::(i{::strategies)strategy_order moves
   picks =. picks,3{::chosen end.
   scores =. scores+picks
   mastertotal =. mastertotal+3{::master
   out =. out,<'round | rack=| moves=| master | score=| picks=|'render rounds;(notation rack);(#moves);(move_notation master);(3{::master);','join <"0 picks
   board =. 9{::master
   rack =. 6{::master
   rack =. rack,draw 7-#rack
   if. 0=#rack do. endreason =. 'out'
   break. end.
  end.
  text =. 'end reason=| rounds=|'render endreason;rounds
  if. endreason-:'stuck' do. text =. text,' rack=',notation rack end.
  out =. out,(<text),<'master total=',str mastertotal
  for_i. i.np do.
   percent =. 0
   if. mastertotal do. percent =. <.(100*i{scores)%mastertotal end.
   out =. out,<'final | total=| percent=|'render (i{::names);(i{scores);percent
  end.
  GameTotals =: GameTotals+0 0 0 0,rounds,0 0 0 0
 else.
  racks =. 0$a:
  for_i. i.np do. racks =. racks,<draw 7 end.
  endreason =. 'scoreless'
  wentout =. _1
  while. 1 do.
   pi =. np|turns
   turns =. turns+1
   rack =. pi{::racks
   moves =. generate_moves board;rack
   prefix =. 'turn | | rack=| moves=|'render turns;(pi{::names);(notation rack);#moves
   play =. 0
   if. #moves do.
    candidate =. 0{::(pi{::strategies)strategy_order moves
    threshold =. num 3{::pi{::players
    play =. -.((3{::candidate)<threshold)*.(#Bag)>:7
   end.
   if. play do.
    best =. 3{::0{::moves
    sc =. 3{::candidate
    nt =. #4{::candidate
    board =. 9{::candidate
    remain =. 6{::candidate
    taken =. draw 7-#remain
    rack =. remain,taken
    scores =. ((pi{scores)+sc)pi}scores
    stats =. ((pi{stats)+1,(nt=7),0 0 0,(best-sc))pi}stats
    stats =. (sc>.(<pi,4){stats)(<pi,4)}stats
    scoreless =. 0
    out =. out,<prefix,(' best=| play | score=| total=| draw=| bag=|'render best;(move_notation candidate);sc;(pi{scores);(notation taken);#Bag)
    if. 0=#highlight do. highlight =. turns;pi;candidate;sc
    elseif. sc>3{::highlight do. highlight =. turns;pi;candidate;sc end.
    if. (0=#rack)*.0=#Bag do. endreason =. 'out'
    wentout =. pi end.
   elseif. (#Bag)>:7 do.
    keep =. best_leave rack
    returned =. rack
    for_ch. keep do. at =. returned i.ch
    returned =. ((i.#returned)-.at){returned end.
    taken =. exchange returned
    rack =. keep,taken
    stats =. (1+(<pi,2){stats)(<pi,2)}stats
    scoreless =. scoreless+1
    out =. out,<prefix,(' exchange keep=| draw=| bag=|'render (notation keep);(notation taken);#Bag)
   else.
    stats =. (1+(<pi,3){stats)(<pi,3)}stats
    scoreless =. scoreless+1
    out =. out,<prefix,' pass bag=',str #Bag
   end.
   racks =. (<rack)pi}racks
   if. wentout>:0 do. break. end.
   if. scoreless=6 do. break. end.
  end.
  text =. 'end reason=',endreason
  if. wentout>:0 do. text =. text,' player=',wentout{::names end.
  out =. out,<text,' turns=',str turns
  adjust =. -collection_points&>racks
  if. wentout>:0 do. adjust =. (+/collection_points&>((i.np)-.wentout){racks)wentout}adjust end.
  final =. scores+adjust
  for_i. i.np do.
   ad =. str i{adjust
   if. (i{adjust)>0 do. ad =. '+',ad end.
   out =. out,<'final | score=| rack=| adjust=| total=|'render (i{::names);(i{scores);(notation i{::racks);ad;i{final
  end.
  order =. \:final
  for_rank. i.np do.
   i =. rank{order
   'a b c d e f' =. i{stats
   out =. out,<'standing | | total=| plays=| bingos=| exchanges=| passes=| top=| loss=|'render (rank+1);(i{::names);(i{final);a;b;c;d;e;f
  end.
  scores =. final
  GameTotals =: GameTotals+0 0 0,turns,0,(+/0{"1 stats),(+/2{"1 stats),(+/3{"1 stats),+/1{"1 stats
 end.
 out =. out,<'winner ',','join (I.scores=>./scores){names
 if. #highlight do.
  'turn pi candidate sc' =. highlight
  out =. out,<'highlight turn=| player=| play | score=|'render turn;(pi{::names);(move_notation candidate);sc
 end.
 out,(<position_summary board),board_display board
)
main =: 3 : 0
 Points =: Counts =: LeaveWeights =: i.0
 for_l. lines 'tiles.txt' do.
  text =. >l
  if. 0=#text do. continue. end.
  if. '#'={.text do. continue. end.
  'ch v c w' =. words text
  Points =: Points,num v
  Counts =: Counts,num c
  LeaveWeights =: LeaveWeights,num w
 end.
 initialize_trie ''
 candidates =. skipped =. duplicates =. 0
 for_l. lines 'dictionary.txt' do.
  w =. >l
  if. 0=#w do. continue. end.
  if. '#'={.w do. continue. end.
  candidates =. candidates+1
  if. ((#w)<2)+.((#w)>15)+.-.*./w e.Letters do. skipped =. skipped+1
  else. duplicates =. duplicates+-.trie_add w end.
 end.
 movesout =. (<'DICTIONARY lines=| words=| skipped=| duplicates=| nodes=|'render candidates;(#Dictionary);skipped;duplicates;#Trie)
 text =. 'lengths'
 for_len. /:~~.#&>Dictionary do. text =. text,' ',(str len),'=',str +/len=#&>Dictionary end.
 movesout =. movesout,<text
 validationout =. gameout =. 0$a:
 TopTotals =: 4$0
 ValidationTotals =: 6$0
 GameTotals =: 9$0
 seen =. 0$a:
 input =. lines 'jobs.txt'
 i =. 0
 while. i<#input do.
  line =. i{::input
  i =. i+1
  if. 0=#line do. continue. end.
  if. '#'={.line do. continue. end.
  header =. words line
  kind =. 0{::header
  name =. 1{::header
  body =. 0$a:
  while. i<#input do.
   line =. i{::input
   i =. i+1
   if. line-:'END' do. break. end.
   body =. body,<line
  end.
  reason =. ''
  if. -.valid_name name do. reason =. 'bad name'
  elseif. (<name)e.seen do. reason =. 'duplicate name' end.
  seen =. seen,<name
  board =. 225#'.'
  rack =. ''
  records =. 0$a:
  players =. 0$a:
  if. (<kind)e.'TOPN';'VALIDATE' do.
   if. kind-:'TOPN' do.
    counttext =. 2{::header
    order =. 3{::header
    rack =. 1{::words 0{::body
    rows =. 2}.body
    if. 0=#reason do.
     if. -. (1 99)valid_number counttext do. reason =. 'bad count'
     elseif. -.(<order)e.'score';'tiles';'equity' do. reason =. 'bad order'
     elseif. -.valid_rack rack do. reason =. 'bad rack' end.
    end.
   else.
    rows =. }.body
    k =. 0
    while. k<#rows do. if. 'MOVE'-:4{.k{::rows do. break. end.
    k =. k+1 end.
    records =. k}.rows
    rows =. k{.rows
   end.
   if. 0=#reason do. reason =. board_check rows;rack end.
   if. 0=#reason do. board =. ;rows end.
  else.
   players =. words&.>body
   seed =. 2{::header
   if. 0=#reason do.
    if. -. (1 2147483646)valid_number seed do. reason =. 'bad seed'
    elseif. ((#players)<2)+.(#players)>4 do. reason =. 'bad player count ',str #players
    else.
     pnames =. 0$a:
     for_j. i.#players do.
      player =. j{::players
      pn =. 1{::player
      st =. 2{::player
      bad =. (-.valid_name pn)+.-.(<st)e.'score';'tiles';'equity'
      if. kind-:'GAME' do. bad =. bad+.-.(0 99)valid_number 3{::player end.
      if. bad do. reason =. 'bad player ',str j+1
      break.
      elseif. (<pn)e.pnames do. reason =. 'duplicate player ',str j+1
      break. end.
      pnames =. pnames,<pn
     end.
    end.
   end.
  end.
  if. kind-:'TOPN' do.
   TopTotals =: TopTotals+1,(0<#reason),0 0
   if. #reason do. out =. (<'TOPN ',name),<'error ',reason
   else. out =. topn_job name;(num counttext);order;rack;board end.
   movesout =. movesout paragraph out
  elseif. kind-:'VALIDATE' do.
   ValidationTotals =: ValidationTotals+1,(0<#reason),0 0 0 0
   if. #reason do. out =. (<'VALIDATE ',name),<'error ',reason
   else. out =. validate_job name;board;records end.
   validationout =. validationout paragraph out
  else.
   GameTotals =: GameTotals+(kind-:'GAME'),(kind-:'DUPLICATE'),(0<#reason),0 0 0 0 0 0
   if. #reason do. out =. (<kind,' ',name),<'error ',reason
   else. out =. play_game kind;name;(num seed);players end.
   gameout =. gameout paragraph out
  end.
 end.
 'j e m b' =. TopTotals
 movesout =. movesout paragraph <'SUMMARY jobs=| errors=| moves=| bingos=|'render j;e;m;b
 'j e m v i l' =. ValidationTotals
 validationout =. validationout paragraph <'SUMMARY jobs=| errors=| moves=| valid=| invalid=| loss=|'render j;e;m;v;i;l
 'g d e t r p x q b' =. GameTotals
 gameout =. gameout paragraph <'SUMMARY games=| duplicates=| errors=| turns=| rounds=| plays=| exchanges=| passes=| bingos=|'render g;d;e;t;r;p;x;q;b
 1!:5 :: 0: <'output'
 'moves.txt'write movesout
 'validation.txt'write validationout
 'game.txt'write gameout
 i.0 0
)
main ''
