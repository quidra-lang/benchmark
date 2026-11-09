format =: 4 : 0
    parts =. '|' split x
    text =. 0{::parts
    for_index. i.#y do.
        value =. index{::y
        if. 2~:3!:0 value do. value =. number value end.
        text =. text,value,(index+1){::parts
    end.
    text
)
text_line =: 3 : 0
    fields =. 0$a:
    for_box. y do.
        value =. >box
        if. 2~:3!:0 value do. value =. number value end.
        fields =. fields,<value
    end.
    ' ' join fields
)
fixed_width_line =: 4 : 0
    'label labelwidth cellwidth' =. x
    text =. label,(0>.labelwidth-#label)#' '
    for_cell. y do.
        value =. >cell
        text =. text,((0>.cellwidth-#value)#' '),value
    end.
    text
)
rounded_percent =: 4 : '((200*x)+y) div 2*y'
write_lines =: 4 : 0
    ((LF join y),LF) 1!:2 <'output/',x
    i.0
)
write_files =: 3 : 0
    if. -.fexist 'output' do. 1!:5 <'output' end.
    for_file. y do.
        'name lines' =. >file
        name write_lines lines
    end.
    i.0
)
