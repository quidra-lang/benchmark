Trail=:0$a:
bind=:4 :0
 binding__x=:y
 Trail=:Trail,x
 1
)
undo=:3 :0
  while. y<#Trail  do.
  t=.{:Trail
  binding__t=:a:
  Trail=:}:Trail
  end.
 0
)
unify=:4 :0
 pending=.,<x;y
  while. #pending  do.
  'a b'=.>{.pending
  pending=.}.pending
  a=.deref a
  b=.deref b
   if. a-:b  do.  continue.  end.
   if. kind__a=0  do. a bind b
   continue.  end.
   if. kind__b=0  do. b bind a
   continue.  end.
   if. kind__a~:kind__b  do. 0  return.  end.
   if. -.value__a-:value__b  do. 0  return.  end.
   if. kind__a=3  do.
    if. (#args__a)~:#args__b  do. 0  return.  end.
   pairs=.0$a:
    for_i. i.#args__a  do. pairs=.pairs,<((i{args__a);i{args__b) end.
   pending=.pairs,pending
   end.
  end.
 1
)
identical=:4 :0
 pending=.,<x;y
  while. #pending  do.
  'a b'=.>{.pending
  pending=.}.pending
  a=.deref a
  b=.deref b
   if. a-:b  do.  continue.  end.
   if. (kind__a=0)+.kind__b=0  do. 0  return.  end.
   if. (kind__a~:kind__b)+.-.value__a-:value__b  do. 0  return.  end.
   if. (#args__a)~:#args__b  do. 0  return.  end.
   for_i. i.#args__a  do. pending=.pending,<((i{args__a);i{args__b) end.
  end.
 1
)
