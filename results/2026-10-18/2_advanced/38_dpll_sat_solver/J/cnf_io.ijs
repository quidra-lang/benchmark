read_lines =: 3 : '<;._2 (1!:1 <y)'
num =: 3 : 0
    if. '-'={.y do.
        -0".}.y
    else.
        0".y
    end.
)
intdiv =: 4 : '<.(x: x)%x: y'
text =: 3 : 0
    value =. ":y
    '-'(I.value='_')}value
)
words =: 3 : 0
    parts =. <;._1 ' ',y
    (0<#&>parts)#parts
)
join =: 4 : 0
    result =. ''
    for_index. i.#y do.
        if. index do.
            result =. result,x
        end.
        result =. result,index{::y
    end.
    result
)
valid_number =: 3 : 0
    if. (0=#y)+.6<#y do.
        0 return.
    end.
    if. -.*./y e.'0123456789' do.
        0 return.
    end.
    (y-:'0')+.'0'~:{.y
)
valid_literal =: 3 : 0
    if. y-:'0' do.
        1 return.
    end.
    digits =. y
    if. #y do.
        if. '-'={.y do.
            digits =. }.y
        end.
    end.
    (valid_number digits)*.-.digits-:'0'
)
dimacs_error =: 3 : '(<0),(<0$a:),<y'
read_dimacs =: 3 : 0
    variables =. _1
    declared =. _1
    clauses =. 0$a:
    partial =. i.0
    lines =. read_lines 'input/',y
    for_index. i.#lines do.
        line =. index{::lines
        number =. index+1
        tokens =. words line
        if. 0=#tokens do.
            continue.
        end.
        if. 'c'={.line do.
            continue.
        end.
        if. 'p'-:0{::tokens do.
            if. variables>:0 do.
                dimacs_error 'duplicate header at line ',text number return.
            end.
            valid =. 4=#tokens
            if. valid do.
                valid =. ('cnf'-:1{::tokens)*.(valid_number 2{::tokens)*.valid_number 3{::tokens
            end.
            if. -.valid do.
                dimacs_error 'bad header at line ',text number return.
            end.
            variables =. num 2{::tokens
            declared =. num 3{::tokens
        else.
            if. variables<0 do.
                dimacs_error 'missing header' return.
            end.
            for_box. tokens do.
                token =. >box
                if. -.valid_literal token do.
                    dimacs_error 'bad token ',token,' at line ',text number return.
                end.
                literal =. num token
                if. (|literal)>variables do.
                    dimacs_error 'literal out of range ',token,' at line ',text number return.
                end.
                if. literal=0 do.
                    clauses =. clauses,<partial
                    partial =. i.0
                else.
                    partial =. partial,literal
                end.
            end.
        end.
    end.
    if. variables<0 do.
        dimacs_error 'missing header'
    elseif. #partial do.
        dimacs_error 'unterminated clause'
    elseif. declared~:#clauses do.
        dimacs_error 'clause count mismatch header=',(text declared),' found=',text #clauses
    else.
        (<variables),(<clauses),<''
    end.
)
model_lines =: 3 : 0
    literals =. (1+i.#y)*((2*y)-1)
    tokens =. (text&.>literals),<'0'
    lines =. 0$a:
    for_start. 10*i.>.(#tokens)%10 do.
        fields =. (start+i.10<.(#tokens)-start){tokens
        lines =. lines,<'v ',' 'join fields
    end.
    lines
)
