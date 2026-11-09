identity =: 3 : '=i.y'
copy_matrix =: ]
column =: 4 : 'y{"1 x'
dot =: 4 : 0
    result =. 0.0
    for_index. i.#x do.
        result =. result+(index{x)*index{y
    end.
    result
)
product =: 4 : 0
    result =. i.0
    for_row. x do.
        result =. result,row dot y
    end.
    result
)
vlength =: 3 : '%:y dot y'
normalize =: 3 : 'y%vlength y'
orient =: 3 : 0
    largest =. 0
    for_index. 1+i.(#y)-1 do.
        if. (|index{y)>|largest{y do.
            largest =. index
        end.
    end.
    if. (largest{y)<0 do.
        -y
    else.
        y
    end.
)
maximum_difference =: 4 : '>./|x-y'
deflate =: 3 : 0
    'values eigenvalue vector' =. y
    result =. copy_matrix values
    for_i. i.#values do.
        for_j. i.#values do.
            value =. ((<i,j){values)-((eigenvalue*i{vector)*j{vector)
            result =. value (<i,j)}result
        end.
    end.
    result
)
inverse_determinant =: 3 : 0
    size =. #y
    work =. y,.identity size
    determinant =. 1.0
    for_k. i.size do.
        pivot =. (<k,k){work
        determinant =. determinant*pivot
        for_h. i.2*size do.
            work =. (((<k,h){work)%pivot)(<k,h)}work
        end.
        for_i. i.size do.
            if. i=k do.
                continue.
            end.
            factor =. (<i,k){work
            for_h. i.2*size do.
                work =. (((<i,h){work)-factor*(<k,h){work)(<i,h)}work
            end.
        end.
    end.
    inverse =. size}."1 work
    (<inverse),<determinant
)
