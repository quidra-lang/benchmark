spline_fit_values =: 4 : 0
    'positions points penalty h d l1 l2' =. 7{.x
    count =. #y
    size =. count-2
    z =. size$0.0
    for_index. i.size do.
        value =. (((index+2){y)-(index+1){y)%(index+1){h
        value =. value-(((index+1){y)-index{y)%index{h
        if. index>:1 do.
            value =. value-(index{l1)*(index-1){z
        end.
        if. index>:2 do.
            value =. value-(index{l2)*(index-2){z
        end.
        z =. value index}z
    end.
    gamma =. count$0.0
    for_index. |.i.size do.
        value =. (index{z)%index{d
        if. (index+1)<size do.
            value =. value-((index+1){l1)*(index+2){gamma
        end.
        if. (index+2)<size do.
            value =. value-((index+2){l2)*(index+3){gamma
        end.
        gamma =. value (index+1)}gamma
    end.
    omega =. ,((1{gamma)-0{gamma)%0{h
    for_index. 1+i.count-2 do.
        value =. (((index+1){gamma)-index{gamma)%index{h
        value =. value-((index{gamma)-(index-1){gamma)%(index-1){h
        omega =. omega,value
    end.
    omega =. omega,0-(({:gamma)-(_2{gamma))%{:h
    (<y-penalty*omega),<gamma
)
spline_evaluate_fit =: 4 : 0
    'estimates gamma position' =. y
    positions =. 0{::x
    points =. 1{::x
    h =. 3{::x
    x0 =. position%100
    count =. #positions
    index =. +/positions<position
    if. index<count do.
        if. position=index{positions do.
            index{estimates return.
        end.
    end.
    if. index=0 do.
        slope =. ((1{estimates)-0{estimates)%0{h
        slope =. slope-((0{h)*1{gamma)%6
        (0{estimates)-((0{points)-x0)*slope return.
    elseif. index=count do.
        slope =. (({:estimates)-_2{estimates)%{:h
        slope =. slope+(({:h)*_2{gamma)%6
        ({:estimates)+(x0-{:points)*slope return.
    end.
    i =. index-1
    left =. x0-i{points
    right =. (index{points)-x0
    first =. ((left*index{estimates)+right*i{estimates)%i{h
    second =. ((1+left%i{h)*index{gamma)+(1+right%i{h)*i{gamma
    first-((left*right)*second)%6
)
spline_estimate =: 4 : 'x spline_evaluate_fit (<7{::x),(<8{::x),<y'
spline_weights =: 4 : 0
    result =. i.0
    for_box. 9{::x do.
        'estimates gamma' =. >box
        result =. result,x spline_evaluate_fit (<estimates),(<gamma),<y
    end.
    result
)
spline_fit =: 3 : 0
    'positions values penalty diagnostics' =. y
    points =. positions%100
    h =. (}.points)-}:points
    size =. (#positions)-2
    a =. %}:h
    c =. %}.h
    b =. -a+c
    diagonal =. i.0
    first =. i.0
    second =. i.0
    for_index. i.size do.
        value =. ((index{h)+(index+1){h)%3
        squares =. ((*:index{a)+*:index{b)+*:index{c
        diagonal =. diagonal,value+penalty*squares
        if. (index+1)<size do.
            first =. first,(((index+1){h)%6)+((penalty*index{c)*((index{b)+(index+1){b))
        end.
        if. (index+2)<size do.
            second =. second,(penalty*index{c)*(index+1){c
        end.
    end.
    d =. size$0.0
    l1 =. size$0.0
    l2 =. size$0.0
    for_index. i.size do.
        if. index>:2 do.
            l2 =. (((index-2){second)%(index-2){d)index}l2
        end.
        if. index>:1 do.
            correction =. 0.0
            if. index>:2 do.
                correction =. ((index{l2)*(index-2){d)*(index-1){l1
            end.
            value =. (((index-1){first)-correction)%(index-1){d
            l1 =. value index}l1
        end.
        value =. index{diagonal
        if. index>:1 do.
            value =. value-((index{l1)*index{l1)*(index-1){d
        end.
        if. index>:2 do.
            value =. value-((index{l2)*index{l2)*(index-2){d
        end.
        d =. value index}d
    end.
    model =. (<positions),(<points),(<penalty),(<h),(<d),(<l1),<l2
    'fitted gamma' =. model spline_fit_values values
    basis =. 0$a:
    leverage =. i.0
    if. diagnostics do.
        for_index. i.#positions do.
            unit =. 1 index}(#positions)$0.0
            fit =. model spline_fit_values unit
            basis =. basis,<fit
            leverage =. leverage,index{0{::fit
        end.
    end.
    model,(<fitted),(<gamma),(<basis),(<leverage),<ordered_sum leverage
)
