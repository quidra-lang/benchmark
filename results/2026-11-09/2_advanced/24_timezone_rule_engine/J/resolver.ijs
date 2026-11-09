period_starts =: 3 : 0
    starts =. 0$0
    for_period. y do. starts =. starts,0{::>period end.
    starts
)
index_at =: 4 : 0
    starts =. period_starts x
    low =. 0
    high =. #starts
    while. low<high do.
        middle =. (low+high)div 2
        if. (middle{starts)<:y do. low =. middle+1
        else. high =. middle end.
    end.
    low-1
)
end_of =: 4 : 0
    if. (y+1)<#x do. 0{::(y+1){::x
    else. PositiveInfinity end.
)
nearby =: 4 : 0
    'first last' =. y
    low =. x index_at first-57600
    high =. x index_at last+57600
    low+i.1+high-low
)
local_candidates =: 4 : 0
    found =. 0$0
    for_index. x nearby y,y do.
        period =. index{::x
        time =. y-1{::period
        if. ((0{::period)<:time)*.time<x end_of index do. found =. found,index end.
    end.
    found
)
skipping_transition =: 4 : 0
    for_index. x nearby y,y do.
        if. index=0 do. continue. end.
        time =. 0{::index{::x
        before =. time+1{::(index-1){::x
        after =. time+1{::index{::x
        if. (before<:y)*.y<after do. index return. end.
    end.
    _1
)
