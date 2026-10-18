main =: 3 : 0
  black =. 11 11$0
  row =. column =. 5
  direction =. 0
  steps =. 4 2$_1 0 0 1 1 0 0 _1
  for_step. i.300 do.
    cell =. <row,column
    if. cell{black do. direction =. 4|direction+3
    else. direction =. 4|direction+1
    end.
    black =. (-.cell{black) cell}black
    'dr dc' =. direction{steps
    row =. 11|row+dr
    column =. 11|column+dc
  end.
  board =. black{'.#'
  board =. 'A' (<row,column)}board
  smoutput board
  smoutput 'black: ',":+/,black
)
main ''
