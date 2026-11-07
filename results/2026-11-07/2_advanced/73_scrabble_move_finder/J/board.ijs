Letters =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Tiles =: Letters,'?'
Premium =: ,>('#..+...#...+..#';'.*...^...^...*.';'..*...+.+...*..';'+..*...+...*..+';'....*.....*....';'.^...^...^...^.';'..+...+.+...+..';'#..+...*...+..#';'..+...+.+...+..';'.^...^...^...^.';'....*.....*....';'+..*...+...*..+';'..*...+.+...*..';'.*...^...^...*.';'#..+...#...+..#')
upper =: 3 : 0
 a =. a.i.y
 a =. a-32*(a>:97)*.a<:122
 a.{~a
)
kind_tiles =: 3 : 0
 out =. y
 out =. '?'(I.out e.Lower)}out
 out
)
inside =: 3 : '(y>:0)*.y<225'
step_valid =: 4 : 0
 if. -.inside y do. 0 return. end.
 if. x=1 do. (15|y)>0 else. 1 end.
)
position =: 3 : 0
 'p dir' =. y
 r =. 1+<.p%15
 c =. (15|p){'ABCDEFGHIJKLMNO'
 if. dir do. c,str r else. (str r),c end.
)
square =: 3 : '((15|y){''ABCDEFGHIJKLMNO''),str 1+<.y%15'
parse_position =: 3 : 0
 if. (#y)<2 do. i.0 return. end.
 dir =. ({.y)e.'ABCDEFGHIJKLMNO'
 if. dir do. c =. {.y
 rs =. }.y else. c =. {:y
 rs =. }:y end.
 if. -.c e.'ABCDEFGHIJKLMNO' do. i.0 return. end.
 if. -. (1 15)valid_number rs do. i.0 return. end.
 ((15*((num rs)-1))+('ABCDEFGHIJKLMNO'i.c)),dir
)
run =: 3 : 0
 'board p step' =. y
 start =. p
 while. 1 do.
  q =. start-step
  if. -.step step_valid start do. break. end.
  if. -.inside q do. break. end.
  if. '.'=q{board do. break. end.
  start =. q
 end.
 ids =. i.0
 q =. start
 while. inside q do.
  if. '.'=q{board do. break. end.
  ids =. ids,q
  qq =. q+step
  if. -.step step_valid qq do. break. end.
  q =. qq
 end.
 ids
)
board_words =: 3 : 0
 out =. 0$a:
 for_dir. i.2 do.
  step =. dir{1 15
  for_axis. i.15 do.
   for_coord. i.15 do.
    if. dir do. p =. axis+15*coord else. p =. coord+15*axis end.
    if. '.'=p{y do. continue. end.
    before =. p-step
    if. (inside before)*.(step step_valid p) do. if. '.'~:before{y do. continue. end. end.
    ids =. run y;p;step
    if. 1<#ids do. out =. out,<p;dir;(ids{y);ids end.
   end.
  end.
 end.
 out
)
adjacents =: 3 : 0
 ns =. i.0
 r =. <.y%15
 c =. 15|y
 if. r>0 do. ns =. ns,y-15 end.
 if. r<14 do. ns =. ns,y+15 end.
 if. c>0 do. ns =. ns,y-1 end.
 if. c<14 do. ns =. ns,y+1 end.
 ns
)
connected =: 3 : 0
 ids =. I.y~:'.'
 if. 0=#ids do. 1 return. end.
 seen =. ,{.ids
 i =. 0
 while. i<#seen do.
  ns =. adjacents i{seen
  seen =. ~.seen,ns#~'.'~:ns{y
  i =. i+1
 end.
 (#seen)=#ids
)
board_display =: 3 : 0
 out =. <'   A B C D E F G H I J K L M N O'
 show =. y
 ids =. I.show='.'
 show =. (ids{Premium)ids}show
 for_r. i.15 do. out =. out,<(_2{.' ',str r+1),' ',' 'join <"0 (r*15+i.15){show end.
 out
)
