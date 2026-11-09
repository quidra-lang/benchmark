decimal_value =: 3 : '(*y)*<.0.5+(|y)*10000'
real_text =: 3 : 0
    rounded =. decimal_value y
    prefix =. ''
    if. rounded<0 do. prefix =. '-'
        rounded =. -rounded end.
    tail =. number 10000|rounded
    prefix,(number rounded div 10000),'.',((4-#tail)$'0'),tail
)
proportion_text =: 3 : 0
    'numerator denominator' =. y
    (number numerator),'/',(number denominator),' ',real_text numerator%denominator
)
fraction_text =: 3 : 0
    'numerator denominator' =. y
    if. denominator=0 do. '- -' return. end.
    first =. numerator
    second =. denominator
    while. second do. remainder =. second|first
        first =. second
        second =. remainder end.
    proportion_text (numerator div first),denominator div first
)
evaluate =: 4 : 0
    matrix =. (ClassCount,ClassCount)$0
    for_index. i.#x do.
        cell =. (index{x),index{y
        matrix =. (1+(<cell){matrix)(<cell)}matrix
    end.
    correct =. 0
    total =. #x
    scored =. 0
    sum =. 0.0
    for_label. i.ClassCount do.
        hits =. (<label,label){matrix
        correct =. correct+hits
        denominator =. (+/label{matrix)+(+/label{"1 matrix)
        if. denominator>0 do.
            sum =. sum+(2*hits)%denominator
            scored =. scored+1
        end.
    end.
    (<matrix),(<total),(<correct),(<correct%total),<sum%scored
)
evaluation_lines =: 3 : 0
    'matrix total correct micro macro' =. y
    lines =. <'true\predicted ',' ' join Classes
    for_label. i.ClassCount do. lines =. lines,<' ' join (label{Classes),<"0 label{matrix end.
    for_label. i.ClassCount do.
        hits =. (<label,label){matrix
        predicted =. +/label{"1 matrix
        support =. +/label{matrix
        lines =. lines,<'class | precision | recall | f1 | support |' format (label{Classes),(<fraction_text hits,predicted),(<fraction_text hits,support),(<fraction_text (2*hits),predicted+support),<support
    end.
    lines,<'micro_f1 | macro_f1 |' format (<real_text micro),<real_text macro
)
