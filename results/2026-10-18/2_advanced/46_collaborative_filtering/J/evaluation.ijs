clip =: 3 : '1.0>.5.0<.y'
rmse =: 3 : 0
    total =. 0.0
    for_error. y do.
        total =. total+error*error
    end.
    %:total%#y
)
mae =: 3 : 0
    total =. 0.0
    for_error. y do.
        total =. total+|error
    end.
    total%#y
)
rank_weight =: 3 : '1.0%2^.y+1'
ranking_metric =: 3 : 0
    'list relevant relevant_count count' =. y
    hits =. 0
    dcg =. 0.0
    ap =. 0.0
    reciprocal =. 0.0
    for_index. i.count do.
        rank =. index+1
        if. (index{list){relevant do.
            hits =. hits+1
            dcg =. dcg+rank_weight rank
            ap =. ap+hits%rank
            if. reciprocal=0 do.
                reciprocal =. 1.0%rank
            end.
        end.
    end.
    denominator =. count<.relevant_count
    ideal =. 0.0
    for_rank. 1+i.denominator do.
        ideal =. ideal+rank_weight rank
    end.
    (<hits),(<hits%relevant_count),(<dcg%ideal),(<ap%denominator),<reciprocal
)
