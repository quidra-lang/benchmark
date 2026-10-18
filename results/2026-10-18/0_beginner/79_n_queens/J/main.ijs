queens =: 3 : 0
  'n row positions first' =. y
  if. row=n do.
    if. (n=8)*.0=#first do. first =. positions end.
    (1;first) return.
  end.
  count =. 0
  for_column. i.n do.
    valid =. 1
    for_previous. i.row do.
      difference =. (previous{positions)-column
      if. (difference=0)+.(difference=row-previous)+.(-difference)=row-previous do.
        valid =. 0 break.
      end.
    end.
    if. valid do.
      positions =. column row}positions
      'found first' =. queens n;(row+1);positions;first
      count =. count+found
    end.
  end.
  count;first
)
main =: 3 : 0
  first =. i.0
  for_n. 4+i.5 do.
    'count first' =. queens n;0;(n$_1);first
    smoutput 'N=',(":n),': ',(":count),' solutions'
  end.
  for_column. first do. smoutput (column$'.'),'Q',(7-column)$'.' end.
)
main ''
