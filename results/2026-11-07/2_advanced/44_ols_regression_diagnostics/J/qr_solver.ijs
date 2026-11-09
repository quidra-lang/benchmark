ordered_sum =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
f_matrix =: 0&{::
f_response =: 1&{::
f_weights =: 2&{::
f_n =: 3&{::
f_p =: 4&{::
f_rank =: 5&{::
f_accepted =: 6&{::
f_aliases =: 7&{::
f_triangular =: 8&{::
f_effects =: 9&{::
f_beta =: 10&{::
f_inverse =: 11&{::
f_variance =: 12&{::
f_u =: 13&{::
f_g =: 14&{::
f_leverage =: 15&{::
f_fitted =: 16&{::
f_residual =: 17&{::
f_weighted_residual =: 18&{::
f_rss =: 19&{::
qr_fit =: 3 : 0
    'matrix response weights tolerance' =. y
    n =. #matrix
    p =. 1{$matrix
    roots =. %:weights
    weighted =. matrix
    for_i. i.n do.
        weighted =. ((i{matrix)*i{roots)i}weighted
    end.
    work =. weighted
    transformed =. roots*response
    lengths =. p$0.0
    for_j. i.p do.
        column =. j{"1 weighted
        lengths =. (%:ordered_sum column*column)j}lengths
    end.
    triangular =. (p,p)$0.0
    accepted =. i.0
    aliases =. i.0
    for_j. i.p do.
        k =. #accepted
        column =. k}.j{"1 work
        eta =. %:ordered_sum column*column
        if. eta<:tolerance*j{lengths do.
            aliases =. aliases,j
            continue.
        end.
        accepted =. accepted,j
        if. ((<k,j){work)>:0 do.
            alpha =. -eta
        else.
            alpha =. eta
        end.
        vector =. k}.j{"1 work
        vector =. ((0{vector)-alpha)0}vector
        squared =. ordered_sum vector*vector
        for_l. i.k do.
            triangular =. ((<l,j){work)(<l,k)}triangular
        end.
        triangular =. alpha (<k,k)}triangular
        for_l. (j+1)+i.p-j+1 do.
            dot =. ordered_sum vector*k}.l{"1 work
            delta =. (2.0*dot)%squared
            for_i. k+i.n-k do.
                work =. (((<i,l){work)-delta*(i-k){vector)(<i,l)}work
            end.
        end.
        dot =. ordered_sum vector*k}.transformed
        delta =. (2.0*dot)%squared
        for_i. k+i.n-k do.
            transformed =. ((i{transformed)-delta*(i-k){vector)i}transformed
        end.
    end.
    rank =. #accepted
    effects =. rank{.transformed
    beta =. p$0.0
    triangular =. (rank,rank){.triangular
    for_k. |.i.rank do.
        tail =. 0.0
        for_l. (k+1)+i.rank-k+1 do.
            tail =. tail+((<k,l){triangular)*(l{accepted){beta
        end.
        beta =. (((k{effects)-tail)%(<k,k){triangular)(k{accepted)}beta
    end.
    inverse =. (rank,rank)$0.0
    for_m. i.rank do.
        for_l. |.i.rank do.
            tail =. 0.0
            for_q. (l+1)+i.rank-l+1 do.
                tail =. tail+((<l,q){triangular)*(<q,m){inverse
            end.
            value =. ((0.0+l=m)-tail)%(<l,l){triangular
            inverse =. value (<l,m)}inverse
        end.
    end.
    variance =. rank$0.0
    for_k. i.rank do.
        row =. k{inverse
        variance =. (ordered_sum row*row)k}variance
    end.
    u =. (n,rank)$0.0
    g =. (n,rank)$0.0
    leverage =. n$0.0
    fitted =. n$0.0
    residual =. n$0.0
    weighted_residual =. n$0.0
    rss =. 0.0
    for_i. i.n do.
        h =. 0.0
        for_k. i.rank do.
            sum =. 0.0
            for_m. i.rank do.
                sum =. sum+((<i,(m{accepted)){weighted)*(<m,k){inverse
            end.
            u =. sum (<i,k)}u
            h =. h+sum*sum
        end.
        leverage =. h i}leverage
        for_k. i.rank do.
            sum =. 0.0
            for_m. i.rank do.
                sum =. sum+((<k,m){inverse)*(<i,m){u
            end.
            g =. sum (<i,k)}g
        end.
        value =. 0.0
        for_k. i.rank do.
            value =. value+((<i,(k{accepted)){matrix)*(k{accepted){beta
        end.
        fitted =. value i}fitted
        difference =. (i{response)-value
        residual =. difference i}residual
        weighted_difference =. (i{roots)*difference
        weighted_residual =. weighted_difference i}weighted_residual
        rss =. rss+weighted_difference*weighted_difference
    end.
    (<matrix),(<response),(<weights),(<n),(<p),(<rank),(<accepted),(<aliases),(<triangular),(<effects),(<beta),(<inverse),(<variance),(<u),(<g),(<leverage),(<fitted),(<residual),(<weighted_residual),<rss
)
