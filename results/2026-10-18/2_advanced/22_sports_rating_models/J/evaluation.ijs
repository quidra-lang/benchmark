sigma =: 3 : '1%1+^-y'
fit_link =: 4 : 0
    alpha =. beta =. 0.0
    for_iteration. i.LinkIterations do.
        g0 =. g1 =. h00 =. h01 =. h11 =. 0.0
        for_index. i.#x do.
            z =. index{x
            result =. index{y
            p =. sigma alpha+beta*z
            w =. p*1-p
            g0 =. g0+result-p
            g1 =. g1+(result-p)*z
            h00 =. h00+w
            h01 =. h01+w*z
            h11 =. h11+(w*z)*z
        end.
        determinant =. (h00*h11)-h01*h01
        alpha =. alpha+((h11*g0)-h01*g1)%determinant
        beta =. beta+((h00*g1)-h01*g0)%determinant
    end.
    alpha,beta
)
log_loss =: 4 : 0
    if. y=2 do. -^.x
    elseif. y=0 do. -^.1-x
    else. -(((^.x)%2)+(^.1-x)%2) end.
)
brier_score =: 4 : '((x-y%2)*(x-y%2))'
correctness =: 4 : 0
    if. y=1 do. 1
    elseif. ((x>0.5)*.y=2)+.(x<0.5)*.y=0 do. 2
    else. 0 end.
)
average_ranks_doubled =: 3 : 0
    result =. 0$0
    for_value. y do.
        greater =. equal =. 0
        for_other. y do.
            comparison =. other frac_compare value
            greater =. greater+comparison>0
            equal =. equal+comparison=0
        end.
        result =. result,(2*greater)+equal+1
    end.
    result
)
kendall_tau =: 4 : 0
    count =. #x
    balance =. 0
    for_t. i.count do.
        for_u. (t+1)+i.count-t+1 do.
            balance =. balance+((t{x)frac_compare u{x)*(t{y)frac_compare u{y
        end.
    end.
    denominator =. (count*(count-1))div 2
    reduced_fraction balance,denominator
)
spearman_rho =: 4 : 0
    first =. average_ranks_doubled x
    second =. average_ranks_doubled y
    squares =. +/*:first-second
    count =. #x
    denominator =. (4*count)*((count*count)-1)
    reduced_fraction (denominator-6*squares),denominator
)
