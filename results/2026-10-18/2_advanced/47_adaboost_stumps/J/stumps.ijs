intdiv =: 4 : '<.(x: x)%x: y'
ordered_sum =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
stump_feature =: 0&{::
stump_thresholds =: 1&{::
stump_values =: 2&{::
stump_output =: 4 : 0
    'feature thresholds values' =. x
    (+/thresholds<feature{y){values
)
stump_outputs =: 4 : 0
    result =. i.0
    for_row. y do.
        result =. result,x stump_output row
    end.
    result
)
prepare =: 3 : 0
    result =. 0$a:
    for_j. i.{:$y do.
        column =. j{"1 y
        order =. /:column
        distinct =. ~.order{column
        batches =. 0$a:
        for_value. distinct do.
            batches =. batches,<I.column=value
        end.
        thresholds =. ((0{distinct)-1.0),((}:distinct)+}.distinct)%2.0
        result =. result,<(<order),(<distinct),(<batches),<thresholds
    end.
    result
)
candidate_error =: 1&{::
choose =: 3 : 0
    values =. candidate_error&>y
    minimum =. <./values
    ({.I.values<:minimum+0.000000001){::y
)
discrete_search =: 3 : 0
    'rows labels weights prepared' =. y
    positive =. ordered_sum (labels=1)#weights
    negative =. ordered_sum (labels=_1)#weights
    candidates =. 0$a:
    for_j. i.#prepared do.
        'order distinct batches thresholds' =. j{::prepared
        left_positive =. left_negative =. 0.0
        for_k. i.#thresholds do.
            if. k do.
                for_i. (k-1){::batches do.
                    if. (i{labels)=1 do.
                        left_positive =. left_positive+i{weights
                    else.
                        left_negative =. left_negative+i{weights
                    end.
                end.
            end.
            threshold =. k{thresholds
            stump =. (<j),(<,threshold),<i.0
            candidates =. candidates,<(<stump),(<left_positive+(negative-left_negative)),(<1),(<i.0),<i.0
            candidates =. candidates,<(<stump),(<left_negative+(positive-left_positive)),(<_1),(<i.0),<i.0
        end.
    end.
    choose candidates
)
regression_search =: 3 : 0
    'rows targets weights prepared' =. y
    total_weight =. ordered_sum weights
    total_target =. ordered_sum weights*targets
    total_square =. ordered_sum (weights*targets)*targets
    candidates =. 0$a:
    for_j. i.#prepared do.
        'order distinct batches thresholds' =. j{::prepared
        left_weight =. left_target =. 0.0
        for_k. i.#thresholds do.
            if. k do.
                for_i. (k-1){::batches do.
                    left_weight =. left_weight+i{weights
                    left_target =. left_target+(i{weights)*i{targets
                end.
            end.
            right_weight =. total_weight-left_weight
            right_target =. total_target-left_target
            left =. 0.0
            gain =. (right_target*right_target)%right_weight
            if. k do.
                left =. left_target%left_weight
                gain =. ((left_target*left_target)%left_weight)+(right_target*right_target)%right_weight
            end.
            right =. right_target%right_weight
            stump =. (<j),(<,k{thresholds),<left,right
            candidates =. candidates,<(<stump),(<total_square-gain),(<0),(<i.0),<i.0
        end.
    end.
    choose candidates
)
multiclass_search =: 3 : 0
    'rows labels weights prepared classes' =. y
    total =. ordered_sum weights
    class_weights =. classes$0.0
    for_i. i.#rows do.
        c =. (i{labels)-1
        class_weights =. ((c{class_weights)+i{weights)c}class_weights
    end.
    candidates =. 0$a:
    for_j. i.#prepared do.
        'order distinct batches thresholds' =. j{::prepared
        left =. classes$0.0
        for_k. i.#thresholds do.
            if. k do.
                for_i. (k-1){::batches do.
                    c =. (i{labels)-1
                    left =. ((c{left)+i{weights)c}left
                end.
            end.
            right =. class_weights-left
            a =. {.\:left
            b =. {.\:right
            stump =. (<j),(<,k{thresholds),<(a+1),b+1
            candidates =. candidates,<(<stump),(<total-((a{left)+b{right)),(<0),(<i.0),<i.0
        end.
    end.
    choose candidates
)
real_cuts =: 3 : 0
    'rows prepared bins' =. y
    result =. 0$a:
    for_j. i.#prepared do.
        order =. 0{::j{::prepared
        values =. j{"1 order{rows
        cuts =. i.0
        for_b. 1+i.bins-1 do.
            rank =. <.(b*#rows)intdiv bins
            cuts =. cuts,(((rank-1){values)+rank{values)%2.0
        end.
        result =. result,<cuts
    end.
    result
)
real_search =: 3 : 0
    'rows labels weights cuts bins' =. y
    candidates =. 0$a:
    for_j. i.#cuts do.
        thresholds =. j{::cuts
        positive =. negative =. bins$0.0
        for_i. i.#rows do.
            bin =. +/thresholds<(<i,j){rows
            if. (i{labels)=1 do.
                positive =. ((bin{positive)+i{weights)bin}positive
            else.
                negative =. ((bin{negative)+i{weights)bin}negative
            end.
        end.
        z =. 2.0*ordered_sum %:positive*negative
        stump =. (<j),(<thresholds),<i.0
        candidates =. candidates,<(<stump),(<z),(<0),(<positive),<negative
    end.
    choose candidates
)
