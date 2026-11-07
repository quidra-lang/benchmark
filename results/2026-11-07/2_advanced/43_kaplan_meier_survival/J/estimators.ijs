risk_sets =: 3 : 0
    moments =. /:~~.2{"1 y
    result =. 0 4$0
    for_moment. moments do.
        at_time =. moment=2{"1 y
        risk =. +/moment<:2{"1 y
        deaths =. +/at_time*.3{"1 y
        censored =. (+/at_time)-deaths
        result =. result,moment,risk,deaths,censored
    end.
    result
)
kaplan_meier =: 3 : 0
    risks =. risk_sets y
    event_rows =. risks#~0<2{"1 risks
    event_times =. 0{"1 event_rows
    result =. 0 10$0.0
    survival =. 1.0
    greenwood =. 0.0
    hazard =. 0.0
    variance =. 0.0
    for_index. i.#event_rows do.
        'moment n d censored' =. index{event_rows
        survival =. survival*(n-d)fraction n
        standard_error =. _1.0
        lower =. _1.0
        upper =. _1.0
        if. n~:d do.
            greenwood =. greenwood+d fraction n*(n-d)
        end.
        if. survival~:0.0 do.
            standard_error =. survival*%:greenwood
            logarithm =. ^.survival
            omega =. (Z95*%:greenwood)%-logarithm
            lower =. ^logarithm*^omega
            upper =. ^logarithm*^-omega
        end.
        hazard =. hazard+d fraction n
        variance =. variance+d fraction n*n
        following =. 10000
        if. (index+1)<#event_times do.
            following =. (index+1){event_times
        end.
        censored =. +/(0=3{"1 y)*.(moment<:2{"1 y)*.(following>2{"1 y)
        result =. result,moment,n,d,censored,survival,standard_error,lower,upper,hazard,%:variance
    end.
    result
)
row_at =: 4 : 0
    for_row. |.x do.
        if. (0{row)<:y do.
            row return.
        end.
    end.
    0 0 0 0 1 0 _1 _1 0 0.0
)
life_table =: 3 : 0
    'subjects width count' =. y
    survival =. 1.0
    variance =. 0.0
    result =. 0 10$0.0
    for_interval. i.count do.
        start =. interval*width
        finish =. (interval+1)*width
        moments =. 2{"1 subjects
        in_interval =. (moments>:start)*.moments<finish
        n =. +/moments>:start
        d =. +/in_interval*.3{"1 subjects
        c =. (+/in_interval)-d
        exposed =. (2*n)-c
        survival =. survival*(exposed-2*d)fraction exposed
        variance =. variance+(4*d)fraction exposed*(exposed-2*d)
        result =. result,start,finish,n,d,c,(exposed%2.0),((2*d)fraction exposed),survival,(survival*%:variance),(2000*d)fraction width*(exposed-d)
    end.
    result
)
