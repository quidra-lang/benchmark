p_means =: 0&{::
p_deviations =: 1&{::
p_scales =: 2&{::
p_covariance =: 3&{::
p_correlation =: 4&{::
p_values =: 5&{::
p_standardized =: 6&{::
standardize =: 3 : 0
    'rows means scales' =. y
    result =. rows
    for_i. i.#rows do.
        for_j. i.#means do.
            result =. ((((<i,j){rows)-j{means)%j{scales)(<i,j)}result
        end.
    end.
    result
)
prepare_pca =: 3 : 0
    'rows scaling' =. y
    n =. #rows
    size =. 1{$rows
    means =. size$0.0
    for_j. i.size do.
        total =. 0.0
        for_i. i.n do.
            total =. total+(<i,j){rows
        end.
        means =. (total%n)j}means
    end.
    covariance =. (size,size)$0.0
    for_j. i.size do.
        for_k. j+i.size-j do.
            total =. 0.0
            for_i. i.n do.
                total =. total+(((<i,j){rows)-j{means)*((<i,k){rows)-k{means
            end.
            value =. total%(n-1)
            covariance =. value (<j,k)}covariance
            covariance =. value (<k,j)}covariance
        end.
    end.
    deviations =. i.0
    for_j. i.size do.
        deviations =. deviations,%:(<j,j){covariance
    end.
    correlation =. (size,size)$0.0
    for_j. i.size do.
        for_k. i.size do.
            if. j=k do.
                value =. 1.0
            else.
                value =. ((<j,k){covariance)%((j{deviations)*k{deviations)
            end.
            correlation =. value (<j,k)}correlation
        end.
    end.
    if. scaling-:'covariance' do.
        values =. covariance
        scales =. size$1.0
    else.
        values =. correlation
        scales =. deviations
    end.
    standardized =. standardize (<rows),(<means),<scales
    (<means),(<deviations),(<scales),(<covariance),(<correlation),(<values),<standardized
)
standardize_supplementary =: 3 : 0
    'rows means scales' =. y
    result =. ($rows)$0.0
    for_i. i.#rows do.
        for_j. i.#means do.
            text =. (<i,j){::rows
            if. text-:'NA' do.
                value =. 0.0
            else.
                value =. ((decimal text)-j{means)%j{scales
            end.
            result =. value (<i,j)}result
        end.
    end.
    result
)
pca_scores =: 4 : 0
    result =. ((#x),#y)$0.0
    for_i. i.#x do.
        for_k. i.#y do.
            result =. ((i{x)dot k{y)(<i,k)}result
        end.
    end.
    result
)
pca_residual =: 3 : 0
    'row scores vectors count' =. y
    result =. (#row)$0.0
    for_j. i.#row do.
        reconstructed =. 0.0
        for_k. i.count do.
            reconstructed =. reconstructed+(k{scores)*(<k,j){vectors
        end.
        result =. ((j{row)-reconstructed)j}result
    end.
    result
)
pca_t2 =: 3 : 0
    'scores eigenvalues count' =. y
    result =. 0.0
    for_k. i.count do.
        value =. k{scores
        result =. result+(value*value)%k{eigenvalues
    end.
    result
)
