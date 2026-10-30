empty_counts =: 3 : 0
    'initial transition emission' =. y
    (<0.0*initial),(<0.0*transition),<0.0*emission
)
smoothed =: 4 : 0
    'initial transition emission' =. y
    (<normalize initial+x),(<normalize"1 transition+x),<normalize"1 emission+x
)
baum_welch_step =: 3 : 0
    'model sequences pseudocount' =. y
    'initial transition emission' =. empty_counts model
    count =. #initial
    for_observations. sequences do.
        observations =. >observations
        result =. model forward_backward observations
        posterior =. 4{::result
        initial =. initial+0{posterior
        for_t. i.#observations do.
            observation =. t{observations
            for_i. i.count do.
                if. observation~:_1 do.
                    position =. <i,observation
                    emission =. ((position{emission)+(<t,i){posterior)position}emission
                end.
                if. (t+1)<#observations do.
                    for_j. i.count do.
                        position =. <i,j
                        value =. model posterior_transition (<result),(<t),(<i),<j
                        transition =. (value+position{transition)position}transition
                    end.
                end.
            end.
        end.
    end.
    pseudocount smoothed (<initial),(<transition),<emission
)
estimate_by_counting =: 3 : 0
    'template observations paths alpha' =. y
    'initial transition emission' =. empty_counts template
    for_record. i.#paths do.
        path =. record{::paths
        sequence =. record{::observations
        initial =. (1+({.path){initial)({.path)}initial
        for_t. i.#path do.
            state =. t{path
            observation =. t{sequence
            if. observation~:_1 do.
                position =. <state,observation
                emission =. (1+position{emission)position}emission
            end.
            if. (t+1)<#path do.
                position =. <state,(t+1){path
                transition =. (1+position{transition)position}transition
            end.
        end.
    end.
    alpha smoothed (<initial),(<transition),<emission
)
total_loglik =: 4 : 0
    total =. 0.0
    for_observations. y do.
        result =. x scaled_forward >observations
        total =. total+5{::result
    end.
    total
)
