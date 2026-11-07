str =: 3 : 0
 if. 2=3!:0 y do. y return. end.
 n =. <.|y
 text =. ''
 while. n>0 do.
  text =. ((10|n){'0123456789'),text
  n =. <.n%10
 end.
 if. 0=#text do. text =. '0' end.
 if. y<0 do. '-',text else. text end.
)
join =: 4 : 0
 t =. ''
 for_i. i.#y do. if. i do. t =. t,x end.
 t =. t,str i{::y end.
 t
)
emit =: 3 : ''' ''join y'
fmt =: 4 : 0
 n =. <.0.5+(10^x)*|y
 t =. (str <.n%10^x),'.',(-x){.(x#'0'),str (10^x)|n
 if. (y<0)*.n>0 do. '-',t else. t end.
)
symbol =: 3 : 0
 s =. N#'.'
 '*'(members y)}s
)
mask_order =: 3 : '( /:symbol&.>y){y'
children_order =: 4 : 0
 'adj lengths leaves negatives' =. x
 'node parent masks' =. y
 children =. (I.node{adj)-.parent
 keys =. 0$a:
 for_c. children do.
  names =. (members c{masks){Names
  keys =. keys,<0{::/:~names
 end.
 (/:keys){children
)
newick_node =: 3 : 0
 node =. y
 'adj lengths leaves negatives' =. PrintTree
 if. node e.leaves do. text =. node{::Names
 else.
  children =. PrintTree children_order node;(node{PrintParents);PrintMasks
  childtexts =. 0$a:
  for_c. children do. childtexts =. childtexts,<newick_node c end.
  text =. '(',(','join childtexts),')'
  if. (PrintMode=2)*.node~:PrintRoot do. text =. text,str (node{PrintMasks){Supports end.
 end.
 if. (PrintMode=1)*.node~:PrintRoot do. text =. text,':',5 fmt (<node,node{PrintParents){lengths end.
 text
)
newick =: 3 : 0
 'PrintTree PrintMode' =: y
 'PrintRoot PrintParents order PrintMasks' =: rooting PrintTree
 (newick_node PrintRoot),';'
)
cladogram_node =: 3 : 0
 'node prefix last' =. y
 'adj lengths leaves negatives' =. PrintTree
 connector =. last{::'|-- ';'`-- '
 if. node e.leaves do. label =. node{::Names else. label =. '[',(str (node{PrintMasks){Supports),']' end.
 out =. <prefix,connector,label
 extension =. last{::'|   ';'    '
 children =. PrintTree children_order node;(node{PrintParents);PrintMasks
 for_i. i.#children do. out =. out,cladogram_node (i{children);(prefix,extension);i=(#children)-1 end.
 out
)
cladogram =: 3 : 0
 'name PrintTree' =: y
 'PrintRoot PrintParents order PrintMasks' =: rooting PrintTree
 out =. (<emit 'TREE';name),<'*'
 children =. PrintTree children_order PrintRoot;PrintRoot;PrintMasks
 for_i. i.#children do. out =. out,cladogram_node (i{children);'';i=(#children)-1 end.
 out
)
write =: 4 : 0
 (;(,&LF)&.>y)1!:2 <'output/',x
 i.0 0
)
