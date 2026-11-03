hexadecimal =: 4 : 0
    text =. ''
    remaining =. y
    while. (remaining>0)+.x>#text do.
        text =. ((16|remaining){'0123456789ABCDEF'),text
        remaining =. remaining intdiv 16
    end.
    text
)
hex2 =: 2&hexadecimal
hex1 =: 1&hexadecimal
hex_lines =: 3 : 0
    lines =. 0$a:
    for_start. 32*i.>.(#y)%32 do.
        text =. ''
        for_value. (start+i.(32<.(#y)-start)){y do.
            text =. text,hex2 value
        end.
        lines =. lines,<text
    end.
    lines
)
adler =: 3 : 0
    a =. 1x
    b =. 0x
    for_value. y do.
        a =. 65521|a+value
        b =. 65521|b+a
    end.
    8 hexadecimal (65536*b)+a
)
isqrt =: 3 : 0
    low =. 0x
    high =. 1x
    while. (high*high)<:y do.
        high =. 2*high
    end.
    while. (low+1)<high do.
        middle =. (low+high)intdiv 2
        if. (middle*middle)<:y do.
            low =. middle
        else.
            high =. middle
        end.
    end.
    low
)
peak =: 4 : 0
    if. 0=#y do.
        0
    else.
        >./|y-x
    end.
)
rms =: 4 : 'isqrt (+/*:y-x)intdiv #y'
zero_crossings =: 3 : '+/((}.y)<128)~:((}:y)<128)'
