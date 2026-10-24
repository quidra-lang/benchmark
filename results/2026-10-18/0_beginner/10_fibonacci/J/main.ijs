main =: 3 : 0
  a =. 1
  b =. 1
  terms =. i.0
  for_n. i.30 do.
    terms =. terms,a
    next =. a+b
    a =. b
    b =. next
  end.
  smoutput ":terms
  smoutput 'sum: ', ":+/terms
)
main ''
