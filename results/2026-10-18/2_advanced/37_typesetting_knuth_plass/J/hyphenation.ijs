is_letter =: 3 : 'y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'''
lower_ascii =: 3 : 0
    codes =. a.i.y
    codes =. codes+32*((codes>:65)*.codes<:90)
    codes{a.
)
upper_ascii =: 3 : 0
    codes =. a.i.y
    codes =. codes-32*((codes>:97)*.codes<:122)
    codes{a.
)
register_word =: 3 : 0
    parts =. '-'split y
    word =. ''join parts
    position =. 0
    points =. i.0
    for_index. i.(#parts)-1 do.
        position =. position+#index{::parts
        points =. points,position
    end.
    index =. DictionaryNames i.<word
    if. index=#DictionaryNames do.
        DictionaryNames =: DictionaryNames,<word
        DictionaryPoints =: DictionaryPoints,<points
    else.
        DictionaryPoints =: (<points)index}DictionaryPoints
    end.
    0
)
new_dictionary =: 4 : 0
    'LeftMin RightMin' =: x
    DictionaryNames =: 0$a:
    DictionaryPoints =: 0$a:
    for_word. y do.
        register_word >word
    end.
    0
)
split_points =: 3 : 0
    word =. y
    first =. 0
    last =. #word
    while. first<last do.
        if. is_letter first{word do.
            break.
        end.
        first =. first+1
    end.
    while. last>first do.
        if. is_letter (last-1){word do.
            break.
        end.
        last =. last-1
    end.
    core =. (last-first){.first}.word
    found =. (1+#word)$0
    appended =. (1+#word)$0
    if. (0<#core)*.*./is_letter"0 core do.
        index =. DictionaryNames i.<lower_ascii core
        if. index<#DictionaryNames do.
            for_position. index{::DictionaryPoints do.
                if. (position>:LeftMin)*.((#core)-position)>:RightMin do.
                    found =. 1 (first+position)}found
                    appended =. 1 (first+position)}appended
                end.
            end.
        end.
    end.
    for_index. 1+i.0>.(#word)-2 do.
        if. '-'=index{word do.
            if. (is_letter (index-1){word)*.is_letter (index+1){word do.
                found =. 1 (index+1)}found
                appended =. 0 (index+1)}appended
            end.
        end.
    end.
    result =. 0 2$0
    for_position. I.found do.
        result =. result,position,position{appended
    end.
    result
)
