minimum_matching =: 3 : 0
    'rows columns' =. $y
    if. (rows=0)+.columns=0 do. 0 2$0 return. end.
    transposed =. rows>columns
    matrix =. y
    if. transposed do. matrix =. |:matrix end.
    'rows columns' =. $matrix
    u =. (rows+1)$0.0
    v =. (columns+1)$0.0
    matched =. previous =. (columns+1)$0
    for_row. 1+i.rows do.
        matched =. row 0}matched
        column =. 0
        distances =. (columns+1)$_
        used =. (columns+1)$0
        while. 1 do.
            used =. 1 column}used
            currentrow =. column{matched
            delta =. _
            following =. 0
            for_candidate. 1+i.columns do.
                if. -.candidate{used do.
                    reduced =. (((<(currentrow-1),candidate-1){matrix)-currentrow{u)-candidate{v
                    if. reduced<candidate{distances do.
                        distances =. reduced candidate}distances
                        previous =. column candidate}previous
                    end.
                    if. (candidate{distances)<delta do.
                        delta =. candidate{distances
                        following =. candidate
                    end.
                end.
            end.
            for_candidate. i.columns+1 do.
                if. candidate{used do.
                    index =. candidate{matched
                    u =. ((index{u)+delta)index}u
                    v =. ((candidate{v)-delta)candidate}v
                else. distances =. ((candidate{distances)-delta)candidate}distances end.
            end.
            column =. following
            if. 0=column{matched do. break. end.
        end.
        while. column~:0 do.
            following =. column{previous
            matched =. (following{matched)column}matched
            column =. following
        end.
    end.
    result =. 0 2$0
    for_column. 1+i.columns do.
        row =. column{matched
        if. row>0 do.
            if. transposed do. result =. result,(column-1),row-1
            else. result =. result,(row-1),column-1 end.
        end.
    end.
    (/:result){result
)
optimal_assignment =: 4 : 0
    usable =. x
    costs =. y
    'rows columns' =. $costs
    if. (rows=0)+.(columns=0)+.-.+./,usable do. 0 2$0 return. end.
    largest =. >./(,usable)#,costs
    penalty =. ((rows<.columns)+1)*((1.0>.largest)+1.0)
    matrix =. costs
    matrix =. penalty(I.-.,usable)},matrix
    matrix =. (rows,columns)$matrix
    result =. 0 2$0
    for_pair. minimum_matching matrix do.
        if. (<pair){usable do. result =. result,pair end.
    end.
    result
)
