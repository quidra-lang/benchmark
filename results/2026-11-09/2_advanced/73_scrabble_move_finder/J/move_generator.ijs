anchors =: 3 : 0
 if. *./y='.' do. ,112 return. end.
 ids =. i.0
 for_p. I.y='.' do. if. +./'.'~:(adjacents p){y do. ids =. ids,p end. end.
 ids
)
cross_checks =: 3 : 0
 'board dir' =. y
 sets =. 225$<Letters
 squares =. i.0
 step =. dir{15 1
 for_p. I.board='.' do.
  test =. 'A'p}board
  ids =. run test;p;step
  if. 1<#ids do.
   squares =. squares,p
   valid =. ''
   for_ch. Letters do. if. contains ids{ch p}board do. valid =. valid,ch end. end.
   sets =. (<valid)p}sets
  end.
 end.
 sets;squares
)
generate_moves =: 3 : 0
 'board rack' =. y
 aa =. anchors board
 moves =. 0$a:
 keys =. 0$a:
 for_dir. i.2 do.
  step =. dir{1 15
  'checks squares' =. cross_checks board;dir
  for_start. i.225 do.
   before =. start-step
   if. (inside before)*.(step step_valid start) do. if. '.'~:before{board do. continue. end. end.
   stack =. <start;0;rack;'';(i.0);''
   while. #stack do.
    'p node remain word ids chars' =. >{:stack
    stack =. }:stack
    boundary =. -.inside p
    if. -.boundary do. boundary =. (p~:start)*.-.step step_valid p end.
    empty =. boundary
    if. -.boundary do. empty =. '.'=p{board end.
    if. (node{Terminal)*.(#ids)>0 do.
     if. empty*.(+./ids e.aa) do.
      discard =. 0
      if. dir*.1=#ids do.
       after =. chars ids}board
       discard =. 1<#run after;({.ids);1
      end.
      if. -.discard do.
       m =. score_move board;rack;start;dir;word
       moves =. moves,<m
       keys =. keys,<(-3{::m);(<.start%15);(15|start);dir;word
      end.
     end.
    end.
    if. boundary do. continue. end.
    if. (#word)>:15 do. continue. end.
    if. '.'~:p{board do.
     ch =. p{board
     next =. (<node,Letters i.upper ,ch){Trie
     if. next>:0 do. stack =. stack,< (p+step);next;remain;(word,ch);ids;chars end.
    else.
     for_ch. Letters do.
      next =. (<node,Letters i.ch){Trie
      if. (next<0)+.-.ch e.p{::checks do. continue. end.
      at =. remain i.ch
      if. at<#remain do. rest =. ((i.#remain)-.at){remain
      stack =. stack,< (p+step);next;rest;(word,ch);(ids,p);chars,ch end.
      at =. remain i.'?'
      if. at<#remain do. rest =. ((i.#remain)-.at){remain
      low =. (Letters i.ch){Lower
      stack =. stack,< (p+step);next;rest;(word,low);(ids,p);chars,low end.
     end.
    end.
   end.
  end.
 end.
 (/:keys){moves
)
