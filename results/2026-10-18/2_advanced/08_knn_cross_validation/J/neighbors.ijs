distance =: 3 : 0
    'a b metric' =. y
    differences =. a-b
    select. metric
    case. 'squared_euclidean' do. real_sum differences*differences
    case. 'manhattan' do. real_sum |differences
    case. 'chebyshev' do. >./|differences
    case. 'cosine' do.
        dot =. real_sum a*b
        na =. %:real_sum a*a
        nb =. %:real_sum b*b
        if. (na=!.0 0)+.nb=!.0 0 do. 1.0 else. 1.0-dot%(na*nb) end.
    end.
)
sort_neighbors =: 3 : 0
    keys =. 0 2$a:
    for_box. y do.
        'gap row' =. >box
        keys =. keys,1 2$(<gap),<'id' get_key row
    end.
    (/:keys){y
)
neighbor_order =: 3 : 0
    'query references metric' =. y
    neighbors =. 0$a:
    for_box. references do.
        'vector row' =. >box
        gap =. distance (<query),(<vector),<metric
        neighbors =. neighbors,<(<gap),<row
    end.
    sort_neighbors neighbors
)
vote =: 4 : 0
    labels =. 0$a:
    for_box. y do. labels =. labels,<'label' get_key 1{::>box end.
    labels =. /:~~.labels
    counts =. (#labels)$0
    distances =. weights =. (#labels)$0.0
    total =. 0.0
    for_box. y do.
        'gap row' =. >box
        position =. labels i.<'label' get_key row
        weight =. 1.0%(gap+0.000000001)
        counts =. (1+position{counts) position}counts
        distances =. (gap+position{distances) position}distances
        weights =. (weight+position{weights) position}weights
        total =. total+weight
    end.
    if. x-:'uniform' do. priority =. counts else. priority =. weights end.
    keys =. 0 3$a:
    for_index. i.#labels do. keys =. keys,1 3$(<-index{priority),(<index{distances),index{labels end.
    ranked =. /:keys
    if. x-:'uniform' do. shares =. (real counts)%real #y else. shares =. weights%total end.
    first =. {.ranked
    runner =. '-'
    runnershare =. 0.0
    if. 1<#ranked do.
        second =. 1{ranked
        runner =. second{::labels
        runnershare =. second{shares
    end.
    'label share runner_up runner_share' record (first{labels),(<first{shares),(<runner),<runnershare
)
estimate =: 4 : 0
    weighted =. weights =. total =. 0.0
    for_box. y do.
        'gap row' =. >box
        target =. 'target' get_key row
        total =. total+target
        weight =. 1.0%(gap+0.000000001)
        weighted =. weighted+weight*target
        weights =. weights+weight
    end.
    if. x-:'uniform' do. total%real #y else. weighted%weights end.
)
