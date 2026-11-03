tile_points =: 3 : 0
 if. y e.Lower do. 0 else. (Tiles i.y){Points end.
)
word_score =: 3 : 0
 'board ids new' =. y
 total =. 0
 mult =. 1
 for_p. ids do.
  v =. tile_points p{board
  if. p e.new do.
   premium =. p{Premium
   if. premium='+' do. v =. 2*v elseif. premium='^' do. v =. 3*v
   elseif. premium='*' do. mult =. 2*mult elseif. premium='#' do. mult =. 3*mult end.
  end.
  total =. total+v
 end.
 total*mult
)
score_move =: 3 : 0
 'board rack p dir word' =. y
 step =. dir{1 15
 ids =. p+step*i.#word
 new =. ids#~'.'=ids{board
 after =. word ids}board
 main =. word_score after;ids;new
 total =. main
 wordlist =. <word,':',str main
 for_q. new do.
  cross =. run after;q;dir{15 1
  if. 1<#cross do.
   sc =. word_score after;cross;new
   total =. total+sc
   wordlist =. wordlist,< (cross{after),':',str sc
  end.
 end.
 used =. kind_tiles new{after
 leave =. rack
 for_ch. used do. i =. leave i.ch
 leave =. ((i.#leave)-.i){leave end.
 if. 7=#new do. total =. total+50 end.
 p;dir;word;total;new;(new{after);(/:~leave);(leave_value leave);(','join wordlist);after
)
