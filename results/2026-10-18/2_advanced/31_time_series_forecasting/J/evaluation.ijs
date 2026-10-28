seasonal_scale =: 4 : 0
    value =. 0.0
    for_t. x+i.(#y)-x do.
        value =. value+|(t{y)-(t-x){y
    end.
    value%(#y)-x
)
accuracy =: 3 : 0
    'actual predicted scale' =. y
    total_error =. absolute =. squared =. percentage =. symmetric =. 0.0
    for_i. i.#actual do.
        observed =. i{actual
        forecast =. i{predicted
        residual =. observed-forecast
        total_error =. total_error+residual
        absolute =. absolute+|residual
        squared =. squared+residual*residual
        percentage =. percentage+(|residual)%observed
        symmetric =. symmetric+(2.0*|residual)%(|observed)+|forecast
    end.
    count =. #actual
    mae =. absolute%count
    (total_error%count),mae,(%:squared%count),((100.0*percentage)%count),((100.0*symmetric)%count),mae%scale
)
winkler =: 3 : 0
    'actual low high multiplier' =. y
    if. actual<low do.
        (high-low)+multiplier*(low-actual) return.
    end.
    if. actual>high do.
        (high-low)+multiplier*(actual-high) return.
    end.
    high-low
)
rank_models =: 3 : '/:2&{::&>y'
