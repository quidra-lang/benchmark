ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'parser.ijs'
load SourceDirectory,'semantic.ijs'
load SourceDirectory,'codegen.ijs'
load SourceDirectory,'vm.ijs'

RuleNames =: <;._1 ' const-jump not-compare not-jump invert-branch thread jump-next unreachable'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
split_words =: 3 : '<;._1 '' '',y'
env_index =: 4 : 0
    for_i. i.#y do.
        if. x-:0{::i{::y do. i return. end.
    end.
    #y
)
env_put =: 4 : 0
    index =. (0{::x)env_index y
    if. index=#y do. y,<x else. (<x)index}y end.
)
compile_fail =: 3 : 0
    CompileError =: y
    13!:8 3
)
format_position =: 3 : '(integer 0{y),'':'',integer 1{y'
position_display =: 3 : 0
    'row column' =. y
    (<'  ',(row-1){::AllSourceLines),<((column+1)$' '),'^'
)
read_programs =: 3 : 0
    AllSourceLines =: <;._2(1!:1 <'input/program.src')
    Programs =: 0$a:
    name =. ''
    lines =. 0$a:
    for_i. i.#AllSourceLines do.
        text =. i{::AllSourceLines
        if. '#program '-:9{.text do.
            if. #name do. Programs =: Programs,<(<name),(<lines),<0$0x end.
            name =. 9}.text
            lines =. 0$a:
        else.
            lines =. lines,<(<i+1),<text
        end.
    end.
    Programs =: Programs,<(<name),(<lines),<0$0x
    names =. 0$a:
    for_program. Programs do. names =. names,<0{::>program end.
    index =. _1
    for_line. <;._2(1!:1 <'input/input.txt') do.
        text =. >line
        if. '#input '-:7{.text do.
            index =. names i.<7}.text
        else.
            fields =. split_words text
            values =. 0$0x
            for_field. fields do.
                field =. >field
                field =. '_'(I.field='-')}field
                values =. values,".field,'x'
            end.
            program =. index{::Programs
            program =. (<(2{::program),values)2}program
            Programs =: (<program)index}Programs
        end.
    end.
)
collect_warnings =: 3 : 0
    warnings =. 0$a:
    for_variable. Variables do.
        if. 0=variable{ReadCounts do.
            role =. 'variable'
            if. 'parameter'-:node_kind variable do. role =. 'parameter' end.
            message =. 'unused ',role,' ',quoted declaration_name variable
            warnings =. warnings,<(<declaration_position variable),<message
        end.
    end.
    for_function. Functions do.
        pending =. ,{.node_children function
        while. #pending do.
            number =. {:pending
            pending =. }:pending
            if. 'block'-:node_kind number do.
                statements =. node_children number
                for_i. i.0>.(#statements)-1 do.
                    if. -.can_complete i{statements do.
                        where =. node_position(i+1){statements
                        warnings =. warnings,<(<where),<'unreachable statement'
                        break.
                    end.
                end.
            end.
            pending =. pending,statement_children number
        end.
    end.
    Reachable =: i.0
    pending =. ,MainFunction
    while. #pending do.
        function =. {:pending
        pending =. }:pending
        if. function e.Reachable do. continue. end.
        Reachable =: Reachable,function
        pending =. pending,function{::Calls
    end.
    for_function. Functions do.
        if. -.function e.Reachable do.
            message =. 'function ',(quoted declaration_name function),' is never called'
            warnings =. warnings,<(<declaration_position function),<message
        end.
    end.
    keys =. 0 2$0
    for_warning. warnings do. keys =. keys,0{::>warning end.
    (/:keys){warnings
)
is_recursive =: 3 : 0
    visited =. i.0
    pending =. y{::Calls
    while. #pending do.
        number =. {:pending
        pending =. }:pending
        if. number=y do. 1 return. end.
        if. -.number e.visited do.
            visited =. visited,number
            pending =. pending,number{::Calls
        end.
    end.
    0
)
is_literal =: 3 : '(<node_kind y)e.''integer'';''boolean'''
literal_is =: 4 : 0
    'kind value' =. x
    if. -.kind-:node_kind y do. 0 else. value=node_value y end.
)
folded_literal =: 4 : 0
    FoldCount =: FoldCount+1
    typ =. node_type x
    kind =. 'integer'
    if. typ-:'bool' do. kind =. 'boolean' end.
    number =. kind new_node(<node_position x),(<i.0),(<y),<''
    5 set_node(<number),<typ
    number
)
fold_identity =: 3 : 0
    FoldCount =: FoldCount+1
    y
)
fold_expression =: 3 : 0
    number =. y
    kind =. node_kind number
    children =. node_children number
    value =. node_value number
    if. kind-:'unary' do.
        operand =. fold_expression {.children
        2 set_node(<number),<,operand
        if. is_literal operand do.
            op =. 'NOT'
            if. value-:,'-' do. op =. 'NEG' end.
            'result error' =. calculate(<op),(<node_value operand),<0
            if. 0=#error do. number folded_literal result return. end.
        end.
    elseif. kind-:'binary' do.
        left =. fold_expression 0{children
        right =. fold_expression 1{children
        2 set_node(<number),<left,right
        if. (is_literal left)*.is_literal right do.
            a =. node_value left
            b =. node_value right
            error =. ''
            if. value-:'&&' do. result =. (a~:0)*.b~:0
            elseif. value-:'||' do. result =. (a~:0)+.b~:0
            else.
                op =. (BinarySymbols i.<value){::BinaryOpcodes
                'result error' =. calculate(<op),(<a),<b
            end.
            if. 0=#error do. number folded_literal result return. end.
        end.
        left_false =. ('boolean';0)literal_is left
        left_true =. ('boolean';1)literal_is left
        right_false =. ('boolean';0)literal_is right
        right_true =. ('boolean';1)literal_is right
        if. (value-:'&&')*.left_false do. number folded_literal 0 return. end.
        if. (value-:'||')*.left_true do. number folded_literal 1 return. end.
        if. (value-:'&&')*.left_true do. fold_identity right return. end.
        if. (value-:'||')*.left_false do. fold_identity right return. end.
        if. (value-:,'+')*.('integer';0)literal_is left do. fold_identity right return. end.
        if. (value-:,'*')*.('integer';1)literal_is left do. fold_identity right return. end.
        if. ((<value)e.(<,'+'),<,'-')*.('integer';0)literal_is right do. fold_identity left return. end.
        if. ((<value)e.(<,'*'),<,'/')*.('integer';1)literal_is right do. fold_identity left return. end.
        if. (value-:'&&')*.right_true do. fold_identity left return. end.
        if. (value-:'||')*.right_false do. fold_identity left return. end.
    elseif. (<kind)e.'array';'call' do.
        updated =. i.0
        for_child. children do. updated =. updated,fold_expression child end.
        2 set_node(<number),<updated
    end.
    number
)
fold_statement =: 3 : 0
    number =. y
    kind =. node_kind number
    children =. node_children number
    if. (<kind)e.'declaration';'return';'call_statement';'print' do.
        updated =. i.0
        for_child. children do. updated =. updated,fold_expression child end.
        2 set_node(<number),<updated
    elseif. kind-:'assignment' do.
        'index expression' =. children
        if. index~:_1 do. index =. fold_expression index end.
        expression =. fold_expression expression
        2 set_node(<number),<index,expression
    elseif. kind-:'block' do.
        updated =. i.0
        for_child. children do. updated =. updated,fold_statement child end.
        2 set_node(<number),<updated
    elseif. kind-:'if' do.
        'condition yes no' =. children
        condition =. fold_expression condition
        if. 'boolean'-:node_kind condition do.
            selected =. no
            if. node_value condition do. selected =. yes end.
            if. selected~:_1 do. replacement =. fold_statement selected
            else. replacement =. 'empty'new_node(<node_position number),(<i.0),(<''),<'' end.
            FoldCount =: FoldCount+1
            replacement return.
        end.
        yes =. fold_statement yes
        if. no~:_1 do. no =. fold_statement no end.
        2 set_node(<number),<condition,yes,no
    elseif. kind-:'while' do.
        'condition body' =. children
        condition =. fold_expression condition
        if. ('boolean';0)literal_is condition do.
            FoldCount =: FoldCount+1
            'empty'new_node(<node_position number),(<i.0),(<''),<'' return.
        end.
        body =. fold_statement body
        2 set_node(<number),<condition,body
    elseif. kind-:'for' do.
        'initial condition update body' =. children
        if. initial~:_1 do. initial =. fold_statement initial end.
        if. condition~:_1 do. condition =. fold_expression condition end.
        if. update~:_1 do. update =. fold_statement update end.
        body =. fold_statement body
        2 set_node(<number),<initial,condition,update,body
    end.
    number
)
inverse_jump =: 3 : '(ConditionalOpcodes i.<y){::''JUMPT'';''JUMPF'''
jumps_on =: 4 : '(y=0)=x-:''JUMPF'''
replace_instruction =: 4 : 'WorkingCode =: (<y)x}WorkingCode'
delete_instruction =: 3 : 0
    WorkingCode =: (y~:i.#WorkingCode)#WorkingCode
    for_i. i.#WorkingCode do.
        'op args position' =. i{::WorkingCode
        if. (<op)e.JumpOpcodes do.
            if. ({.args)>y do.
                i replace_instruction(<op),(<args-1),<position
            end.
        end.
    end.
)
rewrite_at =: 3 : 0
    index =. y
    n =. #WorkingCode
    'op args position' =. index{::WorkingCode
    free =. 0
    if. (index+1)<n do.
        'next_op next_args next_position' =. (index+1){::WorkingCode
        free =. -.(index+1)e.WorkingTargets
    end.
    if. free do.
        if. (op-:'PUSH')*.(<next_op)e.ConditionalOpcodes do.
            if. next_op jumps_on {.args do.
                index replace_instruction(<'JUMP'),(<next_args),<next_position
                delete_instruction index+1
            else.
                delete_instruction index+1
                delete_instruction index
            end.
            1 return.
        elseif. ((<op)e.CompareOpcodes)*.next_op-:'NOT' do.
            new_op =. (CompareOpcodes i.<op){::NegatedOpcodes
            index replace_instruction(<new_op),(<args),<position
            delete_instruction index+1
            2 return.
        elseif. (op-:'NOT')*.(<next_op)e.ConditionalOpcodes do.
            index replace_instruction(<inverse_jump next_op),(<next_args),<next_position
            delete_instruction index+1
            3 return.
        elseif. ((<op)e.ConditionalOpcodes)*.(next_op-:'JUMP') do.
            if. ({.args)=index+2 do.
                index replace_instruction(<inverse_jump op),(<next_args),<position
                delete_instruction index+1
                4 return.
            end.
        end.
    end.
    if. (<op)e.JumpOpcodes do.
        target =. {.args
        changed =. _1
        if. target<n do.
            'destination destination_args destination_position' =. target{::WorkingCode
            if. destination-:'JUMP' do.
                changed =. {.destination_args
            elseif. (destination-:'PUSH')*.(target+1)<n do.
                'following following_args following_position' =. (target+1){::WorkingCode
                if. (<following)e.ConditionalOpcodes do.
                    if. following jumps_on {.destination_args do. changed =. {.following_args
                    else. changed =. target+2 end.
                end.
            end.
        end.
        if. (changed~:_1)*.changed~:target do.
            index replace_instruction(<op),(<,changed),<position
            5 return.
        end.
        if. target=index+1 do.
            if. op-:'JUMP' do. delete_instruction index
            else. index replace_instruction(<'POP'),(<i.0),<position end.
            6 return.
        end.
    end.
    if. free*.(<op)e.TransferOpcodes do.
        delete_instruction index+1
        7 return.
    end.
    0
)
optimize_code =: 3 : 0
    WorkingCode =: y
    counts =. 7$0
    while. 1 do.
        WorkingTargets =: i.0
        for_instruction. WorkingCode do.
            'op args position' =. >instruction
            if. (<op)e.JumpOpcodes do. WorkingTargets =: WorkingTargets,{.args end.
        end.
        applied =. 0
        for_i. i.#WorkingCode do.
            rule =. rewrite_at i
            if. rule do.
                counts =. (1+(rule-1){counts)(rule-1)}counts
                applied =. 1
                break.
            end.
        end.
        if. -.applied do. break. end.
    end.
    (<WorkingCode),<counts
)

successors =: 4 : 0
    code =. x
    'op args position' =. y{::code
    result =. i.0
    if. (-.(<op)e.TransferOpcodes)*.(y+1)<#code do. result =. ,y+1 end.
    if. (<op)e.JumpOpcodes do.
        target =. {.args
        if. (target<#code)*.-.target e.result do. result =. result,target end.
    end.
    result
)
stack_effect =: 3 : 0
    'op args position' =. y
    if. (<op)e.;:'PUSH LOADG LOADL READ' do. 1 return. end.
    if. (<op)e.;:'POP STOREG STOREL JUMPF JUMPT RETV ADD SUB MUL DIV MOD LT LE GT GE EQ NE' do.
        _1 return.
    end.
    if. op-:'STOREA' do. _2 return. end.
    if. op-:'CALL' do.
        result =. -(1{args)
        result+-.'void'-:declaration_type {.args return.
    end.
    if. op-:'PRINT' do. -{.args return. end.
    0
)
analyze_flow =: 3 : 0
    code =. y
    n =. #code
    leaders =. ,0
    for_i. i.n do.
        'op args position' =. i{::code
        if. (<op)e.JumpOpcodes do.
            if. ({.args)<n do. leaders =. leaders,{.args end.
        end.
        if. (<op)e.JumpOpcodes,TransferOpcodes do.
            if. (i+1)<n do. leaders =. leaders,i+1 end.
        end.
    end.
    leaders =. /:~~.leaders
    blocks =. 0$a:
    for_i. i.#leaders do.
        first =. i{leaders
        last =. n-1
        if. (i+1)<#leaders do. last =. ((i+1){leaders)-1 end.
        following =. leaders i.code successors last
        blocks =. blocks,<(<first),(<last),<following
    end.
    depths =. n$_1
    depths =. 0 0}depths
    pending =. ,0
    maximum =. 0
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        after =. (index{depths)+stack_effect index{::code
        maximum =. maximum>.after
        for_target. code successors index do.
            if. _1=target{depths do.
                depths =. after target}depths
                pending =. pending,target
            end.
        end.
    end.
    (<blocks),<maximum
)
set_unit =: 4 : 0
    'number value' =. y
    unit =. number{::Units
    Units =: (<(<value)x}unit)number}Units
)
link_units =: 3 : 0
    field =. y
    addresses =. i.0
    functions =. i.0
    offset =. 0
    for_i. i.#Units do.
        unit =. i{::Units
        addresses =. addresses,offset
        functions =. functions,1{::unit
        (field+5)set_unit(<i),<offset
        offset =. offset+#field{::unit
    end.
    code =. 0$a:
    owners =. i.0
    starts =. offset$_1
    for_i. i.#Units do.
        unit =. i{::Units
        start =. i{addresses
        starts =. i start}starts
        for_instruction. field{::unit do.
            'op args position' =. >instruction
            if. (<op)e.JumpOpcodes do.
                args =. start+args
            elseif. op-:'CALL' do.
                target =. (functions i.{.args){addresses
                args =. target,1{args
            end.
            code =. code,<(<op),(<args),<position
            owners =. owners,i
        end.
    end.
    (<code),(<owners),<starts
)
instruction_text =: 3 : 0
    'op args position' =. y
    text =. op
    if. #args do. text =. text,' ',' 'join integer&.>args end.
    text
)
listing =: 3 : 0
    lines =. 0$a:
    if. #GlobalVariables do.
        lines =. <'globals:'
        for_number. GlobalVariables do.
            typ =. declaration_type number
            size =. declaration_size number
            if. size~:_1 do. typ =. 'int[',(integer size),']' end.
            text =. '  ',(integer number{Addresses),' ',(declaration_name number),' ',typ
            lines =. lines,<text
        end.
    else.
        lines =. <'globals: none'
    end.
    lines =. lines,<'functions:'
    for_unit. Units do.
        'name function slots before after blocks depth recursive old_start new_start' =. >unit
        signature =. ''
        callees =. 'main'
        if. function~:_1 do.
            types =. 0$a:
            for_parameter. node_value function do. types =. types,<declaration_type parameter end.
            signature =. ' ',(declaration_type function),'(',(','join types),')'
            called_names =. 0$a:
            for_callee. function{::Calls do. called_names =. called_names,<declaration_name callee end.
            callees =. ,'-'
            if. #called_names do. callees =. ','join /:~called_names end.
        end.
        text =. '  ',name,signature,' address=',(integer old_start),'->',integer new_start
        text =. text,' size=',(integer #before),'->',(integer #after),' slots=',integer #slots
        text =. text,' stack=',(integer depth),' blocks=',(integer #blocks),' calls=',callees
        if. recursive do. text =. text,' recursive' end.
        lines =. lines,<text
        for_i. i.#slots do.
            number =. i{slots
            lines =. lines,<'    slot ',(integer i),' ',(declaration_name number),' ',declaration_type number
        end.
    end.
    lines =. lines,<'references:'
    for_number. GlobalVariables,Functions do.
        used =. /:~~.0{"1 number{::References
        text =. ,'-'
        if. #used do. text =. ' 'join integer&.>used end.
        where =. 0{declaration_position number
        lines =. lines,<'  ',(declaration_name number),' defined ',(integer where),' used ',text
    end.
    for_version. i.2 do.
        code =. BeforeCode
        field =. 3
        label =. 'before'
        if. version do.
            code =. AfterCode
            field =. 4
            label =. 'after'
        end.
        lines =. lines,<label,' peephole: ',(integer #code),' instructions'
        for_unit. Units do.
            unit =. >unit
            lines =. lines,<(0{::unit),':'
            start =. (field+5){::unit
            for_pc. start+i.#field{::unit do.
                address =. integer pc
                lines =. lines,<((5-#address)$' '),address,'  ',instruction_text pc{::code
            end.
        end.
    end.
    lines =. lines,<'control flow:'
    for_unit. Units do.
        unit =. >unit
        name =. 0{::unit
        blocks =. 5{::unit
        start =. 9{::unit
        lines =. lines,<'  ',name
        for_i. i.#blocks do.
            'first last following' =. i{::blocks
            text =. '    B',(integer i),' ',(integer start+first),'-',integer start+last
            if. #following do.
                names =. 0$a:
                for_target. following do. names =. names,<'B',integer target end.
                text =. text,' -> ',' 'join names
            end.
            lines =. lines,<text
        end.
    end.
    lines
)
execution_diagnostics =: 3 : 0
    'output error error_pc frames executed counts calls pairs max_stack max_depth' =. MainRun
    if. 0=#error do. <'status: ok' return. end.
    instruction =. error_pc{::AfterCode
    where =. 2{::instruction
    unit =. error_pc{AfterOwners
    name =. 0{::unit{::Units
    text =. 'runtime error ',(format_position where),': ',error,' in ',name
    lines =. (<text),position_display where
    callers =. |.}.frames
    for_frame. (5<.#callers){.callers do.
        pc =. (1{::>frame)-1
        name =. 0{::(pc{AfterOwners){::Units
        where =. 2{::pc{::AfterCode
        lines =. lines,<'  called from ',name,' at ',format_position where
    end.
    if. (#callers)>5 do. lines =. lines,<'  ... ',(integer(#callers)-5),' more' end.
    lines,<'status: runtime error'
)
program_statistics =: 3 : 0
    'output error error_pc frames executed counts calls pairs max_stack max_depth' =. MainRun
    before_output =. 0{::ComparisonRun
    before_error =. 1{::ComparisonRun
    same =. (output-:before_output)*.error-:before_error
    lines =. <'code: ',(integer #BeforeCode),' -> ',integer #AfterCode
    lines =. lines,(<'folds: ',integer FoldCount),<'peephole: ',integer +/PeepholeCounts
    for_i. i.7 do. lines =. lines,<'  ',(i{::RuleNames),' ',integer i{PeepholeCounts end.
    lines =. lines,<'executed: ',integer executed
    lines =. lines,<'executed before peephole: ',integer 4{::ComparisonRun
    lines =. lines,<'behaviour: ',same{::'different';'same'
    lines =. lines,(<'max call depth: ',integer max_depth),<'max stack: ',integer max_stack
    op_names =. 0$a:
    unit_names =. 0$a:
    for_instruction. AfterCode do. op_names =. op_names,0{>instruction end.
    for_unit. Units do. unit_names =. unit_names,0{>unit end.
    distinct_ops =. /:~~.op_names
    op_counts =. i.0
    for_op. distinct_ops do. op_counts =. op_counts,+/counts#~op_names=op end.
    unit_counts =. (#Units)$0
    line_numbers =. i.0
    for_i. i.#AfterCode do.
        owner =. i{AfterOwners
        unit_counts =. ((owner{unit_counts)+i{counts)owner}unit_counts
        line_numbers =. line_numbers,0{2{::i{::AfterCode
    end.
    lines =. lines,<'opcodes:'
    for_i. \:op_counts do.
        if. i{op_counts do.
            lines =. lines,<'  ',(i{::distinct_ops),' ',integer i{op_counts
        end.
    end.
    order =. /:unit_names
    order =. order#~order~:0
    order =. (\:order{unit_counts){order
    lines =. lines,<'functions:'
    for_i. order do.
        text =. '  ',(i{::unit_names),' calls=',(integer i{calls),' executed=',integer i{unit_counts
        lines =. lines,<text
    end.
    pair_rows =. 0 3$0
    alphabetical =. /:unit_names
    for_caller. alphabetical do.
        for_callee. alphabetical do.
            count =. (<caller,callee){pairs
            if. count do. pair_rows =. pair_rows,caller,callee,count end.
        end.
    end.
    lines =. lines,<'calls:'
    order =. \:2{"1 pair_rows
    for_i. order do.
        'caller callee count' =. i{pair_rows
        lines =. lines,<'  ',(caller{::unit_names),' -> ',(callee{::unit_names),' ',integer count
    end.
    distinct_lines =. /:~~.line_numbers
    line_counts =. i.0
    for_number. distinct_lines do. line_counts =. line_counts,+/counts#~line_numbers=number end.
    line_order =. \:line_counts
    line_order =. line_order#~(line_order{line_counts)>0
    lines =. lines,<'hot lines:'
    for_i. (5<.#line_order){.line_order do.
        lines =. lines,<'  line ',(integer i{distinct_lines),': ',integer i{line_counts
    end.
    lines =. lines,<'coverage: ',(integer #line_order),' of ',(integer #distinct_lines),' lines'
    unexecuted =. distinct_lines#~line_counts=0
    text =. 'none'
    if. #unexecuted do. text =. ' 'join integer&.>unexecuted end.
    lines =. lines,<'not executed: ',text
    lines =. lines,<'hot spots:'
    order =. \:counts
    order =. order#~(order{counts)>0
    for_pc. (5<.#order){.order do.
        text =. '  pc=',(integer pc),' count=',(integer pc{counts),' ',instruction_text pc{::AfterCode
        lines =. lines,<text
    end.
    lines
)
summary_table =: 3 : 0
    rows =. ( <'program';'status';'code';'executed';'output'),y
    widths =. 5$0
    for_row. rows do.
        row =. >row
        for_j. i.5 do. widths =. ((j{widths)>.#j{::row)j}widths end.
    end.
    lines =. 0$a:
    for_row. rows do.
        row =. >row
        fields =. 0$a:
        for_j. i.5 do.
            text =. j{::row
            padding =. ((j{widths)-#text)$' '
            if. j<2 do. text =. text,padding else. text =. padding,text end.
            fields =. fields,<text
        end.
        lines =. lines,<'  ','  'join fields
    end.
    lines
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_programs ''
    listing_output =. output =. diagnostics =. stats =. table_rows =. 0$a:
    totals =. 7$0
    rule_totals =. 7$0
    for_program. Programs do.
        'name source inputs' =. >program
        header =. '== program ',name,' =='
        listing_output =. listing_output,<header
        output =. output,<header
        diagnostics =. diagnostics,<header
        stats =. stats,<header
        Nodes =: 0$a:
        CompileError =: 0$a:
        try.
            Tokens =: lex_source source
            EndPosition =: 2{::_1{::Tokens
            ParsePosition =: 0
            declarations =. read_program ''
            analyze_program declarations
        catch.
            if. 0=#CompileError do. 13!:8 3 end.
        end.
        if. #CompileError do.
            'kind where message' =. CompileError
            index =. 1+('lexical';'syntax';'semantic')i.<kind
            totals =. (1+index{totals)index}totals
            text =. kind,' error ',(format_position where),': ',message
            diagnostics =. diagnostics,(<text),(position_display where),<'status: compile error'
            listing_output =. listing_output,<'not compiled'
            stats =. stats,<'not compiled'
            table_rows =. table_rows,<name;(kind,' error');'-';'-';'-'
            continue.
        end.
        totals =. (1+0{totals)0}totals
        warnings =. collect_warnings ''
        for_warning. warnings do.
            'where message' =. >warning
            diagnostics =. diagnostics,<'warning ',(format_position where),': ',message
        end.
        GlobalVariables =: i.0
        for_number. declarations do.
            if. 'global'-:node_kind number do. GlobalVariables =: GlobalVariables,number end.
        end.
        kept_functions =. Functions#~Functions e.Reachable
        FoldCount =: 0
        for_number. GlobalVariables do.
            children =. node_children number
            if. #children do. 2 set_node(<number),<,fold_expression {.children end.
        end.
        for_function. kept_functions do.
            body =. fold_statement {.node_children function
            2 set_node(<function),<,body
        end.
        Units =: generate_units(<GlobalVariables),<kept_functions
        PeepholeCounts =: 7$0
        for_i. i.#Units do.
            unit =. i{::Units
            'after counts' =. optimize_code 3{::unit
            PeepholeCounts =: PeepholeCounts+counts
            4 set_unit(<i),<after
            'blocks depth' =. analyze_flow after
            5 set_unit(<i),<blocks
            6 set_unit(<i),<depth
            function =. 1{::unit
            recursive =. 0
            if. function~:_1 do. recursive =. is_recursive function end.
            7 set_unit(<i),<recursive
        end.
        'BeforeCode BeforeOwners BeforeStarts' =: link_units 3
        'AfterCode AfterOwners AfterStarts' =: link_units 4
        MainRun =: run_vm(<AfterCode),(<AfterOwners),(<AfterStarts),(<GlobalSize),<inputs
        ComparisonRun =: run_vm(<BeforeCode),(<BeforeOwners),(<BeforeStarts),(<GlobalSize),<inputs
        listing_output =. listing_output,listing ''
        output =. output,0{::MainRun
        diagnostics =. diagnostics,execution_diagnostics ''
        stats =. stats,program_statistics ''
        status =. 'ok'
        if. #1{::MainRun do.
            status =. 'runtime error'
            totals =. (1+4{totals)4}totals
        end.
        totals =. ((5{totals)+FoldCount)5}totals
        totals =. ((6{totals)+4{::MainRun)6}totals
        rule_totals =. rule_totals+PeepholeCounts
        table_rows =. table_rows,<name;status;(integer #AfterCode);(integer 4{::MainRun);integer #0{::MainRun
    end.
    stats =. stats,<'== summary =='
    stats =. stats,(<'programs: ',integer #Programs),<'compiled: ',integer 0{totals
    text =. 'compile errors: lexical ',(integer 1{totals),' syntax ',(integer 2{totals),' semantic ',integer 3{totals
    stats =. stats,<text
    stats =. stats,(<'runtime errors: ',integer 4{totals),(<'folds: ',integer 5{totals),<'peephole: ',integer +/rule_totals
    for_i. i.7 do. stats =. stats,<'  ',(i{::RuleNames),' ',integer i{rule_totals end.
    stats =. stats,<'executed: ',integer 6{totals
    stats =. stats,summary_table table_rows
    try.
        1!:5 <'output'
    catch.
    end.
    'listing.txt'write_lines listing_output
    'output.txt'write_lines output
    'diagnostics.txt'write_lines diagnostics
    'stats.txt'write_lines stats
)
run ''
