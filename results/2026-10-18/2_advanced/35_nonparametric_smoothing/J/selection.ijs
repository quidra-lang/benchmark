ordered_sum =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
residual_square =: 4 : 0
    result =. 0.0
    for_index. i.#x do.
        difference =. (index{x)-index{y
        result =. result+difference*difference
    end.
    result
)
cross_validation_score =: 4 : 0
    'predicted defined' =. y
    if. -.*/defined do.
        0 0.0 return.
    end.
    1,(x residual_square predicted)%#x
)
generalized_score =: 4 : 0
    'fitted edf' =. y
    factor =. 1-edf%#x
    ((x residual_square fitted)%#x)%(factor*factor)
)
choose_candidate =: 4 : 0
    best =. _1
    for_index. i.#x do.
        if. index{y do.
            if. best<0 do.
                best =. index
            elseif. (index{x)<best{x do.
                best =. index
            end.
        end.
    end.
    best
)
