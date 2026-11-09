semantic_fail =: 4 : 'compile_fail(<''semantic''),(<x),<y'
quoted =: 3 : '(39{a.),y,39{a.'
lookup_name =: 3 : 0
    'name position read' =. y
    referent =. _1
    for_scope. |.Scopes do.
        scope =. >scope
        index =. name env_index scope
        if. index<#scope do.
            referent =. 1{::index{::scope
            break.
        end.
    end.
    if. referent=_1 do.
        index =. name env_index GlobalNames
        if. index<#GlobalNames do. referent =. 1{::index{::GlobalNames end.
    end.
    if. referent~:_1 do.
        references =. (referent{::References),position
        References =: (<references)referent}References
        ReadCounts =: ((referent{ReadCounts)+read)referent}ReadCounts
    end.
    referent
)
lookup_variable =: 3 : 0
    'name position indexed read' =. y
    referent =. lookup_name(<name),(<position),<read
    if. referent=_1 do. position semantic_fail 'undeclared identifier ',quoted name end.
    if. 'function'-:node_kind referent do.
        position semantic_fail (quoted name),' is a function, not a variable'
    end.
    array =. ('global'-:node_kind referent)*._1~:declaration_size referent
    if. indexed*.-.array do. position semantic_fail (quoted name),' is not an array' end.
    if. (-.indexed)*.array do. position semantic_fail 'array ',(quoted name),' used without index' end.
    referent
)
check_expression =: 4 : 0
    call_statement =. x
    'kind position children value extra previous referent complete' =. y{::Nodes
    select. kind
    case. 'integer';'read' do. result =. 'int'
    case. 'boolean' do. result =. 'bool'
    case. 'variable';'array' do.
        referent =. lookup_variable(<value),(<position),(<kind-:'array'),<1
        6 set_node(<y),<referent
        if. kind-:'array' do.
            if. -.'int'-:0 check_expression {.children do.
                position semantic_fail 'index of ',(quoted value),' must be int'
            end.
        end.
        result =. declaration_type referent
    case. 'call' do.
        referent =. lookup_name(<value),(<position),<1
        if. referent=_1 do. position semantic_fail 'undeclared function ',quoted value end.
        if. -.'function'-:node_kind referent do.
            position semantic_fail (quoted value),' is not a function'
        end.
        6 set_node(<y),<referent
        calls =. ~.(CurrentFunction{::Calls),referent
        Calls =: (<calls)CurrentFunction}Calls
        parameters =. node_value referent
        if. (#parameters)~:#children do.
            message =. 'wrong number of arguments to ',(quoted value),' (expected ',integer #parameters
            position semantic_fail message,', found ',(integer #children),')'
        end.
        for_i. i.#children do.
            found =. 0 check_expression i{children
            required =. declaration_type i{parameters
            if. -.required-:found do.
                message =. 'argument ',(integer i+1),' of ',(quoted value),' must be ',required
                position semantic_fail message
            end.
        end.
        result =. declaration_type referent
        if. (-.call_statement)*.result-:'void' do.
            position semantic_fail 'void function ',(quoted value),' used as a value'
        end.
    case. 'unary' do.
        result =. 0 check_expression {.children
        required =. 'bool'
        if. value-:,'-' do. required =. 'int' end.
        if. -.result-:required do.
            position semantic_fail 'operator ',(quoted value),' requires ',required,' operand'
        end.
    case. 'binary' do.
        left =. 0 check_expression 0{children
        right =. 0 check_expression 1{children
        arithmetic =. <;._1 ' + - * / %'
        ordered =. <;._1 ' < <= > >='
        if. (<value)e.arithmetic,ordered do.
            if. (-.left-:'int')+.-.right-:'int' do.
                position semantic_fail 'operator ',(quoted value),' requires int operands'
            end.
            result =. 'bool'
            if. (<value)e.arithmetic do. result =. 'int' end.
        elseif. (<value)e.'==';'!=' do.
            if. -.left-:right do.
                position semantic_fail 'operator ',(quoted value),' requires operands of the same type'
            end.
            result =. 'bool'
        else.
            if. (-.left-:'bool')+.-.right-:'bool' do.
                position semantic_fail 'operator ',(quoted value),' requires bool operands'
            end.
            result =. 'bool'
        end.
    end.
    5 set_node(<y),<result
    result
)
constant_initializer =: 3 : 0
    pending =. ,y
    positions =. 0 2$0
    while. #pending do.
        node =. {:pending
        pending =. }:pending
        if. (<node_kind node)e.;:'variable array call read' do.
            positions =. positions,node_position node
        end.
        pending =. pending,expression_children node
    end.
    if. #positions do.
        (({./:positions){positions)semantic_fail 'global initializer must be constant'
    end.
    0 check_expression y
)
add_scope_variable =: 3 : 0
    name =. declaration_name y
    last =. (#Scopes)-1
    scope =. ((<name),<y)env_put last{::Scopes
    Scopes =: (<scope)last}Scopes
)
check_statement =: 4 : 0
    depth =. x
    'kind position children value extra previous referent complete' =. y{::Nodes
    select. kind
    case. 'declaration' do.
        name =. declaration_name y
        where =. declaration_position y
        typ =. declaration_type y
        if. typ-:'void' do. where semantic_fail 'variable ',(quoted name),' cannot have type void' end.
        scope =. _1{::Scopes
        if. (name env_index scope)<#scope do. where semantic_fail 'redeclaration of ',quoted name end.
        if. #children do.
            if. -.typ-:0 check_expression {.children do.
                where semantic_fail 'type mismatch in initialization of ',quoted name
            end.
        end.
        Variables =: Variables,y
        add_scope_variable y
    case. 'assignment' do.
        'index expression' =. children
        referent =. lookup_variable(<value),(<position),(<index~:_1),<0
        6 set_node(<y),<referent
        if. index~:_1 do.
            if. -.'int'-:0 check_expression index do.
                position semantic_fail 'index of ',(quoted value),' must be int'
            end.
        end.
        if. -.(declaration_type referent)-:0 check_expression expression do.
            position semantic_fail 'type mismatch in assignment to ',quoted value
        end.
    case. 'call_statement' do. 1 check_expression {.children
    case. 'if';'while' do.
        if. -.'bool'-:0 check_expression 0{children do.
            position semantic_fail 'condition of ',(quoted kind),' must be bool'
        end.
        if. kind-:'if' do.
            depth check_statement 1{children
            if. _1~:2{children do. depth check_statement 2{children end.
        else.
            (depth+1)check_statement 1{children
        end.
    case. 'for' do.
        Scopes =: Scopes,<0$a:
        'initial condition update body' =. children
        if. initial~:_1 do. depth check_statement initial end.
        if. condition~:_1 do.
            if. -.'bool'-:0 check_expression condition do.
                position semantic_fail 'condition of ''for'' must be bool'
            end.
        end.
        if. update~:_1 do. depth check_statement update end.
        (depth+1)check_statement body
        Scopes =: }:Scopes
    case. 'break';'continue' do.
        if. depth=0 do. position semantic_fail (quoted kind),' outside loop' end.
    case. 'return' do.
        typ =. declaration_type CurrentFunction
        name =. declaration_name CurrentFunction
        if. typ-:'void' do.
            if. #children do. position semantic_fail 'function ',(quoted name),' must not return a value' end.
        else.
            if. 0=#children do. position semantic_fail 'function ',(quoted name),' must return a value' end.
            if. -.typ-:0 check_expression {.children do.
                position semantic_fail 'return value of ',(quoted name),' must be ',typ
            end.
        end.
    case. 'print' do.
        for_i. i.#children do.
            if. -.'int'-:0 check_expression i{children do.
                position semantic_fail 'argument ',(integer i+1),' of ''print'' must be int'
            end.
        end.
    case. 'block' do.
        Scopes =: Scopes,<0$a:
        for_child. children do. depth check_statement child end.
        Scopes =: }:Scopes
    end.
)
can_complete =: 3 : 0
    cached =. 7{::y{::Nodes
    if. cached~:_1 do. cached return. end.
    children =. node_children y
    kind =. node_kind y
    result =. 1
    if. (<kind)e.;:'return break continue' do.
        result =. 0
    elseif. kind-:'block' do.
        for_child. children do. result =. result*.can_complete child end.
    elseif. kind-:'if' do.
        if. _1~:2{children do.
            result =. (can_complete 1{children)+.can_complete 2{children
        end.
    end.
    7 set_node(<y),<result
    result
)
analyze_program =: 3 : 0
    declarations =. y
    GlobalNames =: 0$a:
    Functions =: Variables =: i.0
    References =: (#Nodes)$<0 2$0
    ReadCounts =: (#Nodes)$0
    Calls =: (#Nodes)$<i.0
    Scopes =: 0$a:
    CurrentFunction =: _1
    for_number. declarations do.
        kind =. node_kind number
        name =. declaration_name number
        where =. declaration_position number
        typ =. declaration_type number
        children =. node_children number
        if. kind-:'global' do.
            size =. declaration_size number
            if. size~:_1 do.
                if. -.typ-:'int' do. where semantic_fail 'array ',(quoted name),' must have element type int' end.
                if. size=0 do.
                    size_position =. 4{::node_extra number
                    size_position semantic_fail 'array ',(quoted name),' must have a positive size'
                end.
            elseif. typ-:'void' do.
                where semantic_fail 'variable ',(quoted name),' cannot have type void'
            end.
        end.
        if. (name env_index GlobalNames)<#GlobalNames do.
            where semantic_fail 'redeclaration of ',quoted name
        end.
        if. kind-:'global' do.
            if. #children do.
                if. -.typ-:constant_initializer {.children do.
                    where semantic_fail 'type mismatch in initialization of ',quoted name
                end.
            end.
            Variables =: Variables,number
        else.
            names =. 0$a:
            for_parameter. node_value number do.
                parameter_name =. declaration_name parameter
                parameter_position =. declaration_position parameter
                if. 'void'-:declaration_type parameter do.
                    parameter_position semantic_fail 'parameter ',(quoted parameter_name),' cannot have type void'
                end.
                if. (<parameter_name)e.names do.
                    parameter_position semantic_fail 'redeclaration of ',quoted parameter_name
                end.
                names =. names,<parameter_name
                Variables =: Variables,parameter
            end.
            Functions =: Functions,number
        end.
        GlobalNames =: ((<name),<number)env_put GlobalNames
    end.
    index =. 'main'env_index GlobalNames
    MainFunction =: _1
    if. index<#GlobalNames do. MainFunction =: 1{::index{::GlobalNames end.
    if. MainFunction~:_1 do.
        if. -.'function'-:node_kind MainFunction do. MainFunction =: _1 end.
    end.
    if. MainFunction=_1 do. EndPosition semantic_fail 'no main function' end.
    if. (-.'void'-:declaration_type MainFunction)+.0<#node_value MainFunction do.
        (declaration_position MainFunction)semantic_fail 'main must be declared as ''void main()'''
    end.
    for_function. Functions do.
        CurrentFunction =: function
        scope =. 0$a:
        for_parameter. node_value function do.
            scope =. ((<declaration_name parameter),<parameter)env_put scope
        end.
        Scopes =: ,<scope
        body =. {.node_children function
        for_statement. node_children body do. 0 check_statement statement end.
        if. (-.'void'-:declaration_type function)*.can_complete body do.
            (declaration_position function)semantic_fail 'missing return in function ',quoted declaration_name function
        end.
    end.
)
