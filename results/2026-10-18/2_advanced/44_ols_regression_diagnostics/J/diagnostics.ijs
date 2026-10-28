r_standardized =: 0&{::
r_studentized =: 1&{::
r_cooks =: 2&{::
r_dffits =: 3&{::
r_flags =: 4&{::
r_dfbetas =: 5&{::
a_rows =: 0&{::
a_dw =: 1&{::
a_bp =: 2&{::
a_jb =: 3&{::
row_diagnostics =: 3 : 0
    'fitted params' =. y
    n =. f_n fitted
    rank =. f_rank fitted
    degrees =. n-rank
    sigma =. %:(f_rss fitted)%degrees
    leverage_limit =. ((3{params)*rank)%n
    cook_limit =. (5{params)%n
    dffits_limit =. (6{params)*%:rank%n
    rows =. 0$a:
    for_i. i.n do.
        h =. i{f_leverage fitted
        residual =. i{f_weighted_residual fitted
        z =. residual%(sigma*%:1.0-h)
        studentized =. z*%:(degrees-1)%(degrees-z*z)
        cooks =. ((z*z)*h)%(rank*(1.0-h))
        dffits =. studentized*%:h%(1.0-h)
        flags =. ''
        if. h>leverage_limit do.
            flags =. flags,'H'
        end.
        if. (|studentized)>4{params do.
            flags =. flags,'O'
        end.
        if. cooks>cook_limit do.
            flags =. flags,'C'
        end.
        if. (|dffits)>dffits_limit do.
            flags =. flags,'F'
        end.
        if. 0=#flags do.
            flags =. '-'
        end.
        deleted_sigma =. sigma*%:(degrees-z*z)%(degrees-1)
        dfbetas =. i.0
        for_k. i.rank do.
            value =. (((<i,k){f_g fitted)*residual)%(1.0-h)
            value =. value%(deleted_sigma*%:k{f_variance fitted)
            dfbetas =. dfbetas,value
        end.
        rows =. rows,<(<z),(<studentized),(<cooks),(<dffits),(<flags),<dfbetas
    end.
    rows
)
durbin_watson =: 3 : 0
    residuals =. f_weighted_residual y
    numerator =. 0.0
    for_i. 1+i.(#residuals)-1 do.
        difference =. (i{residuals)-(i-1){residuals
        numerator =. numerator+difference*difference
    end.
    numerator%f_rss y
)
breusch_pagan =: 3 : 0
    'fitted tolerance' =. y
    squared =. *:f_weighted_residual fitted
    matrix =. (f_accepted fitted){"1 f_matrix fitted
    auxiliary =. qr_fit (<matrix),(<squared),(<(f_n fitted)$1.0),<tolerance
    mean =. (ordered_sum squared)%f_n fitted
    centered =. squared-mean
    tss =. ordered_sum centered*centered
    statistic =. (f_n fitted)*(1.0-(f_rss auxiliary)%tss)
    degrees =. (f_rank auxiliary)-1
    statistic,degrees,statistic chi_pvalue degrees
)
jarque_bera =: 3 : 0
    n =. f_n y
    residuals =. f_weighted_residual y
    mean =. (ordered_sum residuals)%n
    m2 =. 0.0
    m3 =. 0.0
    m4 =. 0.0
    for_value. residuals-mean do.
        m2 =. m2+value*value
        m3 =. m3+(value*value)*value
        m4 =. m4+((value*value)*value)*value
    end.
    m2 =. m2%n
    m3 =. m3%n
    m4 =. m4%n
    skewness =. m3%(m2*%:m2)
    kurtosis =. m4%(m2*m2)
    statistic =. (n%6.0)*((skewness*skewness)+((kurtosis-3.0)*(kurtosis-3.0))%4.0)
    statistic,(statistic chi_pvalue 2),skewness,kurtosis
)
calculate_diagnostics =: 3 : 0
    'fitted params' =. y
    (<row_diagnostics y),(<durbin_watson fitted),(<breusch_pagan (<fitted),<0{params),<jarque_bera fitted
)
