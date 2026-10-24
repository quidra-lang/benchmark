main =: 3 : 0
  for_celsius. _40 _15 _3 0 22 37 100 do.
    fahrenheit =. ((celsius * 9) % 5) + 32
    smoutput (, '0' 8!:2 celsius), ' C = ', (, '1' 8!:2 fahrenheit), ' F'
  end.
)
main ''
