cross =: 3 : 0
  'o a b' =. y
  ((0{a-o)*1{b-o)-((1{a-o)*0{b-o)
)
chain =: 3 : 0
  result =. 0 2$0
  for_point. y do.
    while. (#result)>:2 do.
      if. (cross (_2{.result),point)>0 do. break. end.
      result =. }:result
    end.
    result =. result,point
  end.
  result
)
points =: 15 2$3 2 _6 1 8 4 0 0 _3 7 4 _3 1 _5 _2 1 5 6 _6 _2 2 _2 7 _1 _3 4 2 8 _6 3
points =: /:~points
lower =: }:chain points
upper =: }:chain |.points
hull =: lower,upper
main =: 3 : 0
  smoutput 'hull: ',(":#hull),' points'
  twicearea =. 0
  for_i. i.#hull do.
    j =. (#hull)|i+1
    'x1 y1' =. i{hull
    'x2 y2' =. j{hull
    twicearea =. twicearea+(x1*y2)-x2*y1
    smoutput '(',(, '0' 8!:2 x1),', ',(, '0' 8!:2 y1),')'
  end.
  smoutput 'area: ',, '1' 8!:2 twicearea%2
)
main ''
