main =: 3 : 0
  for_n. 0 7 999 1000 _456789 3141592 9876543210 do.
    negative =. n<0
    magnitude =. , 'c0' 8!:2 |n
    smoutput (negative#'-'),magnitude
  end.
)
main ''
