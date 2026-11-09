split =: 4 : 0
  <;._1 x,y
)

before =: 4 : 0
  ((x{priorities)<y{priorities)+.((x{priorities)=y{priorities)*.x<y
)
push =: 3 : 0
  heap =: heap,y
  index =. <:#heap
  while. index>0 do.
    parent =. <.(index-1)%2
    if. -. (index{heap) before parent{heap do. break. end.
    pair =. index,parent
    heap =: (|.pair{heap) pair}heap
    index =. parent
  end.
  i.0 0
)
pop =: 3 : 0
  result =. {.heap
  last =. {:heap
  heap =: }:heap
  if. 0=#heap do. result return. end.
  heap =: last (0)}heap
  index =. 0
  while. ((2*index)+1)<#heap do.
    child =. 1+2*index
    if. (child+1)<#heap do.
      if. ((child+1){heap) before child{heap do. child =. >:child end.
    end.
    if. -. (child{heap) before index{heap do. break. end.
    pair =. index,child
    heap =: (|.pair{heap) pair}heap
    index =. child
  end.
  result
)
main =: 3 : 0
  operations =. 'add email 3';'add backup 5';'add deploy 1';'run';'add report 3';'add test 2';'add lint 3';'run';'run';'add cleanup 5';'add review 2';'run';'add build 1';'add docs 4';'run';'run'
  names =. 0$<''
  priorities =: i.0
  heap =: i.0
  for_box. operations do.
    fields =. ' ' split >box
    if. 'add'-:>{.fields do.
      id =. #names
      names =. names,1{fields
      priorities =: priorities,0".>2{fields
      push id
    else.
      id =. pop''
      smoutput 'run: ',(>id{names),' (priority ',(":id{priorities),')'
    end.
  end.
  remaining =. 0$<''
  while. #heap do. remaining =. remaining,(pop''){names end.
  smoutput 'remaining: ',}. ; (<' ') ,&.> remaining
)
main ''
