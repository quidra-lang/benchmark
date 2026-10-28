dot =: +/ . *
cross =: 4 : 0
    (((1{x)*2{y)-(2{x)*1{y),(((2{x)*0{y)-(0{x)*2{y),((0{x)*1{y)-(1{x)*0{y
)
normal =: 4 : 0
    'a b c' =. (3{.x)-1
    ((b{y)-a{y)cross(c{y)-a{y
)
determinant =: 4 : 0
    'a b c' =. (3{.x)-1
    (a{y)dot(b{y)cross c{y
)
area =: 3 : 0
    'ids faces points' =. y
    total =. 0.0
    for_id. ids do.
        direction =. ((id-1){faces)normal points
        total =. total+%:0.0+direction dot direction
    end.
    total%2.0
)
length2 =: 4 : 0
    'a b' =. x-1
    delta =. (a{y)-b{y
    delta dot delta
)
triangle_angle =: 4 : 0
    'a b c' =. ((3{.x)-1){y
    products =. ((b-a)dot c-a),((c-b)dot a-b),(a-c)dot b-c
    smallest =. <./products
    if. smallest<0 do.
        'obtuse'
    elseif. smallest=0 do.
        'right'
    else.
        'acute'
    end.
)
volume6 =: 3 : 0
    'ids faces points' =. y
    total =. 0x
    for_id. ids do.
        total =. total+((id-1){faces)determinant points
    end.
    total
)
fraction =: 4 : 0
    numerator =. x
    denominator =. y
    if. denominator<0 do.
        numerator =. -numerator
        denominator =. -denominator
    end.
    divisor =. (|numerator)+.denominator
    numerator =. <.numerator%divisor
    denominator =. <.denominator%divisor
    if. denominator=1 do.
        text numerator
    else.
        (text numerator),'/',text denominator
    end.
)
real_text =: 3 : 0
    value =. 0j3":y
    value =. value#~value~:' '
    if. value-:'_0.000' do.
        '0.000'
    else.
        value
    end.
)
centroid =: 3 : 0
    'ids faces points signed_volume' =. y
    result =. 0$a:
    for_axis. i.3 do.
        total =. 0x
        for_id. ids do.
            face =. (id-1){faces
            coordinates =. axis{"1 ((3{.face)-1){points
            total =. total+((face determinant points)*+/coordinates)
        end.
        result =. result,<total fraction 4*signed_volume
    end.
    result
)
bbox =: 4 : 0
    selected =. (x-1){y
    (<./selected),>./selected
)
winding =: 3 : 0
    'ids faces points sample' =. y
    total =. 0.0
    for_id. ids do.
        face =. (id-1){faces
        a =. ((0{face)-1){points
        b =. ((1{face)-1){points
        c =. ((2{face)-1){points
        a =. a-sample
        b =. b-sample
        c =. c-sample
        la =. %:0.0+a dot a
        lb =. %:0.0+b dot b
        lc =. %:0.0+c dot c
        numerator =. 0.0+a dot b cross c
        denominator =. ((((la*lb)*lc)+((a dot b)*lc))+((b dot c)*la))+((c dot a)*lb)
        total =. total+2*12 o.denominator j.numerator
    end.
    <.(total%(4*3.141592653589793))+0.5
)
