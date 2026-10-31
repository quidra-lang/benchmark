adjust_model =: 4 : 0
    model =. y
    count =. #model
    shared =. 3$0.0
    if. x-:'TIED' do.
        for_column. i.3 do.
            total =. 0.0
            for_component. model do.
                total =. total+(0{component)*(column+3){component
            end.
            shared =. total column}shared
        end.
    end.
    for_k. i.count do.
        row =. k{model
        if. x-:'DIAG' do.
            row =. 0.0 4}row
        elseif. x-:'SPHERICAL' do.
            variance =. ((3{row)+5{row)%2.0
            row =. (variance,0.0,variance)3 4 5}row
        elseif. x-:'TIED' do.
            row =. shared 3 4 5}row
        end.
        model =. row k}model
    end.
    model
)
expectation =: 4 : 0
    model =. y
    records =. (0,#model)$0.0
    densities =. i.0
    loglik =. 0.0
    for_point. x do.
        scores =. i.0
        for_component. model do.
            scores =. scores,point weighted_log_density component
        end.
        maximum =. >./scores
        row =. ^scores-maximum
        total =. 0.0
        for_value. row do.
            total =. total+value
        end.
        density =. maximum+^.total
        records =. records,row%total
        densities =. densities,density
        loglik =. loglik+density
    end.
    (<records),(<densities),<loglik
)
maximization =: 4 : 0
    points =. x
    'records kind epsilon' =. y
    count =. 1{$records
    sample_size =. #points
    model =. 0 6$0.0
    counts =. i.0
    scatter =. 0 3$0.0
    for_k. i.count do.
        nk =. 0.0
        sx =. 0.0
        sy =. 0.0
        for_i. i.sample_size do.
            r =. (<i,k){records
            nk =. nk+r
            sx =. sx+r*(<i,0){points
            sy =. sy+r*(<i,1){points
        end.
        mx =. sx%nk
        my =. sy%nk
        counts =. counts,nk
        model =. model,(nk%sample_size),mx,my,0.0,0.0,0.0
        a =. 0.0
        b =. 0.0
        c =. 0.0
        for_i. i.sample_size do.
            'dx dy' =. (i{points)-mx,my
            r =. (<i,k){records
            a =. a+(r*dx)*dx
            b =. b+(r*dx)*dy
            c =. c+(r*dy)*dy
        end.
        scatter =. scatter,a,b,c
    end.
    if. kind-:'TIED' do.
        shared =. 3$0.0
        for_column. i.3 do.
            total =. 0.0
            for_row. scatter do.
                total =. total+column{row
            end.
            shared =. (total%sample_size)column}shared
        end.
        shared =. shared+epsilon,0.0,epsilon
        for_k. i.count do.
            row =. shared 3 4 5}k{model
            model =. row k}model
        end.
    else.
        for_k. i.count do.
            'a b c' =. (k{scatter)%k{counts
            a =. a+epsilon
            c =. c+epsilon
            if. kind-:'DIAG' do.
                b =. 0.0
            elseif. kind-:'SPHERICAL' do.
                variance =. ((((<k,0){scatter)%k{counts)+((<k,2){scatter)%k{counts)%2.0
                a =. variance+epsilon
                b =. 0.0
                c =. variance+epsilon
            end.
            row =. (a,b,c)3 4 5}k{model
            model =. row k}model
        end.
    end.
    model
)
run_em =: 3 : 0
    'points initial kind iterations epsilon' =. y
    model =. kind adjust_model initial
    'records densities loglik' =. points expectation model
    trace =. ,loglik
    for_iteration. i.iterations do.
        model =. points maximization (<records),(<kind),<epsilon
        'records densities loglik' =. points expectation model
        trace =. trace,loglik
    end.
    (<model),(<records),(<densities),<trace
)
