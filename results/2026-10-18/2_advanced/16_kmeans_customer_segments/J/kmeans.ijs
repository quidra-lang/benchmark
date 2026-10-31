squared_distance =: 4 : 0
    differences =. x-y
    ordered_sum differences*differences
)
assign =: 4 : 0
    labels =. 0$0
    errors =. 0$0.0
    for_point. x do.
        best =. 0
        nearest =. point squared_distance 0{y
        for_center. 1+i.(#y)-1 do.
            distance =. point squared_distance center{y
            if. distance<nearest do. best =. center
                nearest =. distance end.
        end.
        labels =. labels,best
        errors =. errors,nearest
    end.
    (<labels),<errors
)
mean_point =: 3 : 0
    totals =. ({:$y)$0.0
    for_point. y do. totals =. totals+point end.
    totals%#y
)
cluster_sizes =: 4 : 0
    sizes =. x$0
    for_label. y do. sizes =. (1+label{sizes) label}sizes end.
    sizes
)
cluster_center =: 4 : 0
    'labels center' =. y
    mean_point x#~labels=center
)
cluster_centers =: 4 : 0
    'labels count' =. y
    centers =. (0,{:$x)$0.0
    for_center. i.count do. centers =. centers,x cluster_center (<labels),<center end.
    centers
)
refill =: 4 : 0
    'labels errors' =. y
    sizes =. x cluster_sizes labels
    reseeds =. 0
    for_center. i.x do.
        if. center{sizes do. continue. end.
        candidates =. I.(labels{sizes)>:2
        values =. candidates{errors
        chosen =. (values i.>./values){candidates
        own =. chosen{labels
        sizes =. ((own{sizes)-1) own}sizes
        sizes =. (1+center{sizes) center}sizes
        labels =. center chosen}labels
        errors =. 0.0 chosen}errors
        reseeds =. reseeds+1
    end.
    (<labels),(<errors),<reseeds
)
lloyd =: 4 : 0
    'initial limit' =. y
    count =. #initial
    'labels errors' =. x assign initial
    iterations =. reseeds =. converged =. 0
    while. (iterations<limit)*.-.converged do.
        'labels errors added' =. count refill (<labels),<errors
        reseeds =. reseeds+added
        centers =. x cluster_centers (<labels),<count
        iterations =. iterations+1
        'next errors' =. x assign centers
        converged =. next-:labels
        labels =. next
    end.
    'labels errors added' =. count refill (<labels),<errors
    reseeds =. reseeds+added
    centers =. x cluster_centers (<labels),<count
    (<labels),(<centers),(<iterations),(<converged),<reseeds
)
sse =: 4 : 0
    'labels centers' =. y
    total =. 0.0
    for_index. i.#x do. total =. total+(index{x)squared_distance (index{labels){centers end.
    total
)
