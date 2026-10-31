named =: 4 : 0
    fields =. 0$a:
    for_index. i.#x do.
        fields =. fields,<(index{::x),'=',index{::y
    end.
    ' 'join fields
)
number_list =: 3 : 0
    if. #y do.
        ','join text&.>y
    else.
        '-'
    end.
)
frequency =: 3 : 0
    ordered =. /:~y
    fields =. 0$a:
    index =. 0
    while. index<#ordered do.
        end =. index+1
        while. end<#ordered do.
            if. (end{ordered)~:index{ordered do.
                break.
            end.
            end =. end+1
        end.
        fields =. fields,<(text index{ordered),':',text end-index
        index =. end
    end.
    if. #fields do.
        ','join fields
    else.
        '-'
    end.
)
queens_board =: 3 : 0
    lines =. 0$a:
    for_column. y do.
        lines =. lines,<((column-1)#'.'),'Q',((#y)-column)#'.'
    end.
    lines
)
save_lines =: 4 : 0
    content =. ''
    for_box. y do.
        content =. content,(>box),LF
    end.
    content 1!:2 <'output/',x
)
save_paragraphs =: 4 : 0
    lines =. 0$a:
    for_index. i.#y do.
        if. index do.
            lines =. lines,<''
        end.
        lines =. lines,index{::y
    end.
    x save_lines lines
)
