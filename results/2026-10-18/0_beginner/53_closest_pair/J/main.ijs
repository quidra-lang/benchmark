main =: 3 : 0
  points =. 10 2$12 _7 _33 25 41 18 _8 _44 27 39 _46 _12 5 14 36 _29 _19 47 _2 3
  minimum =. _1
  maximum =. _1
  near =. far =. 0 1
  for_i. i.10 do.
    for_j. (i+1)+i.9-i do.
      difference =. (i{points)-j{points
      squared =. +/*:difference
      if. (minimum=_1)+.squared<minimum do.
        minimum =. squared
        near =. i,j
      end.
      if. squared>maximum do.
        maximum =. squared
        far =. i,j
      end.
    end.
  end.
  smoutput 'closest: P',(":0{near),' P',(":1{near),' ',, '4' 8!:2 %:0.0+minimum
  smoutput 'farthest: P',(":0{far),' P',(":1{far),' ',, '4' 8!:2 %:0.0+maximum
)
main ''
