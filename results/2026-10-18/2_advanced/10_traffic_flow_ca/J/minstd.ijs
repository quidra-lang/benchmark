minstd_step =: 3 : '2147483647|48271*y'
draw =: 3 : 'RngState =: minstd_step RngState'
select_weighted =: 4 : 0
    q =. (+/x)|y
    total =. 0
    for_index. i.#x do.
        total =. total+index{x
        if. q<total do. index return. end.
    end.
)
