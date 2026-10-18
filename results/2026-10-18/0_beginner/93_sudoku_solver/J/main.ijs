solve =: 3 : 0
  position =. board i.0
  if. position=#board do. 1 return. end.
  row =. <.position%9
  column =. 9|position
  for_digit. >:i.9 do.
    valid =. 1
    for_i. i.9 do.
      if. (digit=((row*9)+i){board)+.digit=(column+9*i){board do. valid =. 0 end.
    end.
    blockrow =. 3*<.row%3
    blockcolumn =. 3*<.column%3
    for_dr. i.3 do.
      for_dc. i.3 do.
        index =. (9*(blockrow+dr))+blockcolumn+dc
        if. digit=index{board do. valid =. 0 end.
      end.
    end.
    if. valid do.
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
