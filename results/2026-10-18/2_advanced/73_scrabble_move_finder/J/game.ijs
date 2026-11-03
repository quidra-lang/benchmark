random =: 3 : 0
 RNG =: 2147483647|48271x*RNG
 RNG
)
shuffle =: 3 : 0
 bag =. y
 for_i. |.1+i.(#bag)-1 do.
  j =. (i+1)|random ''
  a =. i{bag
  b =. j{bag
  bag =. b i}bag
  bag =. a j}bag
 end.
 bag
)
new_bag =: 3 : 0
 Bag =: shuffle Counts#Tiles
 i.0 0
)
draw =: 3 : 0
 n =. y<.#Bag
 taken =. |.(-n){.Bag
 if. n=0 do. taken =. '' else. Bag =: (-n)}.Bag end.
 taken
)
exchange =: 3 : 0
 tiles =. /:~y
 taken =. draw #tiles
 Bag =: shuffle Bag,tiles
 taken
)
collection_points =: 3 : '+/Points{~Tiles i.y'
