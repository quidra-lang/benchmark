fixed =: 4 : 0
  scale =. 10 ^ x
  rounded =. (*y) * <. 0.5 + scale * |y
  , (":x) 8!:2 rounded % scale
)

main =: 3 : 0
  pi =. 3.141592653589793
  for_radius. 3 7 12 25 41 do.
    r =. 0.0 + radius
    area =. (pi * r) * r
    circumference =. (2.0 * pi) * r
    smoutput 'r=', (":radius), ' area=', (3 fixed area), ' circumference=', 3 fixed circumference
  end.
)
main ''
