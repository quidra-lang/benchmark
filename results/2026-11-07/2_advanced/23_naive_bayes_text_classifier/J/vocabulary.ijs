chi_square =: 3 : 0
    'present frequency classsize total' =. y
    b =. frequency-present
    c =. classsize-present
    e =. (total-classsize)-b
    difference =. (present*e)-b*c
    numerator =. (total*difference)*difference
    denominator =. ((frequency*(total-frequency))*classsize)*(total-classsize)
    if. denominator=0 do. 0.0 else. numerator%denominator end.
)
build_vocabulary =: 4 : 0
    'sequences labels' =. y
    allterms =. ascii_sorted ~.;sequences
    counts =. ((#allterms),ClassCount)$0
    classsizes =. ClassCount$0
    for_index. i.#sequences do.
        label =. index{labels
        classsizes =. (1+label{classsizes)label}classsizes
        for_term. ~.index{::sequences do.
            position =. allterms i.term
            counts =. (1+(<position,label){counts)(<position,label)}counts
        end.
    end.
    ranked =. 0$a:
    scores =. 0$0.0
    for_index. i.#allterms do.
        frequency =. +/index{counts
        if. frequency<MinimumDf do. continue. end.
        bestclass =. 0
        best =. chi_square ((<index,0){counts),frequency,(0{classsizes),#sequences
        for_label. 1+i.ClassCount-1 do.
            value =. chi_square ((<index,label){counts),frequency,(label{classsizes),#sequences
            if. value>best do. best =. value
                bestclass =. label end.
        end.
        ranked =. ranked,< (index{allterms),(<frequency),(<best),<bestclass
        scores =. scores,best
    end.
    candidatecount =. #ranked
    order =. /:(-scores),.i.#ranked
    ranked =. order{ranked
    if. (x>0)*.x<#ranked do. ranked =. x{.ranked end.
    selected =. 0$a:
    for_term. ranked do. selected =. selected,0{>term end.
    terms =. ascii_sorted selected
    frequencies =. 0$0
    for_term. terms do.
        position =. allterms i.term
        frequencies =. frequencies,+/position{counts
    end.
    (<#allterms),(<candidatecount),(<ranked),(<terms),<frequencies
)
encode_terms =: 4 : 0
    terms =. 3{::x
    positions =. terms i.y
    positions#~positions<#terms
)
