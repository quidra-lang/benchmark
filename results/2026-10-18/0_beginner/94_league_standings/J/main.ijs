split =: 4 : 0
  <;._1 x,y
)

main =: 3 : 0
  names =. /:~;:'Lions Tigers Eagles Sharks Wolves Bears'
  matches =. 'Lions 0-3 Bears';'Tigers 2-2 Wolves';'Eagles 4-0 Sharks';'Bears 0-1 Sharks';'Wolves 2-1 Eagles';'Lions 0-1 Tigers';'Tigers 3-3 Bears';'Eagles 2-2 Lions';'Sharks 2-2 Wolves';'Bears 3-1 Wolves';'Lions 2-0 Sharks';'Tigers 2-1 Eagles';'Eagles 1-0 Bears';'Sharks 2-0 Tigers';'Wolves 2-1 Lions'
  played =. wins =. draws =. losses =. goalsfor =. goalsagainst =. points =. 6$0
  for_box. matches do.
    fields =. ' ' split >box
    home =. names i.0{fields
    away =. names i.2{fields
    score =. '-' split >1{fields
    first =. 0".>0{score
    second =. 0".>1{score
    played =. (>:home{played) home}played
    played =. (>:away{played) away}played
    goalsfor =. ((home{goalsfor)+first) home}goalsfor
    goalsagainst =. ((home{goalsagainst)+second) home}goalsagainst
    goalsfor =. ((away{goalsfor)+second) away}goalsfor
    goalsagainst =. ((away{goalsagainst)+first) away}goalsagainst
    if. first=second do.
      draws =. (>:home{draws) home}draws
      draws =. (>:away{draws) away}draws
      points =. (>:home{points) home}points
      points =. (>:away{points) away}points
    else.
      winner =. home
      loser =. away
      if. second>first do. winner =. away [ loser =. home end.
      wins =. (>:winner{wins) winner}wins
      losses =. (>:loser{losses) loser}losses
      points =. (3+winner{points) winner}points
    end.
  end.
  difference =. goalsfor-goalsagainst
  order =. \:points,.difference,.goalsfor
  for_position. i.6 do.
    i =. position{order
    gd =. , '0' 8!:2 i{difference
    if. (i{difference)>0 do. gd =. '+',gd end.
    smoutput (":>:position),'. ',(>i{names),' P=',(":i{played),' W=',(":i{wins),' D=',(":i{draws),' L=',(":i{losses),' GF=',(":i{goalsfor),' GA=',(":i{goalsagainst),' GD=',gd,' Pts=',":i{points
  end.
)
main ''
