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
words =: 3 : ''' ''join integer&.>y'
read_lines =: 3 : '<;._2 (1!:1 <y)'
integers =: 3 : 'x:".&><;._1 '' '',y'
read_inputs =: 3 : 0
    rows =. read_lines 'input/image.pgm'
    image =. >integers&.>3}.rows
    trig =. 1 2{"1 >integers&.>read_lines 'input/trig.txt'
    params =. 0$a:
    for_line. read_lines 'input/params.txt' do.
        fields =. }. <;._1 ' ',>line
        params =. params,<x:".&>fields
    end.
    (<image),(<trig),<params
)
write_lines =: 4 : 0
    ((LF join y),LF)1!:2 <'output/',x
)
write_pgm =: 4 : 0
    'height width' =. $y
    lines =. (<'P2'),(<(integer width),' ',integer height),<'255'
    for_row. y do.
        lines =. lines,<words row
    end.
    x write_lines lines
)
