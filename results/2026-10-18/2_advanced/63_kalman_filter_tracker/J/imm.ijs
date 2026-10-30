imm_new =: 3 : 0
    first =. k_new (<'CV'),(<0{IMMNoise),<y
    second =. k_new (<'CV'),(<1{IMMNoise),<y
    models =. (<first),<second
    (<models),<IMMInitial
)
imm_step =: 3 : 0
    'record interval measurement' =. y
    'oldmodels mu' =. record
    predicted =. i.0
    for_j. i.2 do.
        value =. (((<0,j){IMMTransition)*0{mu)+((<1,j){IMMTransition)*1{mu
        predicted =. predicted,value
    end.
    firststate =. 2{::0{::oldmodels
    secondstate =. 2{::1{::oldmodels
    firstcov =. 3{::0{::oldmodels
    secondcov =. 3{::1{::oldmodels
    models =. 0$a:
    likelihoods =. i.0
    for_j. i.2 do.
        w1 =. (((<0,j){IMMTransition)*0{mu)%j{predicted
        w2 =. (((<1,j){IMMTransition)*1{mu)%j{predicted
        mixed =. (w1*firststate)+w2*secondstate
        covariance =. 4 4$0.0
        for_r. i.4 do.
            for_s. i.4 do.
                d1r =. (r{firststate)-r{mixed
                d1s =. (s{firststate)-s{mixed
                d2r =. (r{secondstate)-r{mixed
                d2s =. (s{secondstate)-s{mixed
                first =. w1*(((<r,s){firstcov)+d1r*d1s)
                second =. w2*(((<r,s){secondcov)+d2r*d2s)
                covariance =. (first+second)(<r,s)}covariance
            end.
        end.
        model =. j{::oldmodels
        model =. (<mixed)2}model
        model =. (<covariance)3}model
        model =. interval k_predict model
        likelihood =. 1.0
        if. #measurement do.
            'model d2 loglik s' =. measurement k_update model
            likelihood =. (^((-d2)%2))%((2*PI)*%:m_determinant2 s)
        end.
        models =. models,<model
        likelihoods =. likelihoods,likelihood
    end.
    products =. likelihoods*predicted
    denominator =. (0{products)+1{products
    (<models),<products%denominator
)
imm_estimate =: 3 : 0
    'models mu' =. y
    ((0{mu)*2{::0{::models)+(1{mu)*2{::1{::models
)
