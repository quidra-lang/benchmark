main =: 3 : 0
  boards =. 'XXXOO.O.X';'X.O.X.O..';'XO..OXXO.';'XOXXOOOXX';'X.OXO.O.X';'XOXOXOOXX'
  lines =. 8 3$0 1 2 3 4 5 6 7 8 0 3 6 1 4 7 2 5 8 0 4 8 2 4 6
  for_i. i.6 do.
    board =. >i{boards
    result =. 'draw'
    if. '.'e.board do. result =. 'in progress' end.
    for_line. lines do.
      marks =. line{board
      if. ('.'~:{.marks)*.*./marks={.marks do.
        result =. ({.marks),' wins' break.
      end.
    end.
    smoutput 'board ',(":>:i),': ',result
  end.
)
main ''
