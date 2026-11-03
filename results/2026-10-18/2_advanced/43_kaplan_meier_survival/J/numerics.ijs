Z95 =: 1.959963984540054
fraction =: 4 : '(0.0+x)%0.0+y'
ordered_sum =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
solve =: 3 : 0
    'a b' =. y
    size =. #b
    for_k. i.size do.
        for_i. (k+1)+i.size-k+1 do.
            factor =. ((<i,k){a)%(<k,k){a
            for_j. k+i.size-k do.
                value =. ((<i,j){a)-factor*(<k,j){a
                a =. value (<i,j)}a
            end.
            b =. ((i{b)-factor*k{b)i}b
        end.
    end.
    solution =. size$0.0
    for_i. |.i.size do.
        value =. i{b
        for_j. (i+1)+i.size-i+1 do.
            value =. value-((<i,j){a)*j{solution
        end.
        solution =. (value%(<i,i){a)i}solution
    end.
    solution
)
inverse =: 3 : 0
    size =. #y
    result =. (size,size)$0.0
    for_column. i.size do.
        unit =. 1.0 column}(size$0.0)
        solution =. solve (<y),<unit
        for_row. i.size do.
            result =. (row{solution)(<row,column)}result
        end.
    end.
    result
)
log_gamma =: 3 : 0
    a =. y
    coefficients =. 76.18009172947146 _86.50532032941677 24.01409824083091 _1.231739572450155 0.001208650973866179 _0.000005395239384953
    xi =. a+5.5
    xi =. xi-(a+0.5)*^.xi
    sigma =. 1.000000000190015
    value =. a
    for_coefficient. coefficients do.
        value =. value+1.0
        sigma =. sigma+coefficient%value
    end.
    (-xi)+^.(2.5066282746310005*sigma)%a
)
gamma_q =: 3 : 0
    'a x' =. y
    if. x=0.0 do.
        1.0 return.
    end.
    prefactor =. ^((-x)+(a*^.x))-log_gamma a
    if. x<a+1.0 do.
        alpha =. a
        term =. 1.0%a
        sigma =. term
        for_index. i.1000 do.
            alpha =. alpha+1.0
            term =. term*x%alpha
            sigma =. sigma+term
            if. (|term)<(|sigma)*1e_15 do.
                break.
            end.
        end.
        1.0-sigma*prefactor return.
    end.
    epsilon =. 1e_300
    b =. (x+1.0)-a
    c =. 1.0%epsilon
    d =. 1.0%b
    h =. d
    for_i. 1+i.1000 do.
        an =. (-i)*(i-a)
        b =. b+2.0
        d =. (an*d)+b
        if. (|d)<epsilon do.
            d =. epsilon
        end.
        c =. b+an%c
        if. (|c)<epsilon do.
            c =. epsilon
        end.
        d =. 1.0%d
        delta =. d*c
        h =. h*delta
        if. (|delta-1.0)<1e_15 do.
            break.
        end.
    end.
    prefactor*h
)
chi_p =: 4 : 'gamma_q (y%2.0),x%2.0'
