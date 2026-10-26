reduced_fraction =: 3 : 0
    'numerator denominator' =. y
    if. denominator<0 do. numerator =. -numerator
        denominator =. -denominator end.
    a =. |numerator
    b =. denominator
    while. b do. remainder =. b|a
        a =. b
        b =. remainder end.
    (numerator div a),denominator div a
)
frac_add =: 4 : 0
    'a b' =. x
    'c d' =. y
    reduced_fraction ((a*d)+c*b),b*d
)
frac_times =: 4 : 'reduced_fraction (x*0{y),1{y'
frac_divide =: 4 : 'reduced_fraction (0{x),y*1{x'
frac_real =: 3 : '(0{y)%1{y'
frac_compare =: 4 : '*((0{x)*1{y)-(0{y)*1{x'
fraction_text =: 3 : 0
    'numerator denominator' =. reduced_fraction y
    (number numerator),'/',number denominator
)
decimal_value =: 4 : 0
    magnitude =. <.0.5+(|y)*10^x
    (*y)*magnitude
)
scaled_text =: 4 : 0
    sign =. ''
    if. y<0 do. sign =. '-'
        y =. -y end.
    scale =. 10^x
    tail =. number scale|y
    sign,(number y div scale),'.',((x-#tail)$'0'),tail
)
fixed =: 3 : 0
    4 fixed y
:
    x scaled_text x decimal_value y
)
fixed_fraction =: 3 : 0
    'numerator denominator' =. y
    magnitude =. |numerator
    whole =. magnitude div denominator
    remainder =. denominator|magnitude
    digits =. 0$0
    for_index. i.4 do.
        remainder =. 10*remainder
        digits =. digits,remainder div denominator
        remainder =. denominator|remainder
    end.
    if. remainder>:denominator-remainder do.
        carry =. 1
        for_index. |.i.4 do.
            if. (index{digits)=9 do. digits =. 0 index}digits
            else. digits =. (1+index{digits)index}digits
                carry =. 0
                break.
            end.
        end.
        whole =. whole+carry
    end.
    sign =. ''
    if. (numerator<0)*.((whole~:0)+.+./digits~:0)do. sign =. '-' end.
    sign,(number whole),'.',digits{Digits
)
fraction_real_text =: 3 : '(fraction_text y),'' '',fixed_fraction y'
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
    i.0
)
