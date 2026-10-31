intdiv =: 4 : '<.(x: x)%x: y'
orient =: 3 : 0
    'p q r' =. x: y
    ((0{q-p)*1{r-p)-(1{q-p)*0{r-p
)
d2 =: 4 : 0
    difference =. (x:x)-x:y
    +/difference*difference
)
dot =: 3 : 0
    'o p q' =. x:y
    +/(p-o)*q-o
)
incircle =: 3 : 0
    'a b c d' =. x:y
    'ax ay' =. a-d
    'bx by' =. b-d
    'cx cy' =. c-d
    aa =. (ax*ax)+ay*ay
    bb =. (bx*bx)+by*by
    cc =. (cx*cx)+cy*cy
    ((ax*((by*cc)-bb*cy))-(ay*((bx*cc)-bb*cx)))+aa*((bx*cy)-by*cx)
)
circumcenter =: 3 : 0
    'a b c' =. x:y
    'bx by' =. b-a
    'cx cy' =. c-a
    bb =. (bx*bx)+by*by
    cc =. (cx*cx)+cy*cy
    denominator =. 2*((bx*cy)-by*cx)
    first =. (((0{a)*denominator)+cy*bb)-by*cc
    second =. (((1{a)*denominator)+bx*cc)-cx*bb
    first,second,denominator
)
fraction =: 4 : 0
    common =. (|x)+.y
    numerator =. <.(x:x)%common
    denominator =. <.(x:y)%common
    text =. ":numerator
    text =. '-'(I.text='_')}text
    if. denominator=1 do.
        text
    else.
        text,'/',":denominator
    end.
)
reduce_direction =: 3 : 0
    common =. (|0{y)+.|1{y
    <.(x:y)%common
)
