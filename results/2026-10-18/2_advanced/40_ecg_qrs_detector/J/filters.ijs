at =: 4 : 0
    if. y<0 do.
        0x
    else.
        y{x
    end.
)
filter_ecg =: 3 : 0
    count =. #y
    cumulative =. count$0x
    moving =. count$0x
    low =. count$0x
    band =. count$0x
    derivative =. count$0x
    squared =. count$0x
    integrated =. count$0x
    window =. 0x
    for_index. i.count do.
        value =. ((2*cumulative at index-1)-cumulative at index-2)+index{y
        value =. (value-2*y at index-6)+y at index-12
        cumulative =. value index}cumulative
        low =. (value intdiv 32)index}low
        value =. ((moving at index-1)+index{low)-low at index-32
        moving =. value index}moving
        value =. (low at index-16)-value intdiv 32
        band =. value index}band
        value =. ((((2*value)+band at index-1)-band at index-3)-2*band at index-4)intdiv 8
        derivative =. value index}derivative
        squared =. (value*value)index}squared
        window =. (window+index{squared)-squared at index-30
        integrated =. (window intdiv 30)index}integrated
    end.
    low,.band,.derivative,.squared,.integrated
)
