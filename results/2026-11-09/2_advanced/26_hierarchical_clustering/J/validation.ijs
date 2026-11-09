correlation =: 4 : 0
    first_mean =. (sequential_sum x)%#x
    second_mean =. (sequential_sum y)%#y
    cross =. first_squares =. second_squares =. 0.0
    for_index. i.#x do.
        a =. (index{x)-first_mean
        b =. (index{y)-second_mean
        cross =. cross+a*b
        first_squares =. first_squares+a*a
        second_squares =. second_squares+b*b
    end.
    cross%%:first_squares*second_squares
)
contingency_table =: 4 : 0
    'first second' =. y
    table =. x$0
    for_index. i.#first do.
        cell =. <(index{first),index{second
        table =. (1+cell{table)cell}table
    end.
    table
)
pair_count =: 3 : '(y*y-1)div 2'
reduced_fraction =: 3 : 0
    'numerator denominator' =. y
    if. denominator<0 do. numerator =. -numerator
        denominator =. -denominator end.
    a =. |numerator
    b =. denominator
    while. b do. remainder =. b|a
        a =. b
        b =. remainder end.
    (numerator div a),denominator div a
)
adjusted_rand_index =: 3 : 0
    count =. +/+/y
    same =. +/pair_count ,y
    row_pairs =. +/pair_count +/"1 y
    column_pairs =. +/pair_count +/y
    total =. pair_count count
    numerator =. 2*((total*same)-row_pairs*column_pairs)
    denominator =. (total*(row_pairs+column_pairs))-2*row_pairs*column_pairs
    if. denominator=0 do. 1 1 else. reduced_fraction numerator,denominator end.
)
silhouette_values =: 4 : 0
    partition =. x
    groups =. >./partition
    sizes =. (groups+1)$0
    for_group. partition do. sizes =. (1+group{sizes)group}sizes end.
    values =. 0$0.0
    for_i. i.#partition do.
        own =. i{partition
        if. (own{sizes)=1 do. values =. values,0.0
            continue. end.
        sums =. (groups+1)$0.0
        for_j. i.#partition do.
            if. i=j do. continue. end.
            group =. j{partition
            sums =. ((group{sums)+(<i,j){y)group}sums
        end.
        inner =. (own{sums)%(own{sizes)-1
        outer =. 0.0
        found =. 0
        for_group. 1+i.groups do.
            if. group=own do. continue. end.
            value =. (group{sums)%group{sizes
            if. (-.found)+.value<outer do. outer =. value
                found =. 1 end.
        end.
        values =. values,(outer-inner)%(inner>.outer)
    end.
    values
)
