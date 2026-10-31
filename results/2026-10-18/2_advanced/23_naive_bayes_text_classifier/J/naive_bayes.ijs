training_counts =: 4 : 0
    'sequences labels' =. y
    documents =. ClassCount$0
    occurrences =. containing =. (ClassCount,x)$0
    for_index. i.#sequences do.
        label =. index{labels
        documents =. (1+label{documents)label}documents
        sequence =. index{::sequences
        for_term. sequence do. occurrences =. (1+(<label,term){occurrences)(<label,term)}occurrences end.
        for_term. ~.sequence do. containing =. (1+(<label,term){containing)(<label,term)}containing end.
    end.
    totals =. +/"1 occurrences
    termtotals =. +/occurrences
    (<#sequences),(<documents),(<occurrences),(<containing),(<totals),(<termtotals),(<+/totals),<x
)
smoothed_log =: 3 : 0
    'count total alpha outcomes' =. y
    numerator =. (100*count)+alpha
    denominator =. (100*total)+alpha*outcomes
    ^.numerator%denominator
)
train_nb =: 4 : 0
    'counts alpha' =. y
    'totaldocs documents occurrences containing totals termtotals total size' =. counts
    priors =. ^.documents%totaldocs
    base =. ClassCount$0.0
    weights =. (ClassCount,size)$0.0
    for_label. i.ClassCount do.
        for_term. i.size do.
            if. x=0 do.
                value =. smoothed_log ((<label,term){occurrences),(label{totals),alpha,size
            elseif. x=1 do.
                present =. smoothed_log ((<label,term){containing),(label{documents),alpha,2
                absent =. smoothed_log ((label{documents)-(<label,term){containing),(label{documents),alpha,2
                base =. ((label{base)+absent)label}base
                value =. present-absent
            else.
                value =. -smoothed_log ((term{termtotals)-(<label,term){occurrences),(total-label{totals),alpha,size
            end.
            weights =. value (<label,term)}weights
        end.
    end.
    (<x),(<priors),(<base),<weights
)
posterior =: 3 : 0
    ranking =. /:(-y),.i.#y
    label =. 0{ranking
    runner =. 1{ranking
    best =. label{y
    exponentials =. ^y-best
    normalizer =. sequential_sum exponentials
    probabilities =. exponentials%normalizer
    margin =. best-runner{y
    (<label),(<label{probabilities),(<ranking),(<y),(<probabilities),(<normalizer),(<margin),<runner
)
predict_nb =: 4 : 0
    'kind priors base weights' =. x
    terms =. y
    if. kind=1 do. terms =. ~.terms end.
    scores =. 0$0.0
    for_label. i.ClassCount do.
        value =. label{base
        for_term. terms do. value =. value+(<label,term){weights end.
        scores =. scores,value+label{priors
    end.
    posterior scores
)
