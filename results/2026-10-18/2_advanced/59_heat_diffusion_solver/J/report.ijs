integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : ''' ''join integer&.>y'
real_text =: 4 : 0
    factor =. 10x^x
    rounded =. x:<.0.5+(|y)*(0.0+factor)
    tail =. integer factor|rounded
    sign =. ((y<0.0)*.rounded~:0)#'-'
    sign,(integer rounded floor_div factor),'.',((x-#tail)$'0'),tail
)
time_text =: 3 : 0
    tail =. integer 1000|y
    (integer y floor_div 1000),'.',((3-#tail)$'0'),tail
)
temperature_lines =: 3 : 0
    result =. 0$a:
    for_row. i.Height do.
        values =. ((Width*row)+i.Width){y
        result =. result,<' 'join (2&real_text)&.>values
    end.
    result
)
isotherm_lines =: 4 : 0
    hottest =. {.I.y=>./y
    counts =. (1+#x)$0
    characters =. ''
    for_p. i.#y do.
        digit =. +/(p{y)>:x
        counts =. (1+digit{counts)digit}counts
        characters =. characters,digit{'0123456789'
    end.
    characters =. '*'hottest}characters
    (<counts),<<"1 Height Width$characters
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
