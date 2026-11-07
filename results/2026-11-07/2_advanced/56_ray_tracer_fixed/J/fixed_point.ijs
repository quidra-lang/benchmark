S =: 4096x
floor_div =: 4 : '<.(x:x)%x:y'
fixed_mul =: 4 : '(x*y)floor_div S'
isqrt =: 3 : 0
    value =. x:y
    low =. 0x
    high =. 1x
    while. (high*high)<:value do.
        high =. high*2
    end.
    while. (low+1)<high do.
        middle =. (low+high)floor_div 2
        if. (middle*middle)<:value do.
            low =. middle
        else.
            high =. middle
        end.
    end.
    low
)
