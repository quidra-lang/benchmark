main =: 3 : 0
  pi =. 3.141592653589793
  for_radius. 3 7 12 25 41 do.
    area =. (pi * radius) * radius
    circumference =. (2 * pi) * radius
    smoutput 'r=', (":radius), ' area=', (, '3' 8!:2 area), ' circumference=', , '3' 8!:2 circumference
  end.
)
main ''
