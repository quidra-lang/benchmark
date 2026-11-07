ordered_sum =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
score =: 4 : 'ordered_sum x*y'
probability =: 3 : 0
    if. y>:0 do.
        1%1+^-y return.
    end.
    e =. ^y
    e%1+e
)
loss =: 4 : '((y>.0)-x*y)+^.1+^-|y'
average_loss =: 3 : 0
    'weights vectors targets' =. y
    total =. 0.0
    for_i. i.#vectors do.
        total =. total+(i{targets)loss weights score i{vectors
    end.
    total%#vectors
)
penalty =: 3 : 'ordered_sum *:}.y'
objective =: 3 : 0
    'weights vectors targets lambda' =. y
    (average_loss 3{.y)+lambda*(penalty weights)%2.0
)
gradient =: 3 : 0
    'weights vectors targets lambda' =. y
    totals =. (#weights)$0.0
    for_i. i.#vectors do.
        vector =. i{vectors
        residual =. (probability weights score vector)-i{targets
        totals =. totals+residual*vector
    end.
    regularization =. 0,lambda*}.weights
    (totals%#vectors)+regularization
)
hessian =: 3 : 0
    'weights vectors lambda' =. y
    size =. #weights
    totals =. (size,size)$0.0
    for_vector. vectors do.
        pi =. probability weights score vector
        variance =. pi*1-pi
        for_j. i.size do.
            for_k. i.j+1 do.
                value =. (variance*j{vector)*k{vector
                totals =. (value+(<j,k){totals)(<j,k)}totals
            end.
        end.
    end.
    matrix =. (size,size)$0.0
    for_j. i.size do.
        for_k. i.j+1 do.
            value =. ((<j,k){totals)%#vectors
            if. (j=k)*.j>:1 do.
                value =. value+lambda
            end.
            matrix =. value(<j,k)}matrix
            matrix =. value(<k,j)}matrix
        end.
    end.
    matrix
)
