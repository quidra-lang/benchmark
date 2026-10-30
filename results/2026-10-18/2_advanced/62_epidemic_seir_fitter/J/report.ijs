intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
format_real =: 4 : 0
    text =. ,(0 j.x)":y
    if. (0=0".text)*.'_'={.text do. text =. }.text end.
    '-'(I.text='_')}text
)
fixed =: 3 : '4 format_real y'
six =: 3 : '6 format_real y'
one =: 3 : '1 format_real y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
render_value =: 3 : 0
    if. 2=3!:0 y do. ,y else. integer y end.
)
emit =: 3 : ''' ''join render_value&.>y'
formatted =: 4 : ''' ''join (x&format_real)&.>y'
plot_curve =: 4 : 0
    observed =. x
    fitted =. y
    days =. #observed
    maximum =. >./observed
    width =. #integer maximum
    grid =. 20 70$'.'
    for_column. i.70 do.
        day =. (column*(days-1))intdiv 69
        actual =. 19<.(20*day{observed)intdiv maximum
        model =. 19<.<.(20*day{fitted)%maximum
        grid =. 'o'(<actual,column)}grid
        character =. (actual=model){'*#'
        grid =. character(<model,column)}grid
    end.
    lines =. <emit 'plot observed o fitted * both # days 1';days;'max';maximum
    for_row. |.i.20 do.
        label =. integer (maximum*row)intdiv 20
        text =. ((width-#label)$' '),label,' |',row{grid
        lines =. lines,<text
    end.
    ticks =. 70$'-'
    ticks =. '+'(10*i.7)}ticks
    lines =. lines,<((width+1)$' '),'+',ticks
    labels =. 70$' '
    for_column. 10*i.7 do.
        day =. 1+(column*(days-1))intdiv 69
        text =. integer day
        labels =. text(column+i.#text)}labels
    end.
    text =. ((width+2)$' '),labels
    text =. (1+{:I.text~:' '){.text
    lines,<text
)
