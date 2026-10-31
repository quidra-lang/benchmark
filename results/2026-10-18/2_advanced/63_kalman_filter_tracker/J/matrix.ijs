m_total =: 3 : 0
    total =. 0.0
    for_value. y do. total =. total+value end.
    total
)
m_identity =: 3 : 0
    matrix =. (y,y)$0.0
    for_i. i.y do. matrix =. 1.0(<i,i)}matrix end.
    matrix
)
m_diagonal =: 3 : 0
    matrix =. ((#y),#y)$0.0
    for_i. i.#y do. matrix =. (i{y)(<i,i)}matrix end.
    matrix
)
m_transpose =: 3 : '|:y'
m_product =: 4 : 0
    result =. ((#x),{:$y)$0.0
    for_i. i.#x do.
        for_j. i.{:$y do.
            value =. 0.0
            for_k. i.{:$x do. value =. value+((<i,k){x)*(<k,j){y end.
            result =. value(<i,j)}result
        end.
    end.
    result
)
m_vector =: 4 : 0
    result =. i.0
    for_row. x do.
        value =. 0.0
        for_j. i.#y do. value =. value+(j{row)*j{y end.
        result =. result,value
    end.
    result
)
m_inverse =: 3 : 0
    n =. #y
    augmented =. y,.m_identity n
    for_column. i.n do.
        pivot =. (<column,column){augmented
        augmented =. ((column{augmented)%pivot)column}augmented
        for_row. i.n do.
            if. row~:column do.
                factor =. (<row,column){augmented
                value =. (row{augmented)-factor*column{augmented
                augmented =. value row}augmented
            end.
        end.
    end.
    (n+i.n){"1 augmented
)
m_determinant2 =: 3 : '(((<0,0){y)*((<1,1){y))-((<0,1){y)*(<1,0){y'
m_quadratic2 =: 4 : 0
    'a b' =. x
    first =. (((<0,0){y)*a)+((<0,1){y)*b
    second =. (((<1,0){y)*a)+((<1,1){y)*b
    (a*first)+b*second
)
