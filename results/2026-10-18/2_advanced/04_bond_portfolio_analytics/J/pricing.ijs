BasisPoint =: 0.0001
bisection =: 1 : 0
    'low high target' =. y
    for_iteration. i.80 do.
        middle =. (low+high)%2.0
        if. (u middle)>!.0 target do. low =. middle else. high =. middle end.
    end.
    (low+high)%2.0
)
present_values =: 4 : 0
    'flows fraction frequency outstanding' =. x
    first =. 1.0+(fraction*y)%frequency
    growth =. 1.0+y%frequency
    factor =. 1.0
    values =. 0$0.0
    for_cash. flows do.
        values =. values,(real cash)%(first*factor)
        factor =. factor*growth
    end.
    values
)
dirty_price =: 4 : 0
    total =. 0.0
    for_value. x present_values y do. total =. total+value end.
    (total*100.0)%real 3{::x
)
yield_to_maturity =: 4 : 0
    pricer =. x
    (pricer&dirty_price) bisection 0.0 1.0,y
)
yield_risk =: 4 : 0
    pricer =. x
    values =. pricer present_values y
    fraction =. 1{::pricer
    frequency =. real 2{::pricer
    total =. weighted =. curvature =. 0.0
    for_index. i.#values do.
        years =. (index+fraction)%frequency
        value =. index{values
        total =. total+value
        weighted =. weighted+years*value
        curvature =. curvature+years*(years+1.0%frequency)*value
    end.
    growth =. 1.0+y%frequency
    macaulay =. weighted%total
    modified =. macaulay%growth
    convexity =. curvature%(total*growth*growth)
    dv01 =. ((pricer dirty_price y-BasisPoint)-pricer dirty_price y+BasisPoint)%2.0
    macaulay,modified,convexity,dv01
)
