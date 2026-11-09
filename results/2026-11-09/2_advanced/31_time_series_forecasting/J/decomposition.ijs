total =: 3 : 0
    result =. 0.0
    for_value. y do.
        result =. result+value
    end.
    result
)
mean =: 3 : '(total y)%#y'
sample_variance =: 3 : '(total *:y-mean y)%<:#y'
d_trend =: 0&{::
d_additive =: 1&{::
d_multiplicative =: 2&{::
d_residual_add =: 3&{::
d_residual_mult =: 4&{::
d_defined =: 5&{::
decompose =: 4 : 0
    season =. x
    count =. #y
    half =. season intdiv 2
    defined =. half+i.count-season
    trend =. count$0.0
    for_t. defined do.
        value =. 0.5*(t-half){y
        for_i. ((t-half)+1)+i.(season-1) do.
            value =. value+i{y
        end.
        value =. value+0.5*(t+half){y
        trend =. (value%season)t}trend
    end.
    additive =. multiplicative =. i.0
    for_position. i.season do.
        times =. defined#~position=season|defined
        additive =. additive,mean (times{y)-times{trend
        multiplicative =. multiplicative,mean (times{y)%times{trend
    end.
    additive =. additive-(total additive)%season
    multiplicative =. multiplicative%((total multiplicative)%season)
    residual_add =. residual_mult =. count$0.0
    for_t. defined do.
        position =. season|t
        residual_add =. (((t{y)-t{trend)-position{additive)t}residual_add
        residual_mult =. ((t{y)%((t{trend)*position{multiplicative))t}residual_mult
    end.
    (<trend),(<additive),(<multiplicative),(<residual_add),(<residual_mult),<defined
)
least_squares_line =: 3 : 0
    center =. (1+#y)%2.0
    average =. mean y
    numerator =. denominator =. 0.0
    for_t. i.#y do.
        position =. (t+1)-center
        numerator =. numerator+position*((t{y)-average)
        denominator =. denominator+position*position
    end.
    slope =. numerator%denominator
    (average-slope*center),slope
)
