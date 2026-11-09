fraction =: 3 : 0
    'numerator denominator' =. 2 x:y
    text =. integer numerator
    if. denominator~:1 do.
        text =. text,'/',integer denominator
    end.
    text
)
bundle =: 3 : 0
    names =. (mask_items y){ItemNames
    if. #names do.
        '+'join names
    else.
        ,'-'
    end.
)
number_list =: 3 : 0
    if. #y do.
        '+'join integer&.>/:~y
    else.
        ,'-'
    end.
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
