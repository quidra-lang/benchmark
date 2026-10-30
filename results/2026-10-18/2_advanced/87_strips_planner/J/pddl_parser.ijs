tokenize =: 3 : 0
    tokens =. 0$a:
    for_line. <;._2 y do.
        line =. >line
        line =. (line i.';'){.line
        word =. ''
        for_character. line do.
            if. character e.' ()' do.
                if. #word do.
                    tokens =. tokens,<word
                    word =. ''
                end.
                if. character e.'()' do.
                    tokens =. tokens,<,character
                end.
            else.
                word =. word,character
            end.
        end.
        if. #word do.
            tokens =. tokens,<word
        end.
    end.
    tokens
)
read_expression =: 3 : 0
    token =. ExpressionPosition{::ExpressionTokens
    ExpressionPosition =: ExpressionPosition+1
    if. token-:,'(' do.
        value =. 0$a:
        while. -. (ExpressionPosition{::ExpressionTokens)-:,')' do.
            value =. value,<read_expression ''
        end.
        ExpressionPosition =: ExpressionPosition+1
        value
    else.
        token
    end.
)
expressions =: 3 : 0
    ExpressionTokens =: tokenize y
    ExpressionPosition =: 0
    roots =. 0$a:
    while. ExpressionPosition<#ExpressionTokens do.
        roots =. roots,<read_expression ''
    end.
    roots
)
typed_list =: 3 : 0
    names =. 0$a:
    types =. 0$a:
    pending =. 0$a:
    position =. 0
    while. position<#y do.
        word =. position{::y
        if. word-:,'-' do.
            type =. (position+1){::y
            names =. names,pending
            types =. types,(#pending)$<type
            pending =. 0$a:
            position =. position+2
        else.
            pending =. pending,<word
            position =. position+1
        end.
    end.
    names =. names,pending
    types =. types,(#pending)$<'object'
    (<names),<types
)
expression_atom =: 3 : '(0{y),<}.y'
condition_elements =: 3 : 0
    conjunction =. 'and'-:0{::y
    for_element. }.y do.
        conjunction =. conjunction*.32=3!:0 >element
    end.
    if. conjunction do.
        }.y
    else.
        ,<y
    end.
)
required_elements =: 3 : 0
    elements =. condition_elements y
    if. 0=#elements do.
        ,<y
    else.
        elements
    end.
)
expression_literal =: 3 : 0
    negative =. ('not'-:0{::y)*.2=#y
    if. negative do.
        negative =. 32=3!:0 (1{::y)
    end.
    if. negative do.
        (<0),<expression_atom 1{::y
    else.
        (<1),<expression_atom y
    end.
)
read_domain =: 3 : 0
    root =. 0{::expressions y
    DomainName =: 1{::1{::root
    TypeNames =: <'object'
    TypeParents =: <''
    PredicateNames =: 0$a:
    PredicateTypes =: 0$a:
    Schemas =: 0$a:
    for_section. 2}.root do.
        section =. >section
        kind =. 0{::section
        select. kind
        case. ':types' do.
            items =. }.section
            for_name. items do.
                name =. >name
                if. name-:,'-' do.
                    continue.
                end.
                if. -.(<name)e.TypeNames do.
                    TypeNames =: TypeNames,<name
                    TypeParents =: TypeParents,<'object'
                end.
            end.
            'names parents' =. typed_list items
            for_i. i.#names do.
                index =. TypeNames i.i{names
                TypeParents =: (i{parents)index}TypeParents
            end.
        case. ':predicates' do.
            for_declaration. }.section do.
                declaration =. >declaration
                PredicateNames =: PredicateNames,<0{::declaration
                'names types' =. typed_list }.declaration
                PredicateTypes =: PredicateTypes,<types
            end.
        case. ':action' do.
            name =. 1{::section
            keys =. (2+2*i.((#section)-2)intdiv 2){section
            values =. (3+2*i.((#section)-2)intdiv 2){section
            parameters =. typed_list (keys i.<':parameters'){::values
            condition =. 0$a:
            index =. keys i.<':precondition'
            if. index<#keys do.
                condition =. expression_literal&.>condition_elements index{::values
            end.
            effects =. 0$a:
            cost =. 1
            for_element. required_elements (keys i.<':effect'){::values do.
                element =. >element
                is_cost =. ('increase'-:0{::element)*.3=#element
                if. is_cost do.
                    is_cost =. (1{::element)-:,<'total-cost'
                end.
                if. is_cost do.
                    cost =. parse_integer 2{::element
                else.
                    effects =. effects,<expression_literal element
                end.
            end.
            schema =. (<name),(<parameters),(<condition),(<effects),<cost
            Schemas =: Schemas,<schema
        end.
    end.
)
read_problems =: 3 : 0
    SourceProblems =: 0$a:
    for_expression. expressions y do.
        expression =. >expression
        name =. 1{::1{::expression
        keys =. 0$a:
        values =. 0$a:
        for_section. 2}.expression do.
            section =. >section
            keys =. keys,<0{::section
            values =. values,<}.section
        end.
        'objects types' =. typed_list (keys i.<':objects'){::values
        initial =. expression_atom&.>(keys i.<':init'){::values
        goal_expression =. 0{::(keys i.<':goal'){::values
        goals =. expression_atom&.>required_elements goal_expression
        problem =. (<name),(<objects),(<types),(<initial),<goals
        SourceProblems =: SourceProblems,<problem
    end.
)
