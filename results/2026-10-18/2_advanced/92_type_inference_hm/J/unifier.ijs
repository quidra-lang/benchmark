new_type =: 4 : 0
    number =. #TypePool
    TypePool =: TypePool,<(<x),(<y),<_1
    number
)
fresh_type =: 3 : '''variable''new_type i.0'
type_kind =: 3 : '0{::y{::TypePool'
type_children =: 3 : '1{::y{::TypePool'
bind_type =: 4 : 0
    record =. x{::TypePool
    TypePool =: (<(<y)2}record)x}TypePool
)
resolve_type =: 3 : 0
    number =. y
    path =. i.0
    while. 'variable'-:type_kind number do.
        next =. 2{::number{::TypePool
        if. next=_1 do. break. end.
        path =. path,number
        number =. next
    end.
    for_variable. path do. variable bind_type number end.
    number
)
occurs_type =: 4 : 0
    number =. resolve_type y
    if. number=x do. 1 return. end.
    for_child. type_children number do.
        if. x occurs_type child do. 1 return. end.
    end.
    0
)
unify_types =: 3 : 0
    'expected found nested' =. y
    expected =. resolve_type expected
    found =. resolve_type found
    if. expected=found do. i.0 return. end.
    first_kind =. type_kind expected
    second_kind =. type_kind found
    if. first_kind-:'variable' do.
        if. expected occurs_type found do. expected,found,1,nested return. end.
        expected bind_type found
    elseif. second_kind-:'variable' do.
        if. found occurs_type expected do. expected,found,1,nested return. end.
        found bind_type expected
    elseif. -.first_kind-:second_kind do.
        expected,found,0,nested return.
    else.
        first =. type_children expected
        second =. type_children found
        for_i. i.#first do.
            failure =. unify_types(i{first),(i{second),1
            if. #failure do. failure return. end.
        end.
    end.
    i.0
)
free_types =: 3 : 0
    number =. resolve_type y
    if. 'variable'-:type_kind number do. ,number return. end.
    variables =. i.0
    for_child. type_children number do. variables =. variables,free_types child end.
    ~.variables
)
generalize_type =: 4 : 0
    free_environment =. i.0
    for_record. x do.
        'name scheme' =. >record
        'value quantified' =. scheme
        free_environment =. free_environment,(free_types value)-.quantified
    end.
    (<y),<(free_types y)-.free_environment
)
copy_type =: 4 : 0
    number =. resolve_type y
    if. 'variable'-:type_kind number do.
        index =. (0{"1 x)i.number
        if. index=#x do. number else. (<index,1){x end.
    else.
        children =. i.0
        for_child. type_children number do. children =. children,x copy_type child end.
        (type_kind number)new_type children
    end.
)
instantiate_type =: 3 : 0
    'value quantified' =. y
    replacements =. 0 2$0
    for_variable. quantified do. replacements =. replacements,variable,fresh_type '' end.
    replacements copy_type value
)
initialize_types =: 3 : 0
    TypePool =: 0$a:
    IntType =: 'int'new_type i.0
    BoolType =: 'bool'new_type i.0
    StringType =: 'string'new_type i.0
)
