fraction_text =: 4 : 0
    divisor =. (|x)+.y
    (text x intdiv divisor),'/',text y intdiv divisor
)
root_text =: 3 : 0
    value =. 0j3\":%:y
    value#~value~:' '
)
ari_text =: 4 : 0
    value =. 0j4\":x%y
    value =. value#~value~:' '
    if. value-:'_0.0000' do.
        value =. '0.0000'
    end.
    value =. '-'(I.value='_')}value
    (x fraction_text y),' ',value
)
framed =: 4 : 0
    border =. '+',(x#'-'),'+'
    result =. ,<border
    for_row. y do.
        result =. result,<'|',(>row),'|'
    end.
    result,<border
)
write_lines =: 4 : 0
    value =. ''
    for_line. y do.
        value =. value,(>line),LF
    end.
    value 1!:2 <'output/',x
)
