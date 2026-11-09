zeros =: 3 : '(y,y)$0.0'
ordered_sum =: 3 : 0
    total =. 0.0
    for_value. y do.
        total =. total+value
    end.
    total
)
dot =: 4 : 0
    total =. 0.0
    for_index. i.#x do.
        total =. total+(index{x)*index{y
    end.
    total
)
cholesky =: 3 : 0
    lower =. zeros #y
    for_row. i.#y do.
        for_column. i.row+1 do.
            subtotal =. 0.0
            for_index. i.column do.
                subtotal =. subtotal+((<row,index){lower)*(<column,index){lower
            end.
            remainder =. ((<row,column){y)-subtotal
            if. row=column do.
                value =. %:remainder
            else.
                value =. remainder%(<column,column){lower
            end.
            lower =. value (<row,column)}lower
        end.
    end.
    lower
)
forward =: 4 : 0
    lower =. x
    result =. (#lower)$0.0
    for_row. i.#lower do.
        subtotal =. 0.0
        for_index. i.row do.
            subtotal =. subtotal+((<row,index){lower)*index{result
        end.
        value =. ((row{y)-subtotal)%(<row,row){lower
        result =. value row}result
    end.
    result
)
backward =: 4 : 0
    lower =. x
    size =. #lower
    result =. size$0.0
    for_row. |.i.size do.
        subtotal =. 0.0
        for_index. (row+1)+i.size-(row+1) do.
            subtotal =. subtotal+((<index,row){lower)*index{result
        end.
        value =. ((row{y)-subtotal)%(<row,row){lower
        result =. value row}result
    end.
    result
)
log_determinant =: 3 : 0
    total =. 0.0
    for_index. i.#y do.
        total =. total+^.(<index,index){y
    end.
    2*total
)
quadratic =: 4 : 0
    transformed =. x forward y
    transformed dot transformed
)
jacobi =: 3 : 0
    size =. #y
    current =. y
    vectors =. zeros size
    for_index. i.size do.
        vectors =. 1.0 (<index,index)}vectors
    end.
    sweeps =. 0
    while. 1 do.
        off =. 0.0
        for_first. i.size-1 do.
            for_second. (first+1)+i.size-(first+1) do.
                value =. (<first,second){current
                off =. off+value*value
            end.
        end.
        if. ((%:off)<1e_12)+.sweeps=50 do.
            break.
        end.
        for_first. i.size-1 do.
            for_second. (first+1)+i.size-(first+1) do.
                value =. (<first,second){current
                if. value=0.0 do.
                    continue.
                end.
                theta =. (((<second,second){current)-(<first,first){current)%2*value
                sign =. 1.0
                if. theta<0.0 do.
                    sign =. _1.0
                end.
                tangent =. sign%(|theta)+%:(theta*theta)+1.0
                cosine =. 1.0%%:(tangent*tangent)+1.0
                sine =. tangent*cosine
                for_index. i.size do.
                    if. (index~:first)*.index~:second do.
                        horizontal =. (<index,first){current
                        vertical =. (<index,second){current
                        a =. (cosine*horizontal)-sine*vertical
                        b =. (sine*horizontal)+cosine*vertical
                        current =. a (<index,first)}current
                        current =. a (<first,index)}current
                        current =. b (<index,second)}current
                        current =. b (<second,index)}current
                    end.
                end.
                value =. (<first,second){current
                current =. (((<first,first){current)-tangent*value)(<first,first)}current
                current =. (((<second,second){current)+tangent*value)(<second,second)}current
                current =. 0.0 (<first,second)}current
                current =. 0.0 (<second,first)}current
                for_index. i.size do.
                    horizontal =. (<index,first){vectors
                    vertical =. (<index,second){vectors
                    vectors =. ((cosine*horizontal)-sine*vertical)(<index,first)}vectors
                    vectors =. ((sine*horizontal)+cosine*vertical)(<index,second)}vectors
                end.
            end.
        end.
        sweeps =. sweeps+1
    end.
    values =. 0$0.0
    for_index. i.size do.
        values =. values,(<index,index){current
    end.
    (<values),(<vectors),<sweeps
)
