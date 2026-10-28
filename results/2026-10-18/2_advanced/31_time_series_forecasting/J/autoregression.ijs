ar_difference =: 3 : 0
    'values season kind' =. y
    offset =. kind{0 1,season,season+1
    result =. i.0
    for_t. offset+i.(#values)-offset do.
        value =. t{values
        select. kind
        case. 1 do.
            value =. value-(t-1){values
        case. 2 do.
            value =. value-(t-season){values
        case. 3 do.
            value =. ((t{values)-(t-1){values)-(((t-season){values)-((t-season)-1){values)
        end.
        result =. result,value
    end.
    (<result),<offset
)
autocorrelation =: 4 : 0
    average =. mean x
    centered =. x-average
    variance =. (total *:centered)%#x
    correlations =. ,1.0
    for_lag. 1+i.y do.
        numerator =. 0.0
        for_i. i.(#x)-lag do.
            numerator =. numerator+(i{centered)*(i+lag){centered
        end.
        correlations =. correlations,(numerator%#x)%variance
    end.
    (<average),(<variance),<correlations
)
durbin_levinson =: 3 : 0
    coefficients =. ,<i.0
    partial =. ,0.0
    variances =. ,1.0
    for_order. 1+i.(#y)-1 do.
        previous =. >{:coefficients
        correction =. 0.0
        for_j. 1+i.order-1 do.
            correction =. correction+((j-1){previous)*(order-j){y
        end.
        theta =. ((order{y)-correction)%{:variances
        current =. i.0
        for_j. 1+i.order-1 do.
            current =. current,((j-1){previous)-theta*((order-j)-1){previous
        end.
        current =. current,theta
        coefficients =. coefficients,<current
        partial =. partial,theta
        variances =. variances,({:variances)*1-theta*theta
    end.
    (<coefficients),(<partial),<variances
)
ar_residuals =: 3 : 0
    'values average coefficients' =. y
    order =. #coefficients
    result =. i.0
    for_i. order+i.(#values)-order do.
        value =. 0.0
        for_j. 1+i.order do.
            value =. value+((j-1){coefficients)*(((i-j){values)-average)
        end.
        result =. result,((i{values)-average)-value
    end.
    result
)
ar_forecast =: 3 : 0
    'values differenced offset kind average coefficients origin steps season' =. y
    transformed =. (origin-offset){.differenced
    extended =. origin{.values
    result =. i.0
    for_step. i.steps do.
        value =. 0.0
        for_j. 1+i.#coefficients do.
            value =. value+((j-1){coefficients)*(((-j){transformed)-average)
        end.
        predicted =. average+value
        transformed =. transformed,predicted
        select. kind
        case. 1 do.
            predicted =. predicted+{:extended
        case. 2 do.
            predicted =. predicted+(-season){extended
        case. 3 do.
            predicted =. ((predicted+{:extended)+(-season){extended)-(-(season+1)){extended
        end.
        extended =. extended,predicted
        result =. result,predicted
    end.
    result
)
ljung_box =: 4 : 0
    count =. #x
    'average variance correlations' =. x autocorrelation >./y
    result =. 0$a:
    for_lag. y do.
        value =. 0.0
        for_k. 1+i.lag do.
            value =. value+(*:k{correlations)%count-k
        end.
        q =. (count*count+2)*value
        z =. q%2.0
        term =. sum =. 1.0
        for_i. 1+i.(lag intdiv 2)-1 do.
            term =. (term*z)%i
            sum =. sum+term
        end.
        result =. result,<(<lag),(<q),<(^-z)*sum
    end.
    result
)
