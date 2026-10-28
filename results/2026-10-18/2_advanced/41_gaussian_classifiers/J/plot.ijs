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
real_text =: 3 : 0
    value =. 0j4":y
    value =. value#~value~:' '
    if. value-:'_0.0000' do.
        '0.0000'
    else.
        '-'(I.value='_')}value
    end.
)
reals =: 3 : 0
    ' 'join real_text&.>y
)
fraction_text =: 3 : 0
    if. 0=#y do.
        '-' return.
    end.
    'numerator denominator' =. y
    (text numerator),'/',(text denominator),' ',real_text (0.0+numerator)%denominator
)
ratio_text =: 4 : 'fraction_text x reduced_fraction y'
frame =: 3 : 0
    border =. '+',((1{$y)#'-'),'+'
    result =. <border
    for_row. y do.
        result =. result,<'|',row,'|'
    end.
    result,<border
)
cell =: 3 : 0
    'value low high size' =. y
    <.(((value-low)%(high-low))*(size-1))+0.5
)
join_sections =: 3 : 0
    result =. 0$a:
    for_index. i.#y do.
        if. index do.
            result =. result,<''
        end.
        result =. result,index{::y
    end.
    result
)
save_lines =: 4 : 0
    content =. ''
    for_box. y do.
        content =. content,(>box),LF
    end.
    content 1!:2 <'output/',x
)
