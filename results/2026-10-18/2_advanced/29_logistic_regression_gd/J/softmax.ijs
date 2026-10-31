sm_shifted =: 4 : 0
    scores =. i.0
    for_row. x do.
        scores =. scores,row score y
    end.
    scores->./scores
)
sm_probabilities =: 4 : 0
    shifted =. x sm_shifted y
    (^shifted)%ordered_sum ^shifted
)
sm_class =: 3 : 'y i.>./y'
sm_loss =: 3 : 0
    'weights vector label' =. y
    shifted =. weights sm_shifted vector
    (^.ordered_sum ^shifted)-label{shifted
)
sm_average_loss =: 3 : 0
    'weights vectors labels' =. y
    total =. 0.0
    for_i. i.#vectors do.
        total =. total+sm_loss (<weights),(<i{vectors),<i{labels
    end.
    total%#vectors
)
sm_penalty =: 3 : 0
    total =. 0.0
    for_row. y do.
        for_weight. }.row do.
            total =. total+weight*weight
        end.
    end.
    total
)
sm_objective =: 3 : 0
    'weights vectors labels lambda' =. y
    (sm_average_loss 3{.y)+lambda*(sm_penalty weights)%2.0
)
sm_gradient =: 3 : 0
    'weights vectors labels lambda' =. y
    'classes size' =. $weights
    totals =. (classes,size)$0.0
    for_i. i.#vectors do.
        vector =. i{vectors
        probabilities =. weights sm_probabilities vector
        for_k. i.classes do.
            residual =. (k{probabilities)-k=i{labels
            row =. (k{totals)+residual*vector
            totals =. row k}totals
        end.
    end.
    result =. totals%#vectors
    for_k. i.classes do.
        row =. k{result
        regularization =. 0,lambda*}.k{weights
        result =. (row+regularization)k}result
    end.
    result
)
sm_train =: 3 : 0
    'vectors labels classes lambda rate iterations' =. y
    weights =. (classes,{:$vectors)$0.0
    checkpoints =. ,<(<0),<weights
    for_t. 1+i.iterations do.
        direction =. sm_gradient (<weights),(<vectors),(<labels),<lambda
        weights =. weights-rate*direction
        if. 0=100|t do.
            checkpoints =. checkpoints,<(<t),<weights
        end.
    end.
    checkpoints
)
