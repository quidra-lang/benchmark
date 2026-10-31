find_peaks =: 3 : 0
    band =. 1{"1 y
    derivative =. 2{"1 y
    integrated =. 4{"1 y
    result =. 0 8$0x
    count =. #integrated
    for_moment. i.count do.
        value =. moment{integrated
        if. value<:0 do.
            continue.
        end.
        first =. 0>.moment-20
        previous =. (first+i.moment-first){integrated
        last =. (count-1)<.moment+20
        following =. ((moment+1)+i.last-moment){integrated
        if. (+./previous>:value)+.+./following>value do.
            continue.
        end.
        position =. 0>.moment-30
        for_index. (position+1)+i.moment-position do.
            if. (|index{band)>|position{band do.
                position =. index
            end.
        end.
        first =. 0>.moment-29
        slope =. >./|(first+i.(moment-first)+1){derivative
        result =. result,moment,position,value,(|position{band),slope,0 0 _1
    end.
    result
)
initial_levels =: 3 : 0
    integrated =. 400{.4{"1 y
    band =. |400{.1{"1 y
    ((>./integrated)intdiv 3),((+/integrated)intdiv 800),((>./band)intdiv 3),(+/band)intdiv 800
)
width_ms =: 4 : 0
    peak =. |y{x
    first =. 0>.y-25
    last =. ((#x)-1)<.y+25
    indices =. first+i.(last-first)+1
    selected =. indices#~(4*|indices{x)>:peak
    5*((({:selected)-{.selected)+1)
)
