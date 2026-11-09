maximum_index =: 3 : 'y i.>./y'
emission_factors =: 4 : 0
    emission =. 2{::x
    if. y=_1 do.
        (#emission)$1.0
    else.
        y{"1 emission
    end.
)
scaled_forward =: 4 : 0
    'initial transition emission' =. x
    count =. #initial
    forward =. (0,count)$0.0
    scales =. i.0
    emissions =. (0,count)$0.0
    loglik =. 0.0
    for_t. i.#y do.
        factors =. x emission_factors t{y
        row =. i.0
        scale =. 0.0
        for_j. i.count do.
            if. t=0 do.
                value =. (j{initial)*j{factors
            else.
                total =. 0.0
                for_i. i.count do.
                    total =. total+((<(t-1),i){forward)*(<i,j){transition
                end.
                value =. total*j{factors
            end.
            row =. row,value
            scale =. scale+value
        end.
        forward =. forward,row%scale
        scales =. scales,scale
        emissions =. emissions,factors
        loglik =. loglik+^.scale
    end.
    (<forward),(<0 0$0.0),(<scales),(<emissions),(<0 0$0.0),<loglik
)
forward_backward =: 4 : 0
    'initial transition emission' =. x
    'forward backward scales emissions posterior loglik' =. x scaled_forward y
    count =. #initial
    length =. #y
    backward =. (length,count)$0.0
    backward =. (count$1.0)(length-1)}backward
    for_t. |.i.length-1 do.
        for_i. i.count do.
            total =. 0.0
            for_j. i.count do.
                term =. ((<i,j){transition)*(<(t+1),j){emissions
                term =. term*(<(t+1),j){backward
                total =. total+term
            end.
            backward =. (total%(t+1){scales)(<t,i)}backward
        end.
    end.
    posterior =. forward*backward
    (<forward),(<backward),(<scales),(<emissions),(<posterior),<loglik
)
posterior_transition =: 4 : 0
    'result position state following' =. y
    transition =. 1{::x
    'forward backward scales emissions posterior loglik' =. result
    value =. ((<position,state){forward)*(<state,following){transition
    value =. value*(<(position+1),following){emissions
    value =. value*(<(position+1),following){backward
    value%(position+1){scales
)
viterbi =: 4 : 0
    'initial transition emission' =. x
    count =. #initial
    log_transition =. ^.transition
    scores =. (^.initial)+^.x emission_factors {.y
    predecessors =. (1,count)$0
    for_t. 1+i.<:#y do.
        factors =. ^.x emission_factors t{y
        next_scores =. i.0
        previous_states =. i.0
        for_j. i.count do.
            candidates =. scores+j{"1 log_transition
            previous =. maximum_index candidates
            previous_states =. previous_states,previous
            next_scores =. next_scores,(previous{candidates)+j{factors
        end.
        scores =. next_scores
        predecessors =. predecessors,previous_states
    end.
    path =. (#y)$0
    path =. (maximum_index scores)(<:#y)}path
    logprob =. ({:path){scores
    for_t. |.1+i.<:#y do.
        path =. ((<t,t{path){predecessors)(t-1)}path
    end.
    (<path),<logprob
)
decode =: 4 : 0
    fb =. x forward_backward y
    'path logprob' =. x viterbi y
    posterior =. 4{::fb
    posterior_path =. i.0
    confidence =. i.0
    for_row. posterior do.
        chosen =. maximum_index row
        posterior_path =. posterior_path,chosen
        confidence =. confidence,chosen{row
    end.
    (<path),(<logprob),(<posterior_path),(<confidence),<fb
)
