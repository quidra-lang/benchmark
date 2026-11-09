read_lines =: 3 : '<;._2 (1!:1 <y)'
num =: 3 : 0
    if. '-'={.y do.
        -x:0".}.y
    else.
        x:0".y
    end.
)
read_ecg =: 3 : 0
    result =. i.0x
    for_box. }.read_lines 'input/ecg.csv' do.
        words =. <;._1 ',',>box
        result =. result,num 1{::words
    end.
    result
)
read_annotations =: 3 : 0
    result =. 0 3$0x
    for_box. }.read_lines 'input/annotations.csv' do.
        words =. <;._1 ',',>box
        result =. result,(num 0{::words),('NVA'i.{.1{::words),_1
    end.
    result
)
read_params =: 3 : 0
    result =. i.0x
    for_box. read_lines 'input/params.txt' do.
        words =. <;._1 ' ',>box
        result =. result,num 1{::words
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
