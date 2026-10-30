model_rounds =: 0&{::
model_reason =: 1&{::
model_cuts =: 2&{::
round_stump =: 0&{::
round_polarity =: 1&{::
round_error =: 2&{::
round_alpha =: 3&{::
round_z =: 4&{::
round_bound =: 5&{::
round_weights =: 6&{::
round_loss =: 7&{::
train_discrete =: 3 : 0
    'rows labels maximum shrinkage initial_weights' =. y
    weights =. initial_weights
    if. 0=#weights do.
        weights =. (#rows)$1.0%#rows
    end.
    prepared =. prepare rows
    rounds =. 0$a:
    bound =. 1.0
    reason =. 'completed'
    for_t. i.maximum do.
        candidate =. discrete_search (<rows),(<labels),(<weights),<prepared
        error =. 1{::candidate
        if. error>:0.5 do.
            reason =. 'weak'
            break.
        end.
        if. error<:0.0000000001 do.
            alpha =. 1.0
        else.
            alpha =. shrinkage*0.5*^.(1.0-error)%error
        end.
        polarity =. 2{::candidate
        'feature thresholds unused' =. 0{::candidate
        stump =. (<feature),(<thresholds),<(-polarity*alpha),polarity*alpha
        previous =. weights
        for_i. i.#rows do.
            decision =. polarity
            if. ((<i,feature){rows)<:0{thresholds do.
                decision =. -polarity
            end.
            exponent =. alpha
            if. decision=i{labels do.
                exponent =. -alpha
            end.
            weights =. ((i{weights)*^exponent)i}weights
        end.
        z =. ordered_sum weights
        weights =. weights%z
        bound =. bound*z
        record =. (<stump),(<polarity),(<error),(<alpha),(<z),(<bound),(<previous),<0.0
        rounds =. rounds,<record
        if. error<:0.0000000001 do.
            reason =. 'perfect'
            break.
        end.
    end.
    (<rounds),(<reason),<0$a:
)
train_samme =: 3 : 0
    'rows labels classes maximum' =. y
    weights =. (#rows)$1.0%#rows
    prepared =. prepare rows
    rounds =. 0$a:
    reason =. 'completed'
    for_t. i.maximum do.
        candidate =. multiclass_search (<rows),(<labels),(<weights),(<prepared),<classes
        error =. 1{::candidate
        if. error>:(classes-1)%classes do.
            reason =. 'weak'
            break.
        end.
        if. error<:0.0000000001 do.
            alpha =. 1.0
        else.
            alpha =. (^.(1.0-error)%error)+^.classes-1
        end.
        stump =. 0{::candidate
        for_i. i.#rows do.
            if. (stump stump_output i{rows)~:i{labels do.
                weights =. ((i{weights)*^alpha)i}weights
            end.
        end.
        weights =. weights%ordered_sum weights
        record =. (<stump),(<0),(<error),(<alpha),(<0.0),(<0.0),(<i.0),<0.0
        rounds =. rounds,<record
        if. error<:0.0000000001 do.
            reason =. 'perfect'
            break.
        end.
    end.
    (<rounds),(<reason),<0$a:
)
