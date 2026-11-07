integer =: 3 : 0
    text =. ":<.y
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
words =: 3 : ''' ''join integer&.>y'
fraction =: 4 : 0
    common =. x+.y
    (integer <.(x:x)%common),'/',integer <.(x:y)%common
)
ids_text =: 3 : 0
    if. 0=#y do.
        '-'
    else.
        words y
    end.
)
distances_text =: 3 : 0
    fields =. 0$a:
    for_pair. y do.
        fields =. fields,<(integer 0{pair),':',integer 1{pair
    end.
    if. 0=#fields do.
        '-'
    else.
        ' 'join fields
    end.
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
