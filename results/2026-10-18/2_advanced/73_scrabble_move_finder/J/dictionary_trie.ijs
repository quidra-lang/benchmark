initialize_trie =: 3 : 0
 Trie =: 1 26$_1
 Terminal =: ,0
 Dictionary =: 0$a:
 i.0 0
)
trie_add =: 3 : 0
 node =. 0
 for_ch. y do.
  k =. Letters i.ch
  next =. (<node,k){Trie
  if. next<0 do.
   next =. #Trie
   Trie =: Trie,26$_1
   Terminal =: Terminal,0
   Trie =: next(<node,k)}Trie
  end.
  node =. next
 end.
 if. node{Terminal do. 0 return. end.
 Terminal =: 1 node}Terminal
 Dictionary =: Dictionary,<y
 1
)
contains =: 3 : 0
 node =. 0
 for_ch. upper y do.
  k =. Letters i.ch
  if. k=26 do. 0 return. end.
  node =. (<node,k){Trie
  if. node<0 do. 0 return. end.
 end.
 node{Terminal
)
can_supply =: 4 : 0
 rack =. x
 for_ch. y do.
  i =. rack i.ch
  if. i=#rack do. i =. rack i.'?' end.
  if. i=#rack do. 0 return. end.
  rack =. ((i.#rack)-.i){rack
 end.
 1
)
anagrams =: 3 : 0
 out =. 0$a:
 keys =. 0$a:
 for_word. /:~Dictionary do.
  w =. >word
  if. y can_supply w do. out =. out,<w
  keys =. keys,<(-#w);w end.
 end.
 (/:keys){out
)
