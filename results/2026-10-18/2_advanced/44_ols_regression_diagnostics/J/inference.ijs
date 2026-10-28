log_gamma =: 3 : 0
    coefficients =. 76.18009172947146 _86.50532032941677 24.01409824083091 _1.231739572450155 0.001208650973866179 _0.000005395239384953
    t =. y+5.5
    adjustment =. t-(y+0.5)*^.t
    series =. 1.000000000190015
    for_j. i.6 do.
        series =. series+(j{coefficients)%(y+j+1)
    end.
    (-adjustment)+^.(2.5066282746310005*series)%y
)
replace_small =: 3 : 0
    if. (|y)<1e_300 do.
        1e_300
    else.
        y
    end.
)
beta_fraction =: 3 : 0
    'a b x' =. y
    c =. 1.0
    d =. 1.0%replace_small 1.0-((a+b)*x)%(a+1.0)
    h =. d
    for_m. 1+i.1000 do.
        q =. ((m*(b-m))*x)%((a-1.0)+2*m)*(a+2*m)
        d =. 1.0%replace_small 1.0+q*d
        c =. replace_small 1.0+q%c
        h =. h*(d*c)
        q =. (((-(a+m))*((a+b)+m))*x)%((a+2*m)*((a+1.0)+2*m))
        d =. 1.0%replace_small 1.0+q*d
        c =. replace_small 1.0+q%c
        delta =. d*c
        h =. h*delta
        if. (|delta-1.0)<1e_15 do.
            break.
        end.
    end.
    h
)
incomplete_beta =: 3 : 0
    'x a b' =. y
    if. x<:0 do.
        0.0 return.
    end.
    if. x>:1 do.
        1.0 return.
    end.
    value =. (log_gamma a+b)-log_gamma a
    value =. value-log_gamma b
    value =. value+a*^.x
    value =. value+b*^.1.0-x
    factor =. ^value
    if. x<(a+1.0)%((a+b)+2.0) do.
        (factor*beta_fraction a,b,x)%a
    else.
        1.0-(factor*beta_fraction b,a,1.0-x)%b
    end.
)
upper_gamma =: 3 : 0
    'a x' =. y
    if. x<:0 do.
        1.0 return.
    end.
    factor =. ^(((-x)+(a*^.x))-log_gamma a)
    if. x<a+1.0 do.
        term =. 1.0%a
        e =. a
        series =. term
        for_index. i.1000 do.
            e =. e+1.0
            term =. term*x%e
            series =. series+term
            if. (|term)<(|series)*1e_15 do.
                break.
            end.
        end.
        1.0-series*factor return.
    end.
    beta =. (x+1.0)-a
    c =. 1.0%1e_300
    d =. 1.0%beta
    h =. d
    for_i. 1+i.1000 do.
        q =. (-i)*(i-a)
        beta =. beta+2.0
        d =. 1.0%replace_small (q*d)+beta
        c =. replace_small beta+q%c
        delta =. d*c
        h =. h*delta
        if. (|delta-1.0)<1e_15 do.
            break.
        end.
    end.
    factor*h
)
t_pvalue =: 4 : 'incomplete_beta (y%(y+x*x)),(y%2.0),0.5'
f_pvalue =: 3 : 0
    'statistic first second' =. y
    incomplete_beta (second%(second+first*statistic)),(second%2.0),first%2.0
)
chi_pvalue =: 4 : 'upper_gamma (y%2.0),x%2.0'
t_quantile =: 4 : 0
    lo =. 0.0
    hi =. 1000.0
    for_index. i.100 do.
        mid =. (lo+hi)%2.0
        if. (mid t_pvalue y)>1.0-x do.
            lo =. mid
        else.
            hi =. mid
        end.
    end.
    (lo+hi)%2.0
)
significance =: 3 : 0
    if. y<0 do.
        ''
    elseif. y<0.001 do.
        '***'
    elseif. y<0.01 do.
        '**'
    elseif. y<0.05 do.
        '*'
    elseif. y<0.1 do.
        '.'
    else.
        ''
    end.
)
four =: 3 : 0
    text =. (0j4":y)-.' '
    text =. '-'(I.text='_')}text
    if. text-:'-0.0000' do.
        text =. '0.0000'
    end.
    text
)
probability =: 3 : 0
    if. y<0 do.
        'NA'
    elseif. y<0.0001 do.
        '<0.0001'
    else.
        four y
    end.
)
