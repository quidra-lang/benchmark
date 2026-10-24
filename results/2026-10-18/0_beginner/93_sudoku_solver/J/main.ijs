solve =: 3 : 0
  position =. board i.0
  if. position=#board do. 1 return. end.
  row =. <.position%9
  column =. 9|position
  row_indices =. (9*row)+i.9
  column_indices =. column+9*i.9
  blockrow =. 3*<.row%3
  blockcolumn =. 3*<.column%3
  block_indices =. , (9*(blockrow+i.3)) +/ blockcolumn+i.3
  occupied =. (row_indices,column_indices,block_indices){board
  for_digit. >:i.9 do.
    if. -.digit e.occupied do.
      board =: digit position}board
      placements =: >:placements
      if. solve'' do. 1 return. end.
      board =: 0 position}board
    end.
  end.
  0
)
main =: 3 : 0
  rows =. '800025000';'070080005';'260400070';'000001900';'010000040';'600200000';'900010000';'700000004';'020000036'
  board =: '0123456789'i.;rows
  placements =: 0
  solved =. solve''
  for_r. i.9 do. smoutput ":9{.(9*r)}.board end.
  smoutput 'placements: ',":placements
)
main ''
