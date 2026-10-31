sequential_sum =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
squared_distance =: 4 : 0
    total =. 0.0
    for_index. i.#x do.
        difference =. (index{x)-index{y
        total =. total+difference*difference
    end.
    total
)
feature_statistics =: 3 : 0
    means =. deviations =. 0$0.0
    for_feature. i.{:$y do.
        values =. feature{"1 y
        mean =. (sequential_sum values)%#y
        squares =. 0.0
        for_value. values do.
            difference =. value-mean
            squares =. squares+difference*difference
        end.
        means =. means,mean
        deviations =. deviations,%:squares%(#y)-1
    end.
    (<means),<deviations
)
standardize_vectors =: 4 : 0
    'means deviations' =. x
    rows =. (0,#means)$0.0
    for_row. y do. rows =. rows,(row-means)%deviations end.
    rows
)
vector_distance =: 4 : 0
    'first second' =. y
    if. x-:'euclidean' do. %:first squared_distance second
    elseif. x-:'manhattan' do. sequential_sum |first-second
    else.
        mean_first =. (sequential_sum first)%#first
        mean_second =. (sequential_sum second)%#second
        cross =. first_squares =. second_squares =. 0.0
        for_index. i.#first do.
            a =. (index{first)-mean_first
            b =. (index{second)-mean_second
            cross =. cross+a*b
            first_squares =. first_squares+a*a
            second_squares =. second_squares+b*b
        end.
        1-cross%%:first_squares*second_squares
    end.
)
distance_matrix =: 4 : 0
    count =. #y
    matrix =. (count,count)$0.0
    for_i. i.count do.
        for_j. (i+1)+i.count-(i+1)do.
            value =. x vector_distance (i{y),:j{y
            matrix =. value (<i,j)}matrix
            matrix =. value (<j,i)}matrix
        end.
    end.
    matrix
)
