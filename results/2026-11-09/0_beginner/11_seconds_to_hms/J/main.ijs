two =: 3 : 0
  _2 {. '0', ":y
)
main =: 3 : 0
  for_seconds. 0 59 3725 45296 86400 312047 do.
    hours =. <. seconds % 3600
    minutes =. 60 | <. seconds % 60
    remainder =. 60 | seconds
    smoutput (":seconds), ' seconds = ', (two hours), ':', (two minutes), ':', two remainder
  end.
)
main ''
