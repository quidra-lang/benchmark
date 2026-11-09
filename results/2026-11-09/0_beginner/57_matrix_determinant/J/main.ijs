determinant =: 3 : 0
  n =. #y
  if. n=1 do. (<0 0){y return. end.
  total =. 0
  for_j. i.n do.
    minor =. (j~:i.n) #"1 }.y
    term =. (j{0{y)*determinant minor
    if. 0=2|j do. total =. total+term
    else. total =. total-term
    end.
  end.
  total
)
main =: 3 : 0
  matrices =. (3 3$2 _3 1 5 4 _2 _1 6 3);(4 4$3 0 _2 5 1 4 7 _3 _6 2 1 8 9 _5 3 2);(5 5$4 _1 7 0 _3 2 8 _5 6 1 _9 3 2 _4 5 6 0 _7 3 _2 1 _6 4 9 8)
  for_box. matrices do.
    matrix =. >box
    n =. #matrix
    smoutput 'det(',(":n),'x',(":n),') = ',(, '0' 8!:2 determinant matrix)
  end.
)
main ''
