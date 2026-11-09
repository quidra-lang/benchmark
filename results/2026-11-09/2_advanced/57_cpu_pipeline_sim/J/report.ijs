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
decimal =: 4 : 0
    scaled =. (y+20000*x)floor_div 2*y
    tail =. integer 10000|scaled
    (integer scaled floor_div 10000),'.',((4-#tail)$'0'),tail
)
percentage =: 4 : 0
    if. y=0 do. ,'-' return. end.
    scaled =. (y+20000*x)floor_div 2*y
    tail =. integer 100|scaled
    (integer scaled floor_div 100),'.',((2-#tail)$'0'),tail
)
fraction =: 4 : 0
    divisor =. x+.y
    (integer x floor_div divisor),'/',integer y floor_div divisor
)
hexadecimal =: 3 : '''0123456789abcdef''{~(8#16)#:y'
register_text =: 3 : 0
    if. y<0 do. ,'-' else. 'r',integer y end.
)
cycle_heading =: 3 : 0
    'first last' =. y
    'cycle',(18$' '),'0123456789'{~10|first+i.1+last-first
)
diagram_row =: 4 : 0
    'number pc kind annotation' =. x
    identifier =. '     -'
    if. number>:0 do. identifier =. _6{.(6$' '),integer number end.
    identifier,' ',(hexadecimal pc),' ',(6{.kind,6$' '),' ',y,annotation
)
join_parts =: 3 : 0
    result =. 0$a:
    for_i. i.#y do.
        if. i do. result =. result,<'' end.
        result =. result,i{::y
    end.
    result
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
