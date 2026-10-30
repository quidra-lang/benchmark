Levels =: ' .:-=+*#%@'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
scaled =: 4 : 0
    factor =. 10x^x
    result =. x:<.0.5+(|y)*factor
    if. y<0.0 do.
        result =. -result
    end.
    result
)
decimal =: 4 : 0
    factor =. 10x^x
    rounded =. x scaled y
    absolute =. |rounded
    tail =. integer factor|absolute
    sign =. (rounded<0)#'-'
    sign,(integer absolute intdiv factor),'.',((x-#tail)$'0'),tail
)
dec =: 3 : '4 decimal y'
values =: 3 : ''' ''join dec&.>y'
integers =: 3 : ''' ''join integer&.>y'
framed =: 3 : 0
    border =. '+',((#>0{y)$'-'),'+'
    rows =. <border
    for_row. y do.
        rows =. rows,<'|',(>row),'|'
    end.
    rows,<border
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
write_blocks =: 4 : 0
    rows =. 0$a:
    for_i. i.#y do.
        if. i do.
            rows =. rows,<''
        end.
        rows =. rows,i{::y
    end.
    x write_lines rows
)
