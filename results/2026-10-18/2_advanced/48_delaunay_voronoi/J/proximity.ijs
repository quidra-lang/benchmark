sets_init =: 3 : 0
    SetParent =: 1+i.y
    SetSizes =: y$1
    SetCount =: y
)
find_set =: 3 : 0
    site =. y
    while. site~:(site-1){SetParent do.
        parent =. (site-1){SetParent
        SetParent =: ((parent-1){SetParent)(site-1)}SetParent
        site =. (site-1){SetParent
    end.
    site
)
join_sets =: 4 : 0
    first =. find_set x
    second =. find_set y
    if. first=second do.
        0 return.
    end.
    if. ((first-1){SetSizes)<(second-1){SetSizes do.
        'first second' =. second,first
    end.
    SetParent =: first(second-1)}SetParent
    SetSizes =: (((first-1){SetSizes)+(second-1){SetSizes)(first-1)}SetSizes
    SetCount =: SetCount-1
    1
)
nearest_neighbors =: 3 : 0
    'points neighbors' =. y
    result =. i.0
    for_i. i.#points do.
        adjacent =. /:~i{::neighbors
        distances =. i.0
        for_other. adjacent do.
            distances =. distances,(i{points)d2 (other-1){points
        end.
        result =. result,({.I.distances=<./distances){adjacent
    end.
    result
)
nearest_components =: 3 : 0
    sets_init #y
    for_i. i.#y do.
        (i+1)join_sets i{y
    end.
    roots =. i.0
    groups =. 0$a:
    for_site. 1+i.#y do.
        root =. find_set site
        index =. roots i.root
        if. index=#roots do.
            roots =. roots,root
            groups =. groups,<i.0
        end.
        groups =. (<(index{::groups),site)index}groups
    end.
    groups
)
kruskal =: 3 : 0
    'points edges' =. y
    distances =. i.0
    for_edge. edges do.
        distances =. distances,(((0{edge)-1){points)d2 ((1{edge)-1){points
    end.
    ordered =. /:distances
    sets_init #points
    result =. 0 2$0
    for_index. ordered do.
        'first second' =. index{edges
        if. first join_sets second do.
            result =. result,first,second
            if. SetCount=1 do.
                break.
            end.
        end.
    end.
    result
)
is_gabriel =: 3 : 0
    'points edge directed' =. y
    'i j' =. edge-1
    for_pair. (i,j),:j,i do.
        'u v' =. pair
        opposite =. (<u,v){directed
        if. opposite do.
            if. (dot ((opposite-1){points),(i{points),:j{points)<:0 do.
                0 return.
            end.
        end.
    end.
    1
)
is_relative =: 3 : 0
    'points edge' =. y
    first =. ((0{edge)-1){points
    second =. ((1{edge)-1){points
    distance =. first d2 second
    for_point. points do.
        if. ((first d2 point)<distance)*.(second d2 point)<distance do.
            0 return.
        end.
    end.
    1
)
greedy_route =: 3 : 0
    'points neighbors start target' =. y
    path =. ,start
    length =. 0.0
    current =. start
    while. current~:target do.
        adjacent =. /:~(current-1){::neighbors
        distances =. i.0
        for_other. adjacent do.
            distances =. distances,((other-1){points)d2 (target-1){points
        end.
        following =. ({.I.distances=<./distances){adjacent
        length =. length+%:0.0+((current-1){points)d2 (following-1){points
        path =. path,following
        current =. following
    end.
    (<path),<length
)
dijkstra =: 3 : 0
    'points neighbors start' =. y
    distances =. (#points)$_
    previous =. (#points)$0
    visited =. (#points)$0
    distances =. 0.0(start-1)}distances
    for_iteration. i.#points do.
        candidates =. I.-.visited
        if. 0=#candidates do.
            break.
        end.
        values =. candidates{distances
        current =. ({.I.values=<./values){candidates
        visited =. 1 current}visited
        for_other. current{::neighbors do.
            candidate =. (current{distances)+%:0.0+(current{points)d2 (other-1){points
            if. candidate<(other-1){distances do.
                distances =. candidate(other-1)}distances
                previous =. (current+1)(other-1)}previous
            end.
        end.
    end.
    (<distances),<previous
)
