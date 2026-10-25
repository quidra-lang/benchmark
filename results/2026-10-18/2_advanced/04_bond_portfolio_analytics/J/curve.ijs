zero_rate =: 4 : 0
    'days rates' =. x
    if. y<:{.days do. {.rates return. end.
    if. y>:{:days do. {:rates return. end.
    index =. 1
    while. y>index{days do. index =. index+1 end.
    if. y=index{days do. index{rates return. end.
    lowday =. (index-1){days
    lowrate =. (index-1){rates
    weight =. (real y-lowday)%real (index{days)-lowday
    lowrate+((index{rates)-lowrate)*weight
)
discount_factor =: 4 : 0
    'day spread' =. y
    rate =. (x zero_rate day)+spread
    years =. day div 365
    remainder =. 365|day
    growth =. 1.0
    for_year. i.years do. growth =. growth*1.0+rate end.
    1.0%(growth*1.0+(rate*real remainder)%365.0)
)
curve_value =: 4 : 0
    'flows spread' =. y
    total =. 0.0
    for_row. flows do.
        'day cash' =. row
        total =. total+(real cash)*x discount_factor day,spread
    end.
    total
)
forward_rate =: 4 : 0
    'start finish' =. y
    ratio =. (x discount_factor start,0.0)%x discount_factor finish,0.0
    ((ratio-1.0)*365.0)%real finish-start
)
shift_curve =: 4 : '({.x),<(1{::x)+y'
flat_curve =: 3 : '(<,0),<,y'
bootstrap =: 3 : 0
    days =. 0$0
    rates =. 0$0.0
    for_box. y do.
        'maturity coupon frequency' =. >box
        dates =. coupon_schedule Settlement,maturity,frequency,0 0
        flows =. 0 2$0.0
        for_index. i.(#dates)-1 do.
            'numerator denominator' =. '30/360' year_fraction (index{dates),(index+1){dates
            cash =. ((real coupon)*numerator)%(10000.0*denominator)
            if. index=(#dates)-2 do. cash =. cash+1.0 end.
            flows =. flows,(((index+1){dates)-Settlement),cash
        end.
        days =. days,maturity-Settlement
        BootstrapDays =: days
        BootstrapRates =: rates
        BootstrapFlows =: flows
        trial =. 3 : '((<BootstrapDays),<BootstrapRates,y) curve_value (<BootstrapFlows),<0.0'
        rate =. trial bisection 0.0 1.0 1.0
        rates =. rates,rate
    end.
    (<days),<rates
)
z_spread =: 4 : 0
    'flows target' =. y
    SpreadCurve =: x
    SpreadFlows =: flows
    trial =. 3 : 'SpreadCurve curve_value (<SpreadFlows),<y'
    trial bisection _0.5 0.5,target
)
