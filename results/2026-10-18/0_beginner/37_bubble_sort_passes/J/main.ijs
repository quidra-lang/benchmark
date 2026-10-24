main =: 3 : 0
  values =. 27 64 13 88 41 5 72 36
  swaps =. 0
  for_pass. >:i.7 do.
    changed =. 0
    for_j. i.8-pass do.
      if. (j{values) > (j+1){values do.
        indices =. j,j+1
        values =. (|.indices{values) indices}values
        swaps =. >:swaps
        changed =. 1
      end.
    end.
    smoutput 'pass ',(":pass),': ',":values
    if. -.changed do. break. end.
  end.
  smoutput 'swaps: ',":swaps
)
main ''
