position_choices =: 4 : 0
    current =. i.y
    result =. (0,y)$0
    while. 1 do.
        result =. result,current
        position =. y-1
        while. position>:0 do.
            if. (position{current)<(x-y)+position do. break. end.
            position =. position-1
        end.
        if. position<0 do. result return. end.
        current =. (1+position{current) position}current
        for_index. (position+1)+i.y-(position+1) do.
            current =. (1+(index-1){current) index}current
        end.
    end.
)
reduced_fraction =: 3 : 0
    'numerator denominator' =. y
    divisor =. (|numerator)+.denominator
    (numerator div divisor),denominator div divisor
)
contrast =: 3 : 0
    'firsttotal firstsize secondtotal secondsize' =. y
    (secondsize*firsttotal)-firstsize*secondtotal
)
value_counts =: 3 : 0
    result =. 0 2$0
    for_value. /:~~.y do. result =. result,value,+/y=value end.
    result
)
doubled_ranks =: 3 : 0
    result =. (#y)$0
    smaller =. 0
    for_pair. value_counts y do.
        'value count' =. pair
        rank =. (2*smaller)+count+1
        result =. rank (I.y=value)}result
        smaller =. smaller+count
    end.
    result
)
split_list =: 4 : 0
    result =. 0$a:
    start =. 0
    for_size. x do.
        result =. result,<size{.start}.y
        start =. start+size
    end.
    result
)
sums_of_squares =: 3 : 0
    total =. +/#&>y
    grand =. (+/+/&>y)%100*total
    between =. within =. 0.0
    for_box. y do.
        sample =. >box
        center =. mean sample
        difference =. center-grand
        between =. between+(#sample)*(difference*difference)
        squares =. 0.0
        for_value. sample do.
            deviation =. (value%100)-center
            squares =. squares+deviation*deviation
        end.
        within =. within+squares
    end.
    between,within
)
f_statistic =: 3 : 0
    'between within groups total' =. y
    (between%groups-1)%(within%total-groups)
)
h_statistic =: 3 : 0
    'ranktotals sizes correction' =. y
    total =. +/sizes
    terms =. (ranktotals*ranktotals)%4*sizes
    value =. sequential_sum terms
    (((12*value)%(total*total+1))-3*total+1)%correction
)
