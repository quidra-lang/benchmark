draw =: 3 : 0
    if. RngMode=0 do.
        GenerationState =: 2147483647|48271*GenerationState
        GenerationState
    else.
        GameState =: 2147483647|48271*GameState
        GameState
    end.
)
rnd =: 3 : 'y|draw '''''
roll_dice =: 3 : 0
    'count sides' =. y
    total =. 0
    for_die. i.count do. total =. total+1+rnd sides end.
    total
)
weighted_select =: 3 : 0
    value =. rnd +/y
    cumulative =. 0
    for_index. i.#y do.
        cumulative =. cumulative+index{y
        if. value<cumulative do. index return. end.
    end.
    <: #y
)
