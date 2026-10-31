topology =: 3 : 0
  'names edges showcycle' =. y
  names =. /:~names
  n =. #names
  indegree =. n$0
  for_edge. edges do.
    target =. names i.1{>edge
    indegree =. (>:target{indegree) target}indegree
  end.
  taken =. n$0
  result =. 0$<''
  while. 1 do.
    available =. I.(-.taken)*.indegree=0
    if. 0=#available do. break. end.
    selected =. {.available
    taken =. 1 selected}taken
    result =. result,selected{names
    for_edge. edges do.
      'source target' =. >edge
      if. source-:>selected{names do.
        index =. names i.<target
        indegree =. (<:index{indegree) index}indegree
      end.
    end.
  end.
  joined =. 4}. ; (<' -> ') ,&.> result
  smoutput 'order: ',joined
  if. showcycle do. smoutput 'cycle: ',}. ; (<' ') ,&.> (-.taken)#names end.
)
names =: ;:'physics algebra graphics programming statistics calculus databases algorithms'
edges =: (<;:'calculus physics'),(<;:'algebra calculus'),(<;:'programming algorithms'),(<;:'algebra statistics'),(<;:'algorithms databases'),(<;:'statistics databases'),(<;:'calculus graphics'),(<;:'algorithms graphics'),<;:'physics graphics'
topology names;edges;0
names =: ;:'music ecology art geology biology chemistry'
edges =: (<;:'music art'),(<;:'art ecology'),(<;:'biology chemistry'),(<;:'chemistry ecology'),(<;:'ecology geology'),<;:'geology chemistry'
topology names;edges;1
