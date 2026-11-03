root =: 4 : 0
    value =. (40000*x)intdiv y
    low =. 0x
    high =. 1x
    while. (high*high)<:value do.
        high =. high*2
    end.
    while. 1<high-low do.
        middle =. (low+high)intdiv 2
        if. (middle*middle)<:value do.
            low =. middle
        else.
            high =. middle
        end.
    end.
    (low+1)intdiv 2
)
statistics =: 3 : 0
    'rr nn pairs' =. y
    result =. 14$_1x
    result =. 0 (8 12)}result
    count =. #rr
    amount =. #nn
    pair_count =. #pairs
    if. count do.
        mean_rr =. (100*+/rr)rdiv count
        mean_hr =. (6000000*count)rdiv +/rr
        shortest =. rr i.<./rr
        longest =. rr i.>./rr
        result =. (mean_rr,mean_hr,shortest,longest)0 1 2 3}result
    end.
    if. amount do.
        result =. ((100*+/nn)rdiv amount)4}result
    end.
    if. amount>:2 do.
        total =. +/nn
        numerator =. (amount*+/nn*nn)-total*total
        result =. (numerator root amount*(amount-1))5}result
    end.
    differences =. (1{"1 pairs)-0{"1 pairs
    totals =. +/"1 pairs
    nn50 =. +/50<|differences
    result =. nn50 (8)}result
    if. pair_count do.
        result =. ((+/differences*differences)root pair_count)6}result
        result =. ((10000*nn50)rdiv pair_count)9}result
    end.
    if. pair_count>:2 do.
        total =. +/differences
        numerator =. (pair_count*+/differences*differences)-total*total
        denominator =. pair_count*(pair_count-1)
        result =. (numerator root denominator)7}result
        result =. (numerator root 2*denominator)10}result
        total =. +/totals
        numerator =. (pair_count*+/totals*totals)-total*total
        result =. (numerator root 2*denominator)11}result
    end.
    bins =. /:~(16*nn)intdiv 125
    histogram =. 0 2$0x
    for_bucket. ~.bins do.
        histogram =. histogram,bucket,+/bins=bucket
    end.
    maximum =. 0
    if. #histogram do.
        maximum =. >./1{"1 histogram
        result =. ((100*amount)rdiv maximum)13}result
    end.
    result =. maximum (12)}result
    (<result),<histogram
)
consecutive_ranges =: 3 : 0
    result =. 0 2$0x
    for_index. y do.
        last =. (#result)-1
        if. last<0 do.
            result =. result,index,index
        elseif. index=1+(<last,1){result do.
            result =. index (<last,1)}result
        else.
            result =. result,index,index
        end.
    end.
    result
)
