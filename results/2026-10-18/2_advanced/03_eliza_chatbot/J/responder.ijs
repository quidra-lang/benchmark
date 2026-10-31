reflect_words =: 3 : 0
    words =. 0$a:
    for_box. y do.
        word =. >box
        if. word has_key PostTable do. words =. words,word get_key PostTable
        else. words =. words,box end.
    end.
    words
)
binding =: 4 : 0
    if. (x>:1)*.x<:#y do. (x-1){::y else. 0$a: end.
)
build_reply =: 4 : 0
    bindings =. x
    text =. ''
    position =. 0
    while. position<#y do.
        chunk =. (3<.(#y)-position){.position}.y
        if. is_reference chunk do.
            value =. Digits i.1{chunk
            text =. text,' ' join reflect_words value binding bindings
            position =. position+3
        else.
            text =. text,position{y
            position =. position+1
        end.
    end.
    parts =. ' ' split text
    text =. ' ' join parts#~0<#&>parts
    if. #text do. text =. (toupper {.text),}.text end.
    text
)
restated_words =: 4 : 0
    words =. 0$a:
    for_box. y do.
        arg =. >box
        if. is_reference arg do. words =. words,(Digits i.1{arg) binding x
        else. words =. words,box end.
    end.
    words
)
eliza_lines =: 3 : 0
    words =. ' ' split y
    lines =. 0$a:
    line =. 'ELIZA: ',0{::words
    for_box. }.words do.
        word =. >box
        if. ((#line)+1+#word)<:72 do. line =. line,' ',word
        else.
            lines =. lines,<line
            line =. (7#' '),word
        end.
    end.
    lines,<line
)
