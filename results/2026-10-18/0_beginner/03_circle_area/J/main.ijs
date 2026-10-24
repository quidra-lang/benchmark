main =: 3 : 0
  pi =. 3.141592653589793
  for_radius. 3 7 12 25 41 do.
    r =. 0.0 + radius
    area =. (pi * r) * r
    circumference =. (2.0 * pi) * r
    smoutput 'r=', (":radius), ' area=', (, '3' 8!:2 area), ' circumference=', , '3' 8!:2 circumference
  end.
)
main ''
