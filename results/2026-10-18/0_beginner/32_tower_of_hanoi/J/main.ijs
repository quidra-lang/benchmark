hanoi =: 3 : 0
  'n source target auxiliary' =. y
  if. n=0 do. 0 return. end.
  first =. hanoi (n-1);source;auxiliary;target
  smoutput 'move disk ', (":n), ' from ',source,' to ',target
  last =. hanoi (n-1);auxiliary;target;source
  first+1+last
)
moves =: hanoi 4;'A';'C';'B'
smoutput 'total moves: ', ":moves
