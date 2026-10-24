main =: 3 : 0
  for_original. 7 98000 4096 50301 2718281 123456789 do.
    digits =. '0123456789' i. ":original
    smoutput (":original), ': digits=', (":#digits), ' sum=', (":+/digits), ' reversed=', ":10 #. |.digits
  end.
)
main ''
