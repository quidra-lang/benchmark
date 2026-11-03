inference_fail =: 3 : 0
    TypeError =: y
    13!:8 3
)
check_type =: 3 : 0
    'expected found position' =. y
    failure =. unify_types expected,found,0
    if. #failure do.
        details =. (<expected),(<found),<failure
        inference_fail(<position),(<'check'),<details
    end.
)
operator_types =: 3 : 0
    if. (<y)e.(<;._1 ' + - * / mod') do. IntType,IntType,IntType return. end.
    if. y-:,'^' do. StringType,StringType,StringType return. end.
    if. (<y)e.'&&';'||' do. BoolType,BoolType,BoolType return. end.
    variable =. fresh_type ''
    if. y-:'::' do.
        sequence =. 'list'new_type,variable
        variable,sequence,sequence
    else.
        variable,variable,BoolType
    end.
)
infer_expression =: 4 : 0
    environment =. x
    'kind position children value previous' =. y{::Nodes
    select. kind
    case. 'integer' do. result =. IntType
    case. 'boolean' do. result =. BoolType
    case. 'string' do. result =. StringType
    case. 'name' do.
        index =. value env_index environment
        if. index=#environment do.
            names =. env_names environment
            inference_fail(<position),(<'unbound'),<(<value),<names
        end.
        result =. instantiate_type 1{::index{::environment
    case. 'fun' do.
        argument =. fresh_type ''
        inner =. environment
        name =. 1{::value
        if. -.name-:,'_' do.
            scheme =. (<argument),<i.0
            inner =. ((<name),<scheme)env_put inner
        end.
        body =. inner infer_expression {.children
        result =. 'function'new_type argument,body
    case. 'apply' do.
        function =. resolve_type environment infer_expression 0{children
        if. 'variable'-:type_kind function do.
            argument =. fresh_type ''
            result =. fresh_type ''
            function bind_type 'function'new_type argument,result
        elseif. 'function'-:type_kind function do.
            'argument result' =. type_children function
        else.
            inference_fail(<node_position 0{children),(<'not_function'),<,function
        end.
        found =. environment infer_expression 1{children
        check_type(<argument),(<found),<node_position 1{children
    case. 'binary' do.
        'first second result' =. operator_types 1{::value
        found =. environment infer_expression 0{children
        check_type(<first),(<found),<node_position 0{children
        found =. environment infer_expression 1{children
        check_type(<second),(<found),<node_position 1{children
    case. 'negate' do.
        found =. environment infer_expression 0{children
        check_type(<IntType),(<found),<node_position 0{children
        result =. IntType
    case. 'if' do.
        found =. environment infer_expression 0{children
        check_type(<BoolType),(<found),<node_position 0{children
        result =. environment infer_expression 1{children
        found =. environment infer_expression 2{children
        check_type(<result),(<found),<node_position 2{children
    case. 'pair' do.
        first =. environment infer_expression 0{children
        second =. environment infer_expression 1{children
        result =. 'pair'new_type first,second
    case. 'list' do.
        element =. fresh_type ''
        for_child. children do.
            found =. environment infer_expression child
            check_type(<element),(<found),<node_position child
        end.
        result =. 'list'new_type,element
    case. 'match' do.
        matched =. environment infer_expression 0{children
        result =. fresh_type ''
        for_arm. value do.
            'pattern expression' =. arm
            PatternEnvironment =: 0$a:
            found =. infer_pattern pattern
            check_type(<matched),(<found),<node_position pattern
            inner =. environment
            for_record. PatternEnvironment do. inner =. (>record)env_put inner end.
            found =. inner infer_expression expression
            check_type(<result),(<found),<node_position expression
        end.
    case. 'let' do.
        inner =. infer_group(<value),(<environment),<1
        result =. inner infer_expression 0{children
    end.
    node =. y{::Nodes
    Nodes =: (<(<result)4}node)y}Nodes
    result
)
infer_pattern =: 3 : 0
    'kind position children value previous' =. y{::Nodes
    select. kind
    case. 'wildcard' do. fresh_type '' return.
    case. 'name' do.
        if. (value env_index PatternEnvironment)<#PatternEnvironment do.
            inference_fail(<position),(<'duplicate_pattern'),<, <value
        end.
        result =. fresh_type ''
        scheme =. (<result),<i.0
        PatternEnvironment =: ((<value),<scheme)env_put PatternEnvironment
        result return.
    case. 'integer' do. IntType return.
    case. 'boolean' do. BoolType return.
    case. 'string' do. StringType return.
    case. 'pair' do.
        first =. infer_pattern 0{children
        second =. infer_pattern 1{children
        'pair'new_type first,second return.
    end.
    element =. fresh_type ''
    sequence =. 'list'new_type,element
    if. kind-:'cons' do.
        found =. infer_pattern 0{children
        check_type(<element),(<found),<node_position 0{children
        found =. infer_pattern 1{children
        check_type(<sequence),(<found),<node_position 1{children
    else.
        for_child. children do.
            found =. infer_pattern child
            check_type(<element),(<found),<node_position child
        end.
    end.
    sequence
)
infer_group =: 3 : 0
    'group environment local' =. y
    'bindings rec_position' =. group{::Groups
    names =. 0$a:
    for_number. bindings do.
        'name position expression scheme classification' =. number{::Bindings
        if. (<name)e.names do.
            inference_fail(<position),(<'duplicate_let'),<, <name
        end.
        names =. names,<name
        if. #rec_position do.
            if. -.'fun'-:node_kind expression do.
                inference_fail(<position),(<'recursive_function'),<, <name
            end.
        end.
    end.
    inferred =. i.0
    if. #rec_position do.
        recursive =. environment
        for_i. i.#bindings do.
            variable =. fresh_type ''
            inferred =. inferred,variable
            scheme =. (<variable),<i.0
            recursive =. ((i{names),<scheme)env_put recursive
        end.
        for_i. i.#bindings do.
            binding =. (i{bindings){::Bindings
            found =. recursive infer_expression 2{::binding
            check_type(<i{inferred),(<found),<1{::binding
        end.
    else.
        for_number. bindings do.
            inferred =. inferred,environment infer_expression 2{::number{::Bindings
        end.
    end.
    result =. environment
    for_i. i.#bindings do.
        number =. i{bindings
        binding =. number{::Bindings
        scheme =. environment generalize_type i{inferred
        binding =. (<scheme)3}binding
        Bindings =: (<binding)number}Bindings
        result =. ((i{names),<scheme)env_put result
    end.
    if. local do. LocalBindings =: LocalBindings,bindings end.
    result
)
