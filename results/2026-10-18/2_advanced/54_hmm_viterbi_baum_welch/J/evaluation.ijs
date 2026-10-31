fraction =: 4 : 0
    if. y=0 do.
        '-' return.
    end.
    numerator =. x
    denominator =. y
    if. denominator<0 do.
        numerator =. -numerator
        denominator =. -denominator
    end.
    divisor =. (|numerator)+.denominator
    (integer numerator intdiv divisor),'/',integer denominator intdiv divisor
)
confusion_matrix =: 3 : '(y,y)$0x'
accumulate_confusion =: 4 : 0
    'truth prediction' =. y
    result =. x
    for_t. i.#truth do.
        position =. <(t{truth),t{prediction
        result =. (1+position{result)position}result
    end.
    result
)
correct_count =: 4 : '+/x=y'
matrix_lines =: 4 : 0
    width =. 1
    for_value. ,y do.
        width =. width>.#integer value
    end.
    header =. ' '
    for_state. x do.
        header =. header,' ',((width-1)$' '),state
    end.
    rows =. <header
    for_i. i.#x do.
        line =. ,i{x
        for_value. i{y do.
            text =. integer value
            line =. line,' ',((width-#text)$' '),text
        end.
        rows =. rows,<line
    end.
    rows
)
metric_lines =: 4 : 0
    row_sums =. +/"1 y
    column_sums =. +/y
    total =. +/row_sums
    correct =. 0
    for_i. i.#x do.
        correct =. correct+(<i,i){y
    end.
    expected =. +/row_sums*column_sums
    rows =. (<'ACCURACY ',correct fraction total),<'KAPPA ',((total*correct)-expected)fraction (total*total)-expected
    for_i. i.#x do.
        true_positive =. (<i,i){y
        rows =. rows,<'STATE ',(i{x),' precision ',(true_positive fraction i{column_sums),' recall ',(true_positive fraction i{row_sums),' f1 ',(2*true_positive)fraction (i{column_sums)+i{row_sums
    end.
    rows
)
runs =: 3 : 0
    result =. 0 3$0
    if. 0=#y do.
        result return.
    end.
    start =. 0
    state =. {.y
    for_t. 1+i.<:#y do.
        if. state~:t{y do.
            result =. result,state,start,t-1
            state =. t{y
            start =. t
        end.
    end.
    result,state,start,(#y)-1
)
matched_regions =: 4 : 0
    total =. 0
    for_a. x do.
        for_b. y do.
            if. ((0{a)<:1{b)*.(0{b)<:1{a do.
                total =. total+1
                break.
            end.
        end.
    end.
    total
)
region_counts =: 4 : '(#x),(#y),(x matched_regions y),y matched_regions x'
boundaries =: 3 : '1+I.(}.y)~:}:y'
matched_boundaries =: 4 : 0
    'other tolerance' =. y
    total =. 0
    for_position. x do.
        if. +./(|position-other)<:tolerance do.
            total =. total+1
        end.
    end.
    total
)
boundary_counts =: 3 : 0
    'prediction actual tolerance' =. y
    predicted =. boundaries prediction
    truth =. boundaries actual
    (#predicted),(#truth),(predicted matched_boundaries (<truth),<tolerance),truth matched_boundaries (<predicted),<tolerance
)
