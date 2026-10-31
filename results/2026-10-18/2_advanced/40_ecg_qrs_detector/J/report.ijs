intdiv =: 4 : '<.(x: x)%x: y'
rdiv =: 4 : '((2*x)+y)intdiv 2*y'
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
two =: 3 : 0
    magnitude =. |y
    decimal =. text 100|magnitude
    decimal =. ((2-#decimal)#'0'),decimal
    sign =. ''
    if. y<0 do.
        sign =. '-'
    end.
    sign,(text magnitude intdiv 100),'.',decimal
)
four =: 3 : 0
    decimal =. text 10000|y
    decimal =. ((4-#decimal)#'0'),decimal
    (text y intdiv 10000),'.',decimal
)
fraction =: 4 : 0
    divisor =. x+.y
    (text x intdiv divisor),'/',text y intdiv divisor
)
ratio =: 4 : 0
    if. y=0 do.
        (text x),'/0 none'
    else.
        (text x),'/',(text y),' reduced=',(x fraction y),' percent=',two (10000*x)rdiv y
    end.
)
maybe_two =: 3 : 0
    if. y<0 do.
        'none'
    else.
        two y
    end.
)
missing =: 3 : 0
    if. y<0 do.
        '-'
    else.
        text y
    end.
)
