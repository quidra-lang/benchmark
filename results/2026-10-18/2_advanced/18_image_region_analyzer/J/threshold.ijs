histogram =: 3 : 0
    'name width height maximum pixels' =. y
    counts =. (maximum+1)$0
    for_value. ,pixels do. counts =. (1+value{counts) value}counts end.
    belowcounts =. +/\counts
    belowsums =. +/\counts*i.maximum+1
    present =. I.counts>0
    total =. {:belowsums
    count =. width*height
    median =. {.I.(2*belowcounts)>:count
    mode =. counts i.>./counts
    binwidth =. (maximum+8)div 8
    bins =. 0$0
    for_start. binwidth*i.1+maximum div binwidth do.
        bins =. bins,+/binwidth{.start}.counts
    end.
    (<counts),(<belowcounts),(<belowsums),(<total),(<count),(<{.present),(<{:present),(<median),(<mode),(<#present),(<binwidth),<bins
)
compare_scores =: 4 : 0
    'a b' =. _2{.x
    'c d' =. _2{.y
    first =. a div b
    second =. c div d
    if. first~:second do. *first-second return. end.
    *((b|a)*d)-(d|c)*b
)
otsu =: 3 : 0
    'counts belowcounts belowsums total count minimum maximum median mode levels binwidth bins' =. y
    candidates =. 0 7$0
    for_cutoff. i.(#counts)-1 do.
        below =. cutoff{belowcounts
        above =. count-below
        if. (0=cutoff{counts)+.above=0 do. continue. end.
        sbelow =. cutoff{belowsums
        sabove =. total-sbelow
        numerator =. ((sbelow*sbelow)*above)+(sabove*sabove)*below
        candidate =. cutoff,below,sbelow,above,sabove,numerator,below*above
        position =. #candidates
        for_index. i.#candidates do.
            if. 0<candidate compare_scores index{candidates do. position =. index break. end.
        end.
        candidates =. (position{.candidates),candidate,position}.candidates
    end.
    cutoff =. upper =. minimum
    if. #candidates do.
        cutoff =. 0{0{candidates
        upper =. ({.I.(counts>0)*.(i.#counts)>cutoff)-1
    end.
    (<cutoff),(<upper),<candidates
)
isodata =: 3 : 0
    'counts belowcounts belowsums total count minimum maximum median mode levels binwidth bins' =. y
    cutoff =. total div count
    iterations =. 0
    while. 1 do.
        below =. cutoff{belowcounts
        above =. count-below
        if. (below=0)+.above=0 do. break. end.
        sbelow =. cutoff{belowsums
        sabove =. total-sbelow
        next =. ((sbelow*above)+sabove*below)div 2*below*above
        iterations =. iterations+1
        if. next=cutoff do. break. end.
        cutoff =. next
        if. iterations=100 do. break. end.
    end.
    cutoff,iterations
)
