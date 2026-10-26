distance_table =: 3 : 0
    count =. #y
    table =. (count,count)$0.0
    for_first. i.count do.
        for_second. (first+1)+i.count-(first+1) do.
            distance =. %:(first{y)squared_distance second{y
            table =. distance (<first,second)}table
            table =. distance (<second,first)}table
        end.
    end.
    table
)
silhouettes =: 3 : 0
    'table labels sizes' =. y
    count =. #sizes
    values =. 0$0.0
    for_index. i.#labels do.
        own =. index{labels
        if. 1=own{sizes do. values =. values,0.0 continue. end.
        totals =. count$0.0
        for_other. i.#labels do.
            if. other=index do. continue. end.
            label =. other{labels
            totals =. ((label{totals)+(<index,other){table) label}totals
        end.
        inner =. (own{totals)%(own{sizes)-1
        others =. (i.count)#~(i.count)~:own
        outer =. <./(others{totals)%others{sizes
        largest =. inner>.outer
        if. largest=0 do. values =. values,0.0 else. values =. values,(outer-inner)%largest end.
    end.
    values
)
calinski_harabasz =: 4 : 0
    'centers sizes within' =. y
    overall =. mean_point x
    between =. 0.0
    for_index. i.#centers do. between =. between+(index{sizes)*(index{centers)squared_distance overall end.
    (between%(#centers)-1)%(within%(#x)-#centers)
)
davies_bouldin =: 4 : 0
    'labels centers sizes' =. y
    count =. #centers
    spreads =. count$0.0
    for_index. i.#x do.
        label =. index{labels
        distance =. %:(index{x)squared_distance label{centers
        spreads =. ((label{spreads)+distance) label}spreads
    end.
    spreads =. spreads%sizes
    total =. 0.0
    for_first. i.count do.
        worst =. 0.0
        for_second. i.count do.
            if. first=second do. continue. end.
            value =. ((first{spreads)+second{spreads)%%:(first{centers)squared_distance second{centers
            worst =. worst>.value
        end.
        total =. total+worst
    end.
    total%count
)
elbow =: 3 : 0
    'k minimum maximum within first last' =. y
    x =. (k-minimum)%maximum-minimum
    vertical =. (within-last)%first-last
    ((1-x)-vertical)%%:2
)
hartigan =: 3 : 0
    'within next count k' =. y
    ((within%next)-1)*((count-k)-1)
)
pair_count =: 3 : '(y*y-1)div 2'
adjusted_rand_index =: 4 : 0
    first =. (~.x)i.x
    second =. (~.y)i.y
    joint =. first,.second
    shared =. 0
    for_pair. ~.joint do.
        count =. +/*./"1 joint="1 pair
        shared =. shared+pair_count count
    end.
    firstpairs =. secondpairs =. 0
    for_label. ~.first do. firstpairs =. firstpairs+pair_count +/first=label end.
    for_label. ~.second do. secondpairs =. secondpairs+pair_count +/second=label end.
    total =. pair_count #x
    numerator =. 2*((total*shared)-firstpairs*secondpairs)
    denominator =. (total*(firstpairs+secondpairs))-((2*firstpairs)*secondpairs)
    if. denominator=0 do. 1.0 else. numerator%denominator end.
)
