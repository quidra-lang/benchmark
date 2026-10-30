crossing_positions =: 3 : 0
    positions =. VertexCount$0
    for_layer. y do.
        vertices =. >layer
        positions =. (i.#vertices)vertices}positions
    end.
    positions
)
accumulator_crossings =: 4 : 0
    'positions lower_size' =. y
    capacity =. 1
    while. capacity<lower_size do.
        capacity =. capacity*2
    end.
    tree =. ((2*capacity)-1)$0
    pairs =. positions{~2{."1 x
    pairs =. (/:pairs){pairs
    count =. 0
    for_pair. pairs do.
        index =. (1{pair)+capacity-1
        tree =. (1+index{tree)index}tree
        while. index>0 do.
            if. 2|index do.
                count =. count+(index+1){tree
            end.
            index =. (index-1)intdiv 2
            tree =. (1+index{tree)index}tree
        end.
    end.
    count
)
brute_crossings =: 4 : 0
    positions =. y
    count =. 0
    for_i. i.#x do.
        'p1 q1 edge' =. i{x
        for_segment. (i+1)}.x do.
            'p2 q2 edge' =. segment
            if. 0>((p1{positions)-p2{positions)*((q1{positions)-q2{positions) do.
                count =. count+1
            end.
        end.
    end.
    count
)
gap_crossings =: 3 : 0
    positions =. crossing_positions y
    counts =. i.0
    for_i. i.#Gaps do.
        count =. (i{::Gaps)accumulator_crossings(<positions),<#(i+1){::y
        counts =. counts,count
    end.
    counts
)
total_crossings =: 3 : '+/gap_crossings y'
local_crossings =: 4 : 0
    positions =. crossing_positions y
    gaps =. (x-1),x
    gaps =. gaps#~(gaps>:0)*.gaps<#Gaps
    count =. 0
    for_gap. gaps do.
        args =. (<positions),<#(gap+1){::y
        count =. count+(gap{::Gaps)accumulator_crossings args
    end.
    count
)
adjacent_cost =: 3 : 0
    'first second positions' =. y
    count =. 0
    for_reference. (<UpperNeighbors),<LowerNeighbors do.
        reference =. >reference
        for_a. first{::reference do.
            for_b. second{::reference do.
                count =. count+(a{positions)>b{positions
            end.
        end.
    end.
    count
)
