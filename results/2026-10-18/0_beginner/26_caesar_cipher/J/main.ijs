caesar =: 4 : 0
  alphabet =. 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'
  result =. ''
  for_char. y do.
    index =. alphabet i. char
    if. index<52 do.
      base =. 26*index>:26
      shifted =. base + 26 | (index-base)+x
      result =. result,shifted{alphabet
    else.
      result =. result,char
    end.
  end.
  result
)
message =: 'Zoe, meet Max by the Old Bridge at six!'
encrypted =: 3 caesar message
smoutput encrypted
smoutput _3 caesar encrypted
