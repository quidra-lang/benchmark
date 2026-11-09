root =: 3 : 0
  vertex =. y
  while. vertex~:vertex{parent do. vertex =. vertex{parent end.
  vertex
)
main =: 3 : 0
  names =. 'ABCDEFGH'
  edges =. 13 3$0 1 7 2 0 4 1 2 9 1 3 14 3 2 6 2 4 3 4 3 5 5 3 11 4 6 16 6 5 8 7 5 12 6 7 2 7 4 10
  edges =. edges {~ /:2{"1 edges
  parent =: i.8
  accepted =. skipped =. total =. 0
  for_edge. edges do.
    'a b weight' =. edge
    first =. root a
    second =. root b
    if. first=second do. skipped =. >:skipped continue. end.
    parent =: first second}parent
    smoutput ((a<.b){names),'-',((a>.b){names),' ',":weight
    total =. total+weight
    accepted =. >:accepted
    if. accepted=7 do. break. end.
  end.
  smoutput 'total weight: ',":total
  smoutput 'skipped: ',":skipped
)
main ''
