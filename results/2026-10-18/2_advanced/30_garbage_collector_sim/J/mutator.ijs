command_names =: 'ALLOC';'PUSH';'LOAD';'POP';'SET';'OVERWRITE';'CHECKPOINT'
read_lines =: 3 : '<;._2 (1!:1 <y)'
read_config =: 3 : 0
    CollectorEntries =: 0$a:
    for_line. read_lines y do.
        fields =. ' 'split >line
        kind =. 0{::fields
        select. kind
        case. 'HEAP' do.
            HeapSize =: num 1{::fields
        case. 'COLLECTOR' do.
            young =. age =. 0
            if. (#fields)>3 do.
                young =. num 3{::fields
                age =. num 4{::fields end.
            CollectorEntries =: CollectorEntries,< (1{fields),(2{fields),(<young),<age
        case. 'MAPS' do.
            MapLabels =: }.fields
        case. 'MMU' do.
            Windows =: num&>}.fields
        case. 'WIDTH' do.
            MapWidth =: num 1{::fields
        end.
    end.
    i.0
)
is_number =: 3 : 0
    if. (0=#y)+.4<#y do.
        0 return.
    end.
    if. (#y)>1 do.
        if. '0'={.y do.
            0 return.
        end.
    end.
    *./y e.'0123456789'
)
is_label =: 3 : 0
    (0<#y)*.(16>:#y)*.*./y e.'abcdefghijklmnopqrstuvwxyz0123456789_'
)
source_value =: 3 : 0
    if. y-:'-' do.
        _1
    else.
        num y
    end.
)
parse_line =: 4 : 0
    fields =. ' 'split y
    kind =. command_names i.{.fields
    defaults =. (<x),(<kind),(<0),(<0),(<0),(<0),(<_1),(<0),<''
    if. kind=7 do.
        (<defaults),<'syntax' return.
    end.
    forms =. (<'nn'),(<'s'),(<'nn'),(<'n'),(<'nns'),(<'ns'),<'l'
    form =. kind{::forms
    if. (#fields)~:1+#form do.
        (<defaults),<'syntax' return.
    end.
    for_index. i.#form do.
        token =. (index+1){::fields
        select. index{form
        case. 'n' do.
            valid =. is_number token
        case. 's' do.
            valid =. (token-:'-')+.is_number token
        case. do.
            valid =. is_label token
        end.
        if. -.valid do.
            (<defaults),<'syntax' return.
        end.
    end.
    command =. defaults
    select. kind
    case. 0 do.
        command =. (<num 1{::fields)2}command
        command =. (<num 2{::fields)3}command
    case. 1 do.
        command =. (<source_value 1{::fields)6}command
    case. 2 do.
        command =. (<num 1{::fields)4}command
        command =. (<num 2{::fields)5}command
    case. 3 do.
        command =. (<num 1{::fields)7}command
    case. 4 do.
        command =. (<num 1{::fields)4}command
        command =. (<num 2{::fields)5}command
        command =. (<source_value 3{::fields)6}command
    case. 5 do.
        command =. (<num 1{::fields)4}command
        command =. (<source_value 2{::fields)6}command
    case. 6 do.
        command =. (1{fields)8}command
    end.
    reason =. ''
    if. kind=0 do.
        if. ((2{::command)>6)+.(3{::command)>24 do.
            reason =. 'range'
        end.
    elseif. kind=3 do.
        if. 0=7{::command do.
            reason =. 'range'
        end.
    end.
    (<command),<reason
)
