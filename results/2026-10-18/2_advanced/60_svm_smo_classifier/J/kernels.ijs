kernel_value =: 4 : 0
    'first second' =. y
    'name kind degree gamma coef0' =. x
    if. kind-:'rbf' do.
        'e1 e2' =. first-second
        ^-gamma*((e1*e1)+e2*e2) return.
    end.
    dot =. ((0{first)*0{second)+(1{first)*1{second
    if. kind-:'linear' do. dot return. end.
    factor =. (gamma*dot)+coef0
    value =. 1.0
    for_iteration. i.degree do. value =. value*factor end.
    value
)
kernel_description =: 3 : 0
    'name kind degree gamma coef0' =. y
    if. kind-:'linear' do. 'linear'
    elseif. kind-:'rbf' do. 'rbf gamma ',fixed gamma
    else. emit 'poly degree';degree;'gamma';(fixed gamma);'coef0';fixed coef0 end.
)
kernel_matrix =: 4 : 0
    matrix =. ((#y),#y)$0.0
    for_i. i.#y do.
        for_j. i.#y do.
            value =. x kernel_value (<i{y),<j{y
            matrix =. value(<i,j)}matrix
        end.
    end.
    matrix
)
kernel_submatrix =: 4 : 'x{"1 x{y'
