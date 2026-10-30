normalize =: 3 : 0
    total =. 0.0
    for_value. y do.
        total =. total+value
    end.
    y%total
)
split_words =: 3 : '<;._1 '' '',y'
read_tokens =: 3 : 0
    rows =. <;._2 (1!:1 <'input/',y)
    split_words&.>rows
)
read_inputs =: 3 : 0
    rows =. read_tokens 'model.txt'
    states =. ;}.0{::rows
    symbols =. ;}.1{::rows
    missing =. 1{::2{::rows
    initial =. normalize ".&>}.3{::rows
    transition =. (0,#states)$0.0
    emission =. (0,#symbols)$0.0
    for_i. i.#states do.
        transition =. transition,normalize ".&>2}.(i+4){::rows
        emission =. emission,normalize ".&>2}.(i+4+#states){::rows
    end.
    model =. (<initial),(<transition),<emission
    (<states),(<symbols),(<missing),(<model),(<read_tokens 'sequences.txt'),(<read_tokens 'labeled.txt'),<read_tokens 'params.txt'
)
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
decimal =: 4 : 0
    factor =. 10x^x
    rounded =. x:<.0.5+(|y)*factor
    sign =. ((y<0.0)*.rounded~:0)#'-'
    tail =. integer factor|rounded
    sign,(integer rounded intdiv factor),'.',((x-#tail)$'0'),tail
)
real_text =: 3 : '4 decimal y'
real_values =: 3 : ''' ''join real_text&.>y'
model_lines =: 4 : 0
    'initial transition emission' =. y
    result =. (<'MODEL ',x),(<'STATES ',' 'join <"0 States),(<'SYMBOLS ',' 'join <"0 Symbols),(<'MISSING ',Missing),<'INITIAL ',real_values initial
    for_i. i.#States do.
        result =. result,<'TRANSITION ',(i{States),' ',real_values i{transition
    end.
    for_i. i.#States do.
        result =. result,<'EMISSION ',(i{States),' ',real_values i{emission
    end.
    result
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
