median =: 3 : 0
    ordered =. /:~y
    middle =. <.-:#ordered
    if. 2|#ordered do.
        middle{ordered
    else.
        (((middle-1){ordered)+middle{ordered)%2
    end.
)
cholesky =: 3 : 0
    size =. #y
    lower =. (size,size)$0.0
    for_row. i.size do.
        for_column. i.row+1 do.
            sigma =. (<row,column){y
            for_k. i.column do.
                sigma =. sigma-((<row,k){lower)*(<column,k){lower
            end.
            if. row=column do.
                value =. %:sigma
            else.
                value =. sigma%(<column,column){lower
            end.
            lower =. value (<row,column)}lower
        end.
    end.
    lower
)
cholesky_solve =: 4 : 0
    size =. #y
    intermediate =. size$0.0
    solution =. size$0.0
    for_row. i.size do.
        value =. row{y
        for_k. i.row do.
            value =. value-((<row,k){x)*k{intermediate
        end.
        intermediate =. (value%(<row,row){x)row}intermediate
    end.
    for_row. |.i.size do.
        value =. row{intermediate
        for_k. (row+1)+i.(size-(row+1)) do.
            value =. value-((<k,row){x)*k{solution
        end.
        solution =. (value%(<row,row){x)row}solution
    end.
    solution
)
loess_local =: 4 : 0
    'positions values span degree rho' =. 5{.x
    count =. #positions
    q =. <.(span*count)%100
    order =. /:|positions-y
    selected =. /:~q{.order
    distance =. >./|(selected{positions)-y
    size =. degree+1
    matrix =. (size,size)$0.0
    right =. size$0.0
    rows =. 0$a:
    local_weights =. i.0
    for_index. selected do.
        a =. (|(index{positions)-y)%distance
        s =. 1-(a*a)*a
        weight =. ((s*s)*s)*index{rho
        delta =. ((index{positions)%100)-y%100
        basis =. 1.0,delta
        if. degree=2 do.
            basis =. basis,delta*delta
        end.
        rows =. rows,<basis
        local_weights =. local_weights,weight
        for_row. i.size do.
            value =. (row{right)+((weight*row{basis)*index{values)
            right =. value row}right
            for_column. i.size do.
                value =. ((<row,column){matrix)+((weight*row{basis)*column{basis)
                matrix =. value (<row,column)}matrix
            end.
        end.
    end.
    lower =. cholesky matrix
    beta =. lower cholesky_solve right
    unit =. 1 0}size$0.0
    zeta =. lower cholesky_solve unit
    weights =. count$0.0
    for_offset. i.q do.
        sum =. ordered_sum zeta*offset{::rows
        weights =. ((offset{local_weights)*sum)(offset{selected)}weights
    end.
    (<0{beta),(<0{zeta),<weights
)
loess_fit =: 3 : 0
    'positions values span degree iterations diagnostics' =. y
    rho =. (#positions)$1.0
    model =. (<positions),(<values),(<span),(<degree),<rho
    fitted =. i.0
    leverage =. i.0
    records =. 0 4$0.0
    if. diagnostics do.
        fits =. 0$a:
        for_position. positions do.
            fits =. fits,<model loess_local position
        end.
        for_iteration. 1+i.iterations do.
            estimates =. 0&{::&>fits
            residuals =. values-estimates
            scale =. median |residuals
            for_index. i.#rho do.
                u =. (index{residuals)%6*scale
                v =. 1-u*u
                weight =. 0.0
                if. (|u)<1 do.
                    weight =. v*v
                end.
                rho =. weight index}rho
            end.
            model =. (<rho)4}model
            updated =. 0$a:
            for_position. positions do.
                updated =. updated,<model loess_local position
            end.
            change =. >./|(0&{::&>updated)-estimates
            records =. records,iteration,scale,(+/0=rho),change
            fits =. updated
        end.
        fitted =. 0&{::&>fits
        leverage =. rho*1&{::&>fits
    end.
    model,(<fitted),(<leverage),(<ordered_sum leverage),<records
)
