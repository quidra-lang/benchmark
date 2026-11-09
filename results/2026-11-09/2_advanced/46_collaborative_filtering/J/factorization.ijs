random_draw =: 3 : 0
    FactorState =: 2147483647x|48271x*FactorState
    FactorState
)
initial_factor =: 3 : '(0.0+((2001x|random_draw 0)-1000x))%10000.0'
initial_factors =: 3 : 0
    values =. (y,FactorCount)$0.0
    for_row. i.y do.
        for_factor. i.FactorCount do.
            values =. (initial_factor 0)(<row,factor)}values
        end.
    end.
    values
)
factor_dot =: 4 : 0
    result =. 0.0
    for_f. i.#x do.
        result =. result+(f{x)*f{y
    end.
    result
)
latent_rmse =: 3 : 0
    'users items user_bias item_bias' =. y
    total =. 0.0
    for_row. Training do.
        'u i rating timestamp' =. row
        predicted =. ((GlobalMean+u{user_bias)+i{item_bias)+(u{users)factor_dot i{items
        difference =. rating-predicted
        total =. total+difference*difference
    end.
    %:total%#Training
)
train_svd =: 3 : 0
    FactorState =: x:Seed
    users =. initial_factors #Users
    items =. initial_factors #Items
    user_bias =. (#Users)$0.0
    item_bias =. (#Items)$0.0
    log =. i.0
    order =. i.#Training
    for_epoch. i.Epochs do.
        for_t. |.1+i.(#order)-1 do.
            value =. random_draw 0
            other =. <.0.0+(t+1)|value
            saved =. t{order
            order =. (other{order)t}order
            order =. saved other}order
        end.
        for_index. order do.
            'u i rating timestamp' =. index{Training
            predicted =. ((GlobalMean+u{user_bias)+i{item_bias)+(u{users)factor_dot i{items
            difference =. rating-predicted
            user_bias =. ((u{user_bias)+LearningRate*(difference-Regularization*u{user_bias))u}user_bias
            item_bias =. ((i{item_bias)+LearningRate*(difference-Regularization*i{item_bias))i}item_bias
            for_f. i.FactorCount do.
                a =. (<u,f){users
                b =. (<i,f){items
                users =. (a+LearningRate*((difference*b)-Regularization*a))(<u,f)}users
                items =. (b+LearningRate*((difference*a)-Regularization*b))(<i,f)}items
            end.
        end.
        log =. log,latent_rmse (<users),(<items),(<user_bias),<item_bias
    end.
    (<users),(<items),(<user_bias),(<item_bias),<log
)
solve_cholesky =: 3 : 0
    'a w' =. y
    size =. #w
    lower =. (size,size)$0.0
    for_row. i.size do.
        for_column. i.row+1 do.
            total =. 0.0
            for_t. i.column do.
                total =. total+((<row,t){lower)*(<column,t){lower
            end.
            value =. ((<row,column){a)-total
            if. row=column do.
                value =. %:value
            else.
                value =. value%(<column,column){lower
            end.
            lower =. value (<row,column)}lower
        end.
    end.
    z =. size$0.0
    x =. size$0.0
    for_row. i.size do.
        total =. 0.0
        for_t. i.row do.
            total =. total+((<row,t){lower)*t{z
        end.
        z =. (((row{w)-total)%(<row,row){lower)row}z
    end.
    for_row. |.i.size do.
        total =. 0.0
        for_t. (row+1)+i.size-row+1 do.
            total =. total+((<t,row){lower)*t{x
        end.
        x =. (((row{z)-total)%(<row,row){lower)row}x
    end.
    x
)
train_als =: 3 : 0
    'user_bias item_bias' =. y
    FactorState =: x:Seed
    items =. initial_factors #Items
    users =. ((#Users),FactorCount)$0.0
    log =. i.0
    for_iteration. i.AlsIterations do.
        for_u. i.#Users do.
            a =. (FactorCount,FactorCount)$0.0
            w =. FactorCount$0.0
            for_i. u{::UserRatings do.
                vector =. i{items
                z =. ((<u,i){RatingValues)-((GlobalMean+u{user_bias)+i{item_bias)
                for_first. i.FactorCount do.
                    w =. ((first{w)+z*first{vector)first}w
                    for_second. i.FactorCount do.
                        value =. ((<first,second){a)+(first{vector)*second{vector
                        a =. value (<first,second)}a
                    end.
                end.
            end.
            for_first. i.FactorCount do.
                a =. (((<first,first){a)+AlsReg*u{UserCounts)(<first,first)}a
            end.
            users =. (solve_cholesky (<a),<w)u}users
        end.
        for_i. i.#Items do.
            a =. (FactorCount,FactorCount)$0.0
            w =. FactorCount$0.0
            for_u. i{::ItemRatings do.
                vector =. u{users
                z =. ((<u,i){RatingValues)-((GlobalMean+u{user_bias)+i{item_bias)
                for_first. i.FactorCount do.
                    w =. ((first{w)+z*first{vector)first}w
                    for_second. i.FactorCount do.
                        value =. ((<first,second){a)+(first{vector)*second{vector
                        a =. value (<first,second)}a
                    end.
                end.
            end.
            for_first. i.FactorCount do.
                a =. (((<first,first){a)+AlsReg*i{ItemCounts)(<first,first)}a
            end.
            items =. (solve_cholesky (<a),<w)i}items
        end.
        log =. log,latent_rmse (<users),(<items),(<user_bias),<item_bias
    end.
    (<users),(<items),(<user_bias),(<item_bias),<log
)
