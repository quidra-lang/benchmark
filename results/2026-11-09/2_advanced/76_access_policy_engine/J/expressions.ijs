expression_node =: 4 : '(<x),(<''''),<y'
literal_node =: 3 : '(<''literal''),(<y),<0$a:'
expression_tokens =: 3 : 0
    text =. y
    tokens =. 0$a:
    position =. 0
    while. position<#text do.
        character =. position{text
        if. character=' ' do.
            position =. position+1
            continue.
        end.
        start =. position
        if. character='"' do.
            position =. position+1
            while. '"'~:position{text do.
                position =. position+1
            end.
            position =. position+1
        elseif. character e.'0123456789' do.
            position =. position+1
            while. position<#text do.
                if. -. (position{text)e.'0123456789' do.
                    break.
                end.
                position =. position+1
            end.
        elseif. character e.Letters do.
            position =. position+1
            while. position<#text do.
                if. -. (position{text)e.Letters,'0123456789_.' do.
                    break.
                end.
                position =. position+1
            end.
        else.
            position =. position+1
            if. position<#text do.
                pair =. 2{.start}.text
                if. (<pair)e.'==';'!=';'<=';'>=' do.
                    position =. position+1
                end.
            end.
        end.
        token =. (position-start){.start}.text
        if. (1=#token)*.character e.'+-*<>()[],' do.
            token =. {.token
        end.
        tokens =. tokens,<token
    end.
    tokens
)
expression_peek =: 3 : 0
    if. ExpressionPosition<#ExpressionTokens do.
        ExpressionPosition{::ExpressionTokens
    else.
        ''
    end.
)
expression_take =: 3 : 0
    token =. expression_peek ''
    ExpressionPosition =: ExpressionPosition+1
    token
)
parse_expression =: 3 : 0
    ExpressionTokens =: expression_tokens y
    ExpressionPosition =: 0
    parse_disjunction ''
)
parse_disjunction =: 3 : 0
    left =. parse_conjunction ''
    while. 'or'-:expression_peek '' do.
        expression_take ''
        right =. parse_conjunction ''
        left =. 'or'expression_node (<left),<right
    end.
    left
)
parse_conjunction =: 3 : 0
    left =. parse_negation ''
    while. 'and'-:expression_peek '' do.
        expression_take ''
        right =. parse_negation ''
        left =. 'and'expression_node (<left),<right
    end.
    left
)
parse_negation =: 3 : 0
    if. 'not'-:expression_peek '' do.
        expression_take ''
        'not'expression_node <parse_negation ''
    else.
        parse_comparison ''
    end.
)
parse_comparison =: 3 : 0
    left =. parse_sum ''
    operator =. expression_peek ''
    if. (<operator)e.'==';'!=';'<';'<=';'>';'>=';'in' do.
        expression_take ''
        right =. parse_sum ''
        left =. operator expression_node (<left),<right
    end.
    left
)
parse_sum =: 3 : 0
    left =. parse_product ''
    while. (<expression_peek '')e.'+';'-' do.
        operator =. expression_take ''
        right =. parse_product ''
        left =. operator expression_node (<left),<right
    end.
    left
)
parse_product =: 3 : 0
    left =. parse_unary ''
    while. '*'-:expression_peek '' do.
        expression_take ''
        right =. parse_unary ''
        left =. '*'expression_node (<left),<right
    end.
    left
)
parse_unary =: 3 : 0
    if. '-'-:expression_peek '' do.
        expression_take ''
        '-'expression_node <parse_unary ''
    else.
        parse_primary ''
    end.
)
parse_primary =: 3 : 0
    token =. expression_take ''
    if. ({.token)e.'0123456789' do.
        literal_node 0 value parse_int token
    elseif. '"'={.token do.
        literal_node 1 value }:}.token
    elseif. (<token)e.'true';'false' do.
        literal_node 2 value token-:'true'
    elseif. token-:'it' do.
        'it'expression_node 0$a:
    elseif. '.'e.token do.
        (<'attribute'),(<token),<0$a:
    elseif. token-:'(' do.
        result =. parse_disjunction ''
        expression_take ''
        result
    elseif. token-:'[' do.
        elements =. 0$a:
        while. -.']'-:expression_peek '' do.
            elements =. elements,<}:}.expression_take ''
            if. -.']'-:expression_peek '' do.
                expression_take ''
            end.
        end.
        expression_take ''
        literal_node 3 value elements
    else.
        expression_take ''
        arguments =. 0$a:
        while. -.')'-:expression_peek '' do.
            arguments =. arguments,<parse_disjunction ''
            if. -.')'-:expression_peek '' do.
                expression_take ''
            end.
        end.
        expression_take ''
        token expression_node arguments
    end.
)
