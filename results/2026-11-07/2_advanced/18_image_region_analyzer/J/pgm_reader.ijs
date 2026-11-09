read_lines =: 3 : '<;._2 (1!:1 <y)'
read_words =: 3 : 0
    words =. 0$a:
    for_line. read_lines y do.
        line =. >line
        line =. (line i.'#'){.line
        fields =. ' ' split line
        words =. words,fields#~0<#&>fields
    end.
    words
)
read_images =: 3 : 0
    words =. read_words y
    images =. 0$a:
    position =. 0
    while. position<#words do.
        name =. (position+1){::words
        width =. num (position+3){::words
        height =. num (position+4){::words
        maximum =. num (position+5){::words
        position =. position+6
        pixels =. (height,width)$num&>(width*height){.position}.words
        position =. position+width*height
        images =. images,<(<name),(<width),(<height),(<maximum),<pixels
    end.
    images
)
