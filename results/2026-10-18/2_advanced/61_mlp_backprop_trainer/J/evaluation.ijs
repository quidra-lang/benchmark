integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_number =: 3 : '". ''_''(I.y=''-'')}y'
format_real =: 4 : 0
    text =. ,(0 j.x)":y
    if. (0=0".text)*.'_'={.text do. text =. }.text end.
    '-'(I.text='_')}text
)
fixed =: 3 : '4 format_real y'
six =: 3 : '6 format_real y'
ratio =: 4 : 0
    if. y=0 do. ,'-' return. end.
    numerator =. x:x
    denominator =. x:y
    q =. <.((20000x*numerator)+denominator)%(2x*denominator)
    whole =. integer <.q%10000
    digits =. integer 10000|q
    whole,'.',((-4){.'0000',digits)
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do. result =. result,x end.
        result =. result,index{::y
    end.
    result
)
render_value =: 3 : 0
    if. 2=3!:0 y do. ,y else. integer y end.
)
emit =: 3 : ''' ''join render_value&.>y'
formatted =: 4 : ''' ''join (x&format_real)&.>y'
best_two =: 3 : '2{.\:y'
confusion_matrix =: 4 : 0
    matrix =. (x,x)$0
    for_outcome. y do.
        result =. >outcome
        index =. <(1{::result),2{::result
        matrix =. (1+index{matrix)index}matrix
    end.
    matrix
)
class_measures =: 4 : 0
    support =. +/y{x
    predicted =. +/y{"1 x
    truecount =. (<y,y){x
    (<support),(<predicted),(<truecount ratio predicted),(<truecount ratio support),<(2*truecount)ratio support+predicted
)
level_maps =: 3 : 0
    lines =. 0$a:
    for_row. i.ImageHeight do.
        parts =. 0$a:
        for_levels. y do.
            values =. (row*ImageWidth)+i.ImageWidth
            parts =. parts,<(values{>levels){'0123456789'
        end.
        lines =. lines,<' 'join parts
    end.
    lines
)
image_lines =: 3 : 0
    characters =. (y='1'){'.#'
    <"1 (ImageHeight,ImageWidth)$characters
)
