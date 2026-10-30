BinarySymbols =: <;._1 ' + - * / % < <= > >= == !='
BinaryOpcodes =: ;:'ADD SUB MUL DIV MOD LT LE GT GE EQ NE'
JumpOpcodes =: ;:'JUMP JUMPF JUMPT'
ConditionalOpcodes =: ;:'JUMPF JUMPT'
TransferOpcodes =: ;:'JUMP RET RETV HALT'
CompareOpcodes =: ;:'LT LE GT GE EQ NE'
NegatedOpcodes =: ;:'GE GT LE LT NE EQ'
emit_instruction =: 3 : 'GeneratedCode =: GeneratedCode,<y'
new_label =: 3 : 0
    number =. #LabelPositions
    LabelPositions =: LabelPositions,_1
    number
)
mark_label =: 3 : 'LabelPositions =: (#GeneratedCode)y}LabelPositions'
generate_expression =: 3 : 0
    'kind position children value extra typ referent complete' =. y{::Nodes
    select. kind
    case. 'integer';'boolean' do. emit_instruction(<'PUSH'),(<,value),<position
    case. 'variable' do.
        if. 'global'-:node_kind referent do.
            emit_instruction(<'LOADG'),(<,referent{Addresses),<position
        else.
            emit_instruction(<'LOADL'),(<,referent{Slots),<position
        end.
    case. 'array' do.
        generate_expression {.children
        args =. (referent{Addresses),declaration_size referent
        emit_instruction(<'LOADA'),(<args),<position
    case. 'read' do. emit_instruction(<'READ'),(<i.0),<position
    case. 'call' do.
        for_child. children do. generate_expression child end.
        emit_instruction(<'CALL'),(<referent,#children),<position
    case. 'unary' do.
        generate_expression {.children
        op =. 'NOT'
        if. value-:,'-' do. op =. 'NEG' end.
        emit_instruction(<op),(<i.0),<position
    case. 'binary' do.
        if. (<value)e.'&&';'||' do.
            shortcut =. new_label ''
            end =. new_label ''
            generate_expression 0{children
            op =. 'JUMPF'
            if. value-:'||' do. op =. 'JUMPT' end.
            emit_instruction(<op),(<,shortcut),<position
            generate_expression 1{children
            emit_instruction(<'JUMP'),(<,end),<position
            mark_label shortcut
            emit_instruction(<'PUSH'),(<,value-:'||'),<position
            mark_label end
        else.
            generate_expression 0{children
            generate_expression 1{children
            op =. (BinarySymbols i.<value){::BinaryOpcodes
            emit_instruction(<op),(<i.0),<position
        end.
    end.
)
generate_statement =: 3 : 0
    'kind position children value extra typ referent complete' =. y{::Nodes
    select. kind
    case. 'declaration' do.
        where =. declaration_position y
        if. #children do. generate_expression {.children
        else. emit_instruction(<'PUSH'),(<,0x),<where end.
        emit_instruction(<'STOREL'),(<,y{Slots),<where
    case. 'assignment' do.
        'index expression' =. children
        if. index~:_1 do. generate_expression index end.
        generate_expression expression
        if. index~:_1 do.
            args =. (referent{Addresses),declaration_size referent
            emit_instruction(<'STOREA'),(<args),<position
        elseif. 'global'-:node_kind referent do.
            emit_instruction(<'STOREG'),(<,referent{Addresses),<position
        else.
            emit_instruction(<'STOREL'),(<,referent{Slots),<position
        end.
    case. 'call_statement' do.
        generate_expression {.children
        if. -.'void'-:node_type {.children do. emit_instruction(<'POP'),(<i.0),<position end.
    case. 'print' do.
        for_child. children do. generate_expression child end.
        emit_instruction(<'PRINT'),(<,#children),<position
    case. 'if' do.
        alternative =. new_label ''
        end =. new_label ''
        generate_expression 0{children
        emit_instruction(<'JUMPF'),(<,alternative),<position
        generate_statement 1{children
        if. _1=2{children do.
            mark_label alternative
        else.
            emit_instruction(<'JUMP'),(<,end),<position
            mark_label alternative
            generate_statement 2{children
            mark_label end
        end.
    case. 'while' do.
        start =. new_label ''
        end =. new_label ''
        mark_label start
        generate_expression 0{children
        emit_instruction(<'JUMPF'),(<,end),<position
        LoopLabels =: LoopLabels,end,start
        generate_statement 1{children
        LoopLabels =: }:LoopLabels
        emit_instruction(<'JUMP'),(<,start),<position
        mark_label end
    case. 'for' do.
        start =. new_label ''
        update_label =. new_label ''
        end =. new_label ''
        'initial condition update body' =. children
        if. initial~:_1 do. generate_statement initial end.
        mark_label start
        if. condition~:_1 do.
            generate_expression condition
            emit_instruction(<'JUMPF'),(<,end),<position
        end.
        LoopLabels =: LoopLabels,end,update_label
        generate_statement body
        LoopLabels =: }:LoopLabels
        mark_label update_label
        if. update~:_1 do. generate_statement update end.
        emit_instruction(<'JUMP'),(<,start),<position
        mark_label end
    case. 'break';'continue' do.
        label =. (kind-:'continue'){_1{LoopLabels
        emit_instruction(<'JUMP'),(<,label),<position
    case. 'return' do.
        if. #children do.
            generate_expression {.children
            emit_instruction(<'RETV'),(<i.0),<position
        else.
            emit_instruction(<'RET'),(<i.0),<position
        end.
    case. 'block' do.
        for_child. children do. generate_statement child end.
    end.
)
finish_code =: 3 : 0
    result =. 0$a:
    for_instruction. GeneratedCode do.
        'op args position' =. >instruction
        if. (<op)e.JumpOpcodes do. args =. ,({.args){LabelPositions end.
        result =. result,<(<op),(<args),<position
    end.
    result
)
assign_slots =: 3 : 0
    declarations =. i.0
    pending =. ,{.node_children y
    while. #pending do.
        number =. {:pending
        pending =. }:pending
        if. 'declaration'-:node_kind number do. declarations =. declarations,number end.
        pending =. pending,statement_children number
    end.
    keys =. 0 2$0
    for_number. declarations do. keys =. keys,declaration_position number end.
    declarations =. (node_value y),(/:keys){declarations
    for_i. i.#declarations do. Slots =: i(i{declarations)}Slots end.
    declarations
)
new_unit =: 3 : 0
    y,(<0$a:),(<0$a:),(<0),(<0),(<0),<0
)
generate_units =: 3 : 0
    'globals functions' =. y
    Addresses =: Slots =: (#Nodes)$_1
    GlobalSize =: 0
    for_number. globals do.
        Addresses =: GlobalSize number}Addresses
        size =. declaration_size number
        if. size=_1 do. size =. 1 end.
        GlobalSize =: GlobalSize+size
    end.
    GeneratedCode =: 0$a:
    LabelPositions =: i.0
    LoopLabels =: 0 2$0
    for_number. globals do.
        children =. node_children number
        if. #children do.
            generate_expression {.children
            emit_instruction(<'STOREG'),(<,number{Addresses),<declaration_position number
        end.
    end.
    where =. declaration_position MainFunction
    emit_instruction(<'CALL'),(<MainFunction,0),<where
    emit_instruction(<'HALT'),(<i.0),<where
    init =. new_unit(<'<init>'),(<_1),(<i.0),<finish_code ''
    units =. ,<init
    for_function. functions do.
        slots =. assign_slots function
        GeneratedCode =: 0$a:
        LabelPositions =: i.0
        LoopLabels =: 0 2$0
        emit_instruction(<'ENTER'),(<,#slots),<declaration_position function
        body =. {.node_children function
        generate_statement body
        if. 'void'-:declaration_type function do.
            emit_instruction(<'RET'),(<i.0),<node_value body
        end.
        unit =. new_unit(<declaration_name function),(<function),(<slots),<finish_code ''
        units =. units,<unit
    end.
    units
)
