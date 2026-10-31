decimal =: 4 : 0
    'numerator denominator' =. x
    scale =. 10^y
    rounded =. ((2*scale*|numerator)+denominator)div 2*denominator
    sign =. ''
    if. (numerator<0)*.rounded>0 do. sign =. '-' end.
    digits =. number scale|rounded
    sign,(number rounded div scale),'.',(-y){.(y$'0'),digits
)
hull_area_text =: 3 : '(number y div 2),''.'',(2|y){''05'''
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
