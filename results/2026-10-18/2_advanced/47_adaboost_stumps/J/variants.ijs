update_weights =: 3 : 0
    'rows labels weights stump' =. y
    for_i. i.#rows do.
        value =. stump stump_output i{rows
        weights =. ((i{weights)*^(-i{labels)*value)i}weights
    end.
    weights%ordered_sum weights
)
train_real =: 3 : 0
    'rows labels maximum bins smoothing convergence' =. y
    weights =. (#rows)$1.0%#rows
    prepared =. prepare rows
    cuts =. real_cuts (<rows),(<prepared),<bins
    rounds =. 0$a:
    bound =. 1.0
    reason =. 'completed'
    for_t. i.maximum do.
        candidate =. real_search (<rows),(<labels),(<weights),(<cuts),<bins
        z =. 1{::candidate
        if. z>:1.0-convergence do.
            reason =. 'converged'
            break.
        end.
        positive =. 3{::candidate
        negative =. 4{::candidate
        values =. 0.5*^.(positive+smoothing)%(negative+smoothing)
        'feature thresholds unused' =. 0{::candidate
        stump =. (<feature),(<thresholds),<values
        bound =. bound*z
        record =. (<stump),(<0),(<0.0),(<0.0),(<z),(<bound),(<weights),<0.0
        rounds =. rounds,<record
        weights =. update_weights (<rows),(<labels),(<weights),<stump
    end.
    (<rounds),(<reason),<cuts
)
train_gentle =: 3 : 0
    'rows labels maximum' =. y
    weights =. (#rows)$1.0%#rows
    prepared =. prepare rows
    rounds =. 0$a:
    for_t. i.maximum do.
        candidate =. regression_search (<rows),(<0.0+labels),(<weights),<prepared
        stump =. 0{::candidate
        record =. (<stump),(<0),(<1{::candidate),(<0.0),(<0.0),(<0.0),(<weights),<0.0
        rounds =. rounds,<record
        weights =. update_weights (<rows),(<labels),(<weights),<stump
    end.
    (<rounds),(<'completed'),<0$a:
)
train_logit =: 3 : 0
    'rows labels maximum clip' =. y
    scores =. (#rows)$0.0
    probabilities =. (#rows)$0.5
    prepared =. prepare rows
    rounds =. 0$a:
    for_t. i.maximum do.
        q =. probabilities*(1.0-probabilities)
        targets =. (-clip)>.clip<.((labels=1)-probabilities)%q
        weights =. q%ordered_sum q
        candidate =. regression_search (<rows),(<targets),(<weights),<prepared
        'feature thresholds original' =. 0{::candidate
        stump =. (<feature),(<thresholds),<original%2.0
        for_i. i.#rows do.
            scores =. ((i{scores)+stump stump_output i{rows)i}scores
            probabilities =. (1.0%(1.0+^_2.0*i{scores))i}probabilities
        end.
        total =. 0.0
        for_i. i.#rows do.
            total =. total+^.1.0+^(_2.0*i{labels)*i{scores
        end.
        record =. (<stump),(<0),(<1{::candidate),(<0.0),(<0.0),(<0.0),(<weights),<total%#rows
        rounds =. rounds,<record
    end.
    (<rounds),(<'completed'),<0$a:
)
