main =: 3 : 0
  values =. 52 17 38 9 61 38 24 45
  total =. 0
  for_i. >:i.7 do.
    value =. i{values
    j =. i-1
    shifts =. 0
    while. j>:0 do.
      if. (j{values)<:value do. break. end.
      values =. (j{values) (j+1)}values
      j =. j-1
      shifts =. >:shifts
    end.
    values =. value (j+1)}values
    total =. total+shifts
    smoutput 'i=',(":i),' shifts=',(":shifts),': ',":values
  end.
  smoutput 'total shifts: ',":total
)
main ''
