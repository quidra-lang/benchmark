draw =: 4 : 0
    total =. 0.0
    for_weight. y do.
        total =. total+weight
    end.
    state =. 2147483647|48271*x:x
    threshold =. ((0.0+state)%2147483647.0)*total
    cumulative =. 0.0
    for_j. i.#y do.
        cumulative =. cumulative+j{y
        if. threshold<cumulative do.
            j,state return.
        end.
    end.
    ((#y)-1),state
)
synthetic_sequence =: 4 : 0
    'initial transition emission' =. x
    'length seed' =. y
    states =. i.0
    observations =. i.0
    for_t. i.length do.
        weights =. initial
        if. t do.
            weights =. ({:states){transition
        end.
        'state seed' =. seed draw weights
        'symbol seed' =. seed draw state{emission
        states =. states,state
        observations =. observations,symbol
    end.
    (<states),(<observations),<seed
)
posterior_path =: 4 : 0
    'forward seed' =. y
    transition =. 1{::x
    path =. (#forward)$0
    'state seed' =. seed draw {:forward
    path =. state (<:#forward)}path
    for_t. |.i.<:#forward do.
        following =. (t+1){path
        weights =. (t{forward)*following{"1 transition
        'state seed' =. seed draw weights
        path =. state t}path
    end.
    (<path),<seed
)
