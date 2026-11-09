zones =: 3 : 0
    'lcl cl ucl' =. >1{"1 y
    upper =. (ucl-cl)%3.0
    lower =. (cl-lcl)%3.0
    'lcl cl ucl u1 u2 l1 l2' record (<lcl),(<cl),(<ucl),(<cl+upper),(<cl+2.0*upper),(<cl-lower),<cl-2.0*lower
)
new_signal =: 3 : '''chart rule start end value direction'' record y'
rule_direction =: 4 : 0
    'window zone' =. y
    'lcl cl ucl u1 u2 l1 l2' =. >1{"1 zone
    value =. {:window
    select. x
    case. 1 do.
        if. (value>!.0 ucl)+.value<!.0 lcl do.
            if. value>!.0 cl do. 'UP' else. 'DOWN' end.
            return.
        end.
    case. 2;3 do.
        if. x=2 do. upper =. u2
        lower =. l2
        needed =. 2
        else. upper =. u1
        lower =. l1
        needed =. 4 end.
        if. (value>!.0 upper)*.(+/window>!.0 upper)>:needed do. 'UP' return. end.
        if. (value<!.0 lower)*.(+/window<!.0 lower)>:needed do. 'DOWN' return. end.
    case. 4 do.
        if. *./window>!.0 cl do. 'UP' return. end.
        if. *./window<!.0 cl do. 'DOWN' return. end.
    case. 5 do.
        differences =. (}.window)-}:window
        if. *./differences>!.0 0 do. 'UP' return. end.
        if. *./differences<!.0 0 do. 'DOWN' return. end.
    case. 6 do.
        differences =. (}.window)-}:window
        positive =. differences>!.0 0
        if. (*./differences~:!.0 0)*.*./(}:positive)~:}.positive do. 'NONE' return. end.
    case. 7 do.
        if. *./(window>!.0 l1)*.window<!.0 u1 do. 'NONE' return. end.
    case. 8 do.
        upper =. window>!.0 u1
        lower =. window<!.0 l1
        if. (*./upper+.lower)*.(+./upper)*.+./lower do. 'NONE' return. end.
    end.
    ''
)
check_rules =: 3 : 0
    'chart numbers values limits rules' =. y
    zone =. zones limits
    signals =. 0$a:
    for_index. i.#values do.
        for_rule. rules do.
            length =. (rule-1){1 3 5 8 6 14 15 8
            if. (index+1)<length do. continue. end.
            first =. index+1-length
            direction =. rule rule_direction (<length{.first}.values),<zone
            if. #direction do.
                valueset =. (<chart),(<number rule),(<first{numbers),(<index{numbers),(<index{values),<direction
                signals =. signals,<new_signal valueset
            end.
        end.
    end.
    signals
)
