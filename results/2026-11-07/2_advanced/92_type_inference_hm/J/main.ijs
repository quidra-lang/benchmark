ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'parser.ijs'
load SourceDirectory,'unifier.ijs'
load SourceDirectory,'inference.ijs'
load SourceDirectory,'evaluator.ijs'

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
env_names =: 3 : 0
    names =. 0$a:
    for_record. y do. names =. names,<0{::>record end.
    names
)
quote_string =: 3 : 0
    text =. ,'"'
    for_character. y do.
        select. character
        case. '\' do. text =. text,'\\'
        case. '"' do. text =. text,'\"'
        case. LF do. text =. text,'\n'
        case. (9{a.) do. text =. text,'\t'
        case. do. text =. text,character
        end.
    end.
    text,'"'
)
format_literal =: 4 : 0
    select. x
    case. 'integer' do. integer y
    case. 'boolean' do. y{::'false';'true'
    case. 'string' do. quote_string y
    end.
)
print_value =: 3 : 0
    'kind value' =. y{::Values
    if. (<kind)e.;:'integer boolean string' do. kind format_literal value return. end.
    if. (<kind)e.'pair';'list' do.
        parts =. 0$a:
        for_child. value do. parts =. parts,<print_value child end.
        if. kind-:'pair' do. '(',(', 'join parts),')' else. '[',('; 'join parts),']' end.
    else.
        '<fun>'
    end.
)
builtin_call =: 4 : 0
    'name argument' =. y
    data =. value_data argument
    select. name
    case. 'fst' do. 0{data
    case. 'snd' do. 1{data
    case. 'not' do. 'boolean'new_value -.data
    case. 'string_of_int' do. 'string'new_value integer data
    case. 'failwith' do. x runtime_fail 'failure ',print_value argument
    end.
)
start_type_printer =: 4 : 0
    PrinterVariables =: i.0
    PrinterLocal =: x
    PrinterQuantified =: y
)
type_text =: 3 : 0
    number =. resolve_type y
    kind =. type_kind number
    if. kind-:'variable' do.
        index =. PrinterVariables i.number
        if. index=#PrinterVariables do. PrinterVariables =: PrinterVariables,number end.
        prefix =. ,39{a.
        if. PrinterLocal*.-.number e.PrinterQuantified do. prefix =. prefix,'_' end.
        suffix =. ''
        if. index>:26 do. suffix =. integer <.(x:index)%26x end.
        prefix,((26|index){'abcdefghijklmnopqrstuvwxyz'),suffix return.
    end.
    if. (<kind)e.;:'int bool string' do. kind return. end.
    children =. type_children number
    first =. resolve_type 0{children
    left =. type_text first
    first_kind =. type_kind first
    if. kind-:'list' do.
        if. (<first_kind)e.'pair';'function' do. left =. '(',left,')' end.
        left,' list' return.
    end.
    second =. resolve_type 1{children
    right =. type_text second
    if. kind-:'pair' do.
        if. (<first_kind)e.'pair';'function' do. left =. '(',left,')' end.
        if. (<type_kind second)e.'pair';'function' do. right =. '(',right,')' end.
        left,' * ',right
    else.
        if. first_kind-:'function' do. left =. '(',left,')' end.
        left,' -> ',right
    end.
)
declared_text =: 3 : 0
    kind =. node_kind y
    if. kind-:'type_variable' do. node_value y return. end.
    if. (<kind)e.;:'int bool string' do. kind return. end.
    children =. node_children y
    first =. 0{children
    left =. declared_text first
    first_kind =. node_kind first
    if. kind-:'list' do.
        if. (<first_kind)e.'pair';'function' do. left =. '(',left,')' end.
        left,' list' return.
    end.
    second =. 1{children
    right =. declared_text second
    if. kind-:'pair' do.
        if. (<first_kind)e.'pair';'function' do. left =. '(',left,')' end.
        if. (<node_kind second)e.'pair';'function' do. right =. '(',right,')' end.
        left,' * ',right
    else.
        if. first_kind-:'function' do. left =. '(',left,')' end.
        left,' -> ',right
    end.
)
signature_type =: 3 : 0
    kind =. node_kind y
    if. kind-:'type_variable' do.
        name =. node_value y
        index =. SignatureNames i.<name
        if. index=#SignatureNames do.
            SignatureNames =: SignatureNames,<name
            SignatureTypes =: SignatureTypes,fresh_type ''
        end.
        index{SignatureTypes
    else.
        children =. i.0
        for_child. node_children y do. children =. children,signature_type child end.
        kind new_type children
    end.
)
identical_types =: 4 : 0
    first =. resolve_type x
    second =. resolve_type y
    if. (('variable'-:type_kind first)+.'variable'-:type_kind second) do. first=second return. end.
    if. -.(type_kind first)-:type_kind second do. 0 return. end.
    a =. type_children first
    b =. type_children second
    for_i. i.#a do.
        if. -.(i{a)identical_types i{b do. 0 return. end.
    end.
    1
)
signature_matches =: 4 : 0
    first =. resolve_type x
    second =. resolve_type y
    if. 'variable'-:type_kind first do.
        index =. (0{"1 SignatureAssignments)i.first
        if. index<#SignatureAssignments do.
            ((<index,1){SignatureAssignments)identical_types second
        else.
            SignatureAssignments =: SignatureAssignments,first,second
            1
        end.
        return.
    end.
    if. ('variable'-:type_kind second)+.-.(type_kind first)-:type_kind second do. 0 return. end.
    a =. type_children first
    b =. type_children second
    for_i. i.#a do.
        if. -.(i{a)signature_matches i{b do. 0 return. end.
    end.
    1
)
check_signatures =: 3 : 0
    'group signatures' =. y
    bindings =. 0{::group{::Groups
    for_i. i.#bindings do.
        signature =. i{::signatures
        if. 0=#signature do. continue. end.
        number =. i{bindings
        'name position expression scheme classification' =. number{::Bindings
        SignatureNames =: 0$a:
        SignatureTypes =: i.0
        SignatureAssignments =: 0 2$0
        declared =. signature_type 1{::signature
        inferred =. 0{::scheme
        if. -.inferred signature_matches declared do.
            details =. (<name),(<inferred),<declared
            inference_fail(<position),(<'signature'),<details
        end.
        scheme =. (<declared),<free_types declared
        binding =. number{::Bindings
        Bindings =: (<(<scheme)3}binding)number}Bindings
    end.
)
edit_distance =: 4 : 0
    previous =. i.1+#y
    for_i. i.#x do.
        current =. ,i+1
        for_j. i.#y do.
            value =. (({:current)+1)<.((j+1){previous)+1
            value =. value<.(j{previous)+(i{x)~:j{y
            current =. current,value
        end.
        previous =. current
    end.
    {:previous
)
name_candidate =: 4 : 0
    best =. ''
    distance =. 3
    for_candidate. /:~y do.
        candidate =. >candidate
        d =. x edit_distance candidate
        if. (d<distance)*.(d<:2)*.d<#x do.
            distance =. d
            best =. candidate
        end.
    end.
    best
)
type_error_message =: 3 : 0
    'position kind details' =. y
    0 start_type_printer i.0
    quote =. 39{a.
    if. kind-:'unbound' do.
        'name candidates' =. details
        text =. 'unbound variable ',quote,name,quote
        candidate =. name name_candidate candidates
        if. #candidate do. text =. text,' (did you mean ',quote,candidate,quote,'?)' end.
        text return.
    elseif. kind-:'not_function' do.
        'expected a function but found ',type_text {.details return.
    elseif. kind-:'check' do.
        'expected found failure' =. details
        text =. 'expected ',(type_text expected),' but found ',type_text found
        'first second infinite nested' =. failure
        if. infinite do.
            if. -.'variable'-:type_kind resolve_type first do. 'first second' =. second,first end.
            text =. text,' (infinite type ',(type_text first),' = ',(type_text second),')'
        elseif. nested do.
            text =. text,' (',(type_text first),' vs ',(type_text second),')'
        end.
        text return.
    end.
    name =. 0{::details
    if. kind-:'duplicate_pattern' do. 'variable ',quote,name,quote,' is bound twice in this pattern'
    elseif. kind-:'duplicate_let' do. 'variable ',quote,name,quote,' is bound twice in this let'
    elseif. kind-:'recursive_function' do. quote,name,quote,' in let rec must be a function'
    else.
        quote,name,quote,' has type ',(type_text 1{::details),' but its signature is ',type_text 2{::details
    end.
)
leading_parameters =: 3 : 0
    parameters =. 0$a:
    expression =. y
    while. 'fun'-:node_kind expression do.
        parameters =. parameters,<1{::node_value expression
        expression =. {.node_children expression
    end.
    (<parameters),<expression
)
format_binding =: 3 : 0
    'name position expression scheme classification' =. y{::Bindings
    'parameters body' =. leading_parameters expression
    ' 'join(<name),parameters,(<,'='),<0 format_expression body
)
format_group =: 3 : 0
    'bindings rec_position' =. y{::Groups
    prefix =. 'let '
    if. #rec_position do. prefix =. 'let rec ' end.
    parts =. 0$a:
    for_binding. bindings do. parts =. parts,<format_binding binding end.
    prefix,' and 'join parts
)
ends_with_match =: 3 : 0
    kind =. node_kind y
    if. kind-:'match' do. 1 return. end.
    if. (<kind)e.'fun';'let' do. ends_with_match {.node_children y
    elseif. kind-:'if' do. ends_with_match 2{node_children y
    else. 0 end.
)
format_pattern =: 3 : 0
    'kind position children value inferred' =. y{::Nodes
    if. (<kind)e.'name';'wildcard' do. value return. end.
    if. (<kind)e.;:'integer boolean string' do. kind format_literal value return. end.
    if. kind-:'list' do.
        parts =. 0$a:
        for_child. children do. parts =. parts,<format_pattern child end.
        '[',('; 'join parts),']' return.
    end.
    first =. 0{children
    left =. format_pattern first
    right =. format_pattern 1{children
    if. kind-:'pair' do. '(',left,', ',right,')'
    else.
        if. 'cons'-:node_kind first do. left =. '(',left,')' end.
        left,' :: ',right
    end.
)
format_expression =: 4 : 0
    'kind position children value inferred' =. y{::Nodes
    strength =. 9
    select. kind
    case. 'integer';'boolean';'string' do. text =. kind format_literal value
    case. 'name' do. text =. value
    case. 'fun' do.
        strength =. 0
        'parameters body' =. leading_parameters y
        text =. 'fun ',(' 'join parameters),' -> ',0 format_expression body
    case. 'apply' do.
        strength =. 8
        text =. (8 format_expression 0{children),' ',9 format_expression 1{children
    case. 'binary' do.
        operator =. 1{::value
        index =. OperatorNames i.<operator
        strength =. index{OperatorPrecedence
        right =. index{OperatorRight
        text =. ((strength+right)format_expression 0{children),' ',operator,' '
        text =. text,(strength+-.right)format_expression 1{children
    case. 'negate' do.
        strength =. 7
        text =. '-',7 format_expression 0{children
    case. 'if' do.
        strength =. 0
        text =. 'if ',(0 format_expression 0{children),' then ',0 format_expression 1{children
        text =. text,' else ',0 format_expression 2{children
    case. 'pair' do.
        text =. '(',(0 format_expression 0{children),', ',(0 format_expression 1{children),')'
    case. 'list' do.
        parts =. 0$a:
        for_child. children do. parts =. parts,<0 format_expression child end.
        text =. '[',('; 'join parts),']'
    case. 'let' do.
        strength =. 0
        text =. (format_group value),' in ',0 format_expression 0{children
    case. 'match' do.
        strength =. 0
        parts =. 0$a:
        for_i. i.#value do.
            'pattern body' =. i{value
            body_text =. 0 format_expression body
            if. (i<(#value)-1)*.ends_with_match body do. body_text =. '(',body_text,')' end.
            parts =. parts,<(format_pattern pattern),' -> ',body_text
        end.
        text =. 'match ',(0 format_expression 0{children),' with ',' | 'join parts
    end.
    if. strength<x do. '(',text,')' else. text end.
)
format_item =: 3 : 0
    'kind value' =. y
    if. kind-:'signature' do.
        'name declared' =. value
        'val ',(1{::name),' : ',(declared_text declared),';;'
    elseif. kind-:'declaration' do.
        (format_group value),';;'
    else.
        (0 format_expression value),';;'
    end.
)

coverage_node =: 4 : 0
    number =. #CoverageNodes
    CoverageNodes =: CoverageNodes,<(<x),<y
    number
)
coverage_pattern =: 3 : 0
    'kind position children value inferred' =. y{::Nodes
    if. (<kind)e.'wildcard';'name' do. _1 return. end.
    if. (<kind)e.;:'integer boolean string' do.
        ((<kind),<value)coverage_node i.0 return.
    end.
    if. kind-:'list' do.
        result =. ((<'nil'),<'')coverage_node i.0
        for_child. |.children do.
            first =. coverage_pattern child
            result =. ((<'cons'),<'')coverage_node first,result
        end.
        result return.
    end.
    arguments =. i.0
    for_child. children do. arguments =. arguments,coverage_pattern child end.
    ((<kind),<'')coverage_node arguments
)
coverage_constructors =: 3 : 0
    kind =. type_kind resolve_type y
    if. kind-:'bool' do.
        (<(<'boolean'),<0),<(<'boolean'),<1
    elseif. kind-:'list' do.
        (<(<'nil'),<''),<(<'cons'),<''
    elseif. kind-:'pair' do.
        ,<(<'pair'),<''
    else.
        0$a:
    end.
)
constructor_arguments =: 4 : 0
    kind =. 0{::x
    number =. resolve_type y
    if. kind-:'pair' do. type_children number
    elseif. kind-:'cons' do. ({.type_children number),number
    else. i.0 end.
)
specialize_matrix =: 4 : 0
    'constructor arity' =. x
    rows =. 0$a:
    for_row. y do.
        row =. >row
        head =. {.row
        if. head=_1 do.
            rows =. rows,<(arity$_1),}.row
        else.
            'key arguments' =. head{::CoverageNodes
            if. key-:constructor do. rows =. rows,<arguments,}.row end.
        end.
    end.
    rows
)
useful_pattern =: 3 : 0
    index =. CoverageCacheKeys i.<y
    if. index<#CoverageCacheKeys do. index{CoverageCacheValues return. end.
    result =. compute_useful y
    CoverageCacheKeys =: CoverageCacheKeys,<y
    CoverageCacheValues =: CoverageCacheValues,result
    result
)
compute_useful =: 3 : 0
    'matrix query types' =. y
    if. 0=#query do. 0=#matrix return. end.
    if. 0=#matrix do. 1 return. end.
    head =. {.query
    if. head~:_1 do.
        'constructor arguments' =. head{::CoverageNodes
        argument_types =. constructor constructor_arguments {.types
        selected =. ((<constructor),<#arguments)specialize_matrix matrix
        useful_pattern(<selected),(<arguments,}.query),<argument_types,}.types return.
    end.
    possible =. coverage_constructors {.types
    present =. 0$a:
    for_row. matrix do.
        first =. {.>row
        if. first~:_1 do. present =. present,<0{::first{::CoverageNodes end.
    end.
    if. (0<#possible)*.*./possible e.present do.
        for_constructor. possible do.
            constructor =. >constructor
            argument_types =. constructor constructor_arguments {.types
            arity =. #argument_types
            selected =. ((<constructor),<arity)specialize_matrix matrix
            q =. (arity$_1),}.query
            if. useful_pattern(<selected),(<q),<argument_types,}.types do. 1 return. end.
        end.
        0 return.
    end.
    defaults =. 0$a:
    for_row. matrix do.
        row =. >row
        if. _1={.row do. defaults =. defaults,<}.row end.
    end.
    useful_pattern(<defaults),(<}.query),<}.types
)
add_warning =: 3 : 'ItemWarnings =: ItemWarnings,<y'
match_warnings =: 3 : 0
    CoverageCacheKeys =: 0$a:
    CoverageCacheValues =: i.0
    matrix =. 0$a:
    matched_type =. ,node_type {.node_children y
    arms =. node_value y
    for_i. i.#arms do.
        'pattern expression' =. i{arms
        query =. ,coverage_pattern pattern
        if. i do.
            if. -.useful_pattern(<matrix),(<query),<matched_type do.
                add_warning(<node_position pattern),(<2),<'this match case is unused'
            end.
        end.
        matrix =. matrix,<query
    end.
    if. useful_pattern(<matrix),(<,_1),<matched_type do.
        add_warning(<node_position y),(<1),<'this match is not exhaustive'
    end.
)
new_symbol =: 3 : 0
    number =. #Symbols
    Symbols =: Symbols,<y,<0
    number
)
bind_static_pattern =: 4 : 0
    environment =. x
    if. 'name'-:node_kind y do.
        name =. node_value y
        symbol =. new_symbol(<name),(<node_position y),<0
        environment =. ((<name),<symbol)env_put environment
    end.
    for_child. node_children y do. environment =. environment bind_static_pattern child end.
    environment
)
static_group =: 4 : 0
    'group top' =. y
    environment =. x
    'bindings rec_position' =. group{::Groups
    targets =. i.0
    inner =. environment
    for_number. bindings do.
        'name position expression scheme classification' =. number{::Bindings
        symbol =. new_symbol(<name),(<position),<top
        targets =. targets,symbol
        inner =. ((<name),<symbol)env_put inner
    end.
    StaticGroups =: StaticGroups,<(<group),<targets
    right =. environment
    if. #rec_position do. right =. inner end.
    for_number. bindings do. right static_expression 2{::number{::Bindings end.
    inner
)
static_expression =: 4 : 0
    environment =. x
    'kind position children value inferred' =. y{::Nodes
    if. kind-:'name' do.
        index =. value env_index environment
        symbol =. _1
        if. index<#environment do. symbol =. 1{::index{::environment end.
        StaticReferences =: symbol y}StaticReferences
        if. symbol~:_1 do.
            record =. symbol{::Symbols
            Symbols =: (<(<1)3}record)symbol}Symbols
        end.
        return.
    elseif. kind-:'fun' do.
        inner =. environment
        name =. 1{::value
        if. -.name-:,'_' do.
            symbol =. new_symbol(<name),(<3{::value),<0
            inner =. ((<name),<symbol)env_put inner
        end.
        inner static_expression {.children
        return.
    elseif. kind-:'let' do.
        inner =. environment static_group value,0
        inner static_expression {.children
        return.
    elseif. kind-:'match' do.
        environment static_expression {.children
        match_warnings y
        for_arm. value do.
            'pattern expression' =. arm
            inner =. environment bind_static_pattern pattern
            inner static_expression expression
        end.
        return.
    end.
    for_child. children do. environment static_expression child end.
)
expression_nodes =: 3 : 0
    numbers =. ,y
    kind =. node_kind y
    if. kind-:'let' do.
        bindings =. 0{::(node_value y){::Groups
        for_number. bindings do. numbers =. numbers,expression_nodes 2{::number{::Bindings end.
    end.
    for_child. node_children y do. numbers =. numbers,expression_nodes child end.
    if. kind-:'match' do.
        for_arm. node_value y do. numbers =. numbers,expression_nodes 1{arm end.
    end.
    numbers
)
recursion_visit =: 4 : 0
    tail =. x
    kind =. node_kind y
    children =. node_children y
    if. kind-:'name' do.
        if. (y{StaticReferences)e.RecursionTargets do. RecursionCalls =: RecursionCalls,0 end.
        return.
    elseif. kind-:'apply' do.
        arguments =. i.0
        function =. y
        while. 'apply'-:node_kind function do.
            pair =. node_children function
            arguments =. (1{pair),arguments
            function =. 0{pair
        end.
        if. ('name'-:node_kind function)*.(function{StaticReferences)e.RecursionTargets do.
            RecursionCalls =: RecursionCalls,tail
        else.
            0 recursion_visit function
        end.
        for_argument. arguments do. 0 recursion_visit argument end.
        return.
    elseif. kind-:'if' do.
        0 recursion_visit 0{children
        tail recursion_visit 1{children
        tail recursion_visit 2{children
        return.
    elseif. kind-:'match' do.
        0 recursion_visit 0{children
        for_arm. node_value y do. tail recursion_visit 1{arm end.
        return.
    elseif. kind-:'let' do.
        bindings =. 0{::(node_value y){::Groups
        for_number. bindings do. 0 recursion_visit 2{::number{::Bindings end.
        tail recursion_visit 0{children
        return.
    elseif. kind-:'binary' do.
        if. (1{node_value y)e.'&&';'||' do.
            0 recursion_visit 0{children
            tail recursion_visit 1{children
            return.
        end.
    end.
    for_child. children do. 0 recursion_visit child end.
)
static_checks =: 3 : 0
    'kind value' =. y
    Symbols =: StaticGroups =: ItemWarnings =: 0$a:
    StaticReferences =: (#Nodes)$_1
    environment =. 0$a:
    for_name. env_names TypeEnvironment do.
        environment =. environment,<name,<_1
    end.
    if. kind-:'declaration' do.
        environment static_group value,1
    else.
        environment static_expression value
    end.
    for_record. StaticGroups do.
        'group targets' =. >record
        'bindings rec_position' =. group{::Groups
        if. 0=#rec_position do. continue. end.
        referenced =. 0
        for_number. bindings do.
            nodes =. expression_nodes 2{::number{::Bindings
            referenced =. referenced+.+./(nodes{StaticReferences)e.targets
        end.
        if. -.referenced do. add_warning(<rec_position),(<3),<'unused rec flag' end.
        RecursionTargets =: targets
        for_number. bindings do.
            expression =. 2{::number{::Bindings
            'parameters body' =. leading_parameters expression
            RecursionCalls =: i.0
            1 recursion_visit body
            classification =. ''
            if. #RecursionCalls do.
                classification =. 'recursive'
                if. *./RecursionCalls do. classification =. 'tail recursive' end.
            end.
            binding =. number{::Bindings
            Bindings =: (<(<classification)4}binding)number}Bindings
        end.
    end.
    for_symbol. Symbols do.
        'name position top used' =. >symbol
        if. (-.top)*.(-.used)*.'_'~:{.name do.
            quote =. 39{a.
            add_warning(<position),(<4),<'unused variable ',quote,name,quote
        end.
    end.
    keys =. 0 3$0
    for_warning. ItemWarnings do.
        'position priority message' =. >warning
        keys =. keys,(}.position),priority
    end.
    (/:keys){ItemWarnings
)

classification_suffix =: 3 : 0
    classification =. 4{::y{::Bindings
    if. #classification do. ' (',classification,')' else. '' end.
)
write_types =: 3 : 0
    'item inferred' =. y
    'kind value' =. item
    if. kind-:'declaration' do.
        bindings =. 0{::value{::Groups
        for_number. bindings do.
            'name position expression scheme classification' =. number{::Bindings
            0 start_type_printer i.0
            text =. name,' : ',type_text 0{::scheme
            TypesOutput =: TypesOutput,<text,classification_suffix number
        end.
    else.
        0 start_type_printer i.0
        TypesOutput =: TypesOutput,<'- : ',type_text inferred
    end.
    keys =. 0 2$0
    for_number. LocalBindings do. keys =. keys,}.1{::number{::Bindings end.
    for_number. (/:keys){LocalBindings do.
        'name position expression scheme classification' =. number{::Bindings
        'file row column' =. position
        1 start_type_printer 1{::scheme
        text =. '  ',name,' (',(integer row),':',(integer column),') : ',type_text 0{::scheme
        TypesOutput =: TypesOutput,<text,classification_suffix number
    end.
)
report =: 3 : 0
    'kind position message' =. y
    'file row column' =. position
    select. kind
    case. 'syntax error' do. counter =. 2
    case. 'type error' do. counter =. 3
    case. 'runtime error' do. counter =. 4
    case. 'warning' do. counter =. 5
    end.
    cell =. <CurrentFile,counter
    Statistics =: (1+cell{Statistics)cell}Statistics
    text =. (file{::FileNames),':',(integer row),':',(integer column),': ',kind,': ',message
    ErrorsOutput =: ErrorsOutput,<text
    lines =. file{::SourceLines
    if. row<:#lines do.
        ErrorsOutput =: ErrorsOutput,(<'    ',(row-1){::lines),<((column+3)$' '),'^'
    end.
)
unused_signature =: 3 : 0
    name =. 0{::y
    quote =. 39{a.
    message =. 'signature for ',quote,(1{::name),quote,' is never used'
    report(<'warning'),(<3{::name),<message
)
syntax_message =: 3 : 0
    'kind spelling value position' =. y
    if. kind-:'invalid' do. value
    elseif. kind-:'EOF' do. 'unexpected end of file'
    else.
        quote =. 39{a.
        'unexpected ',quote,spelling,quote
    end.
)
process_item =: 3 : 0
    item =. y
    'kind value' =. item
    FormattedOutput =: FormattedOutput,<format_item item
    if. kind-:'signature' do.
        name =. 1{::0{::value
        index =. name env_index PendingSignatures
        if. index<#PendingSignatures do. unused_signature 1{::index{::PendingSignatures end.
        PendingSignatures =: ((<name),<value)env_put PendingSignatures
        return.
    end.
    signatures =. 0$a:
    if. kind-:'declaration' do.
        bindings =. 0{::value{::Groups
        for_number. bindings do.
            name =. 0{::number{::Bindings
            index =. name env_index PendingSignatures
            signature =. 0$a:
            if. index<#PendingSignatures do.
                signature =. 1{::index{::PendingSignatures
                PendingSignatures =: (index~:i.#PendingSignatures)#PendingSignatures
            end.
            signatures =. signatures,<signature
        end.
    end.
    LocalBindings =: i.0
    TypeError =: 0$a:
    inferred =. _1
    try.
        if. kind-:'declaration' do.
            infer_group(<value),(<TypeEnvironment),<0
            check_signatures(<value),<signatures
        else.
            inferred =. TypeEnvironment infer_expression value
        end.
    catch.
        if. 0=#TypeError do. 13!:8 3 end.
    end.
    if. #TypeError do.
        report(<'type error'),(<0{::TypeError),<type_error_message TypeError
        return.
    end.
    warnings =. static_checks item
    write_types(<item),<inferred
    for_warning. warnings do.
        'position priority message' =. >warning
        report(<'warning'),(<position),<message
    end.
    RuntimeError =: 0$a:
    try.
        if. kind-:'declaration' do.
            environment =. ValueEnvironment evaluate_group value
        else.
            result =. ValueEnvironment evaluate_expression value
        end.
    catch.
        if. 0=#RuntimeError do. 13!:8 3 end.
    end.
    if. #RuntimeError do.
        'position message' =. RuntimeError
        report(<'runtime error'),(<position),<message
        return.
    end.
    if. kind-:'declaration' do.
        records =. environment{::ValueEnvironments
        for_number. bindings do.
            'name position expression scheme classification' =. number{::Bindings
            result =. 1{::(name env_index records){::records
            ValuesOutput =: ValuesOutput,<name,' = ',print_value result
            TypeEnvironment =: ((<name),<scheme)env_put TypeEnvironment
        end.
        ValueEnvironment =: environment
        cell =. <CurrentFile,1
        Statistics =: ((cell{Statistics)+#bindings)cell}Statistics
    else.
        ValuesOutput =: ValuesOutput,<'- = ',print_value result
    end.
)
initialize_builtins =: 3 : 0
    TypeEnvironment =: 0$a:
    values =. 0$a:
    for_name. ;:'fst snd not string_of_int failwith' do.
        name =. >name
        quantified =. i.0
        if. (<name)e.'fst';'snd' do.
            first =. fresh_type ''
            second =. fresh_type ''
            pair =. 'pair'new_type first,second
            result =. first
            if. name-:'snd' do. result =. second end.
            value =. 'function'new_type pair,result
            quantified =. first,second
        elseif. name-:'not' do.
            value =. 'function'new_type BoolType,BoolType
        elseif. name-:'string_of_int' do.
            value =. 'function'new_type IntType,StringType
        else.
            result =. fresh_type ''
            value =. 'function'new_type StringType,result
            quantified =. ,result
        end.
        scheme =. (<value),<quantified
        TypeEnvironment =: ((<name),<scheme)env_put TypeEnvironment
        function =. 'builtin'new_value name
        values =. ((<name),<function)env_put values
    end.
    ValueEnvironment =: new_environment values
)
process_file =: 3 : 0
    CurrentFile =: y
    name =. y{::FileNames
    TypesOutput =: TypesOutput,<'== ',name,' =='
    ValuesOutput =: ValuesOutput,<'== ',name,' =='
    FormattedOutput =: FormattedOutput,<'(* ',name,' *)'
    PendingSignatures =: 0$a:
    FileCalls =: 0
    Tokens =: y lex_source y{::Sources
    ParseIndex =: 0
    while. -.parser_at 'EOF' do.
        cell =. <CurrentFile,0
        Statistics =: (1+cell{Statistics)cell}Statistics
        SyntaxError =: 0$a:
        try.
            item =. read_item ''
        catch.
            if. 0=#SyntaxError do. 13!:8 3 end.
        end.
        if. #SyntaxError do.
            report(<'syntax error'),(<3{::SyntaxError),<syntax_message SyntaxError
            recover_item ''
        else.
            process_item item
        end.
    end.
    keys =. 0 2$0
    for_record. PendingSignatures do.
        signature =. 1{::>record
        keys =. keys,}.3{::0{::signature
    end.
    for_record. (/:keys){PendingSignatures do. unused_signature 1{::>record end.
    Statistics =: FileCalls(<CurrentFile,6)}Statistics
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    FileNames =: 'prelude.ml';'program.ml'
    Sources =: SourceLines =: 0$a:
    for_name. FileNames do.
        source =. 1!:1 <'input/',>name
        Sources =: Sources,<source
        SourceLines =: SourceLines,<<;._2 source
    end.
    Nodes =: Bindings =: Groups =: Values =: ValueEnvironments =: CoverageNodes =: 0$a:
    TypesOutput =: ValuesOutput =: ErrorsOutput =: FormattedOutput =: 0$a:
    Statistics =: 2 7$0
    initialize_types ''
    initialize_builtins ''
    process_file 0
    process_file 1
    ErrorsOutput =: ErrorsOutput,<'== summary =='
    labels =. ;:'items bindings syntax type runtime warnings calls'
    for_i. i.2 do.
        text =. (i{::FileNames),':'
        for_j. i.7 do.
            text =. text,' ',(j{::labels),'=',integer(<i,j){Statistics
        end.
        ErrorsOutput =: ErrorsOutput,<text
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'types.txt'write_lines TypesOutput
    'values.txt'write_lines ValuesOutput
    'errors.txt'write_lines ErrorsOutput
    'formatted.ml'write_lines FormattedOutput
)
run ''
