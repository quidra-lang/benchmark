node_tag =: 3 : '0{::y{::SyntaxNodes'
node_first =: 3 : '1{::y{::SyntaxNodes'
node_last =: 3 : '2{::y{::SyntaxNodes'
node_level =: 3 : '3{::y{::SyntaxNodes'
node_data =: 3 : '4{::y{::SyntaxNodes'
new_node =: 4 : 0
    number =. #SyntaxNodes
    SyntaxNodes =: SyntaxNodes,<(<x),y
    number
)
peek_token =: 3 : 'ParsePosition{::Tokens'
peek_text =: 3 : '1{::peek_token '''''
parse_at =: 3 : '(,y)-:peek_text '''''
parse_fail =: 3 : 0
    token =. peek_token ''
    actual =. 'end of file'
    if. -.'end'-:0{::token do.
        apostrophe =. 39{a.
        actual =. apostrophe,(1{::token),apostrophe
    end.
    ParseError =: (<2{::token),(<3{::token),<'expected ',y,', found ',actual
    13!:8 3
)
advance_token =: 3 : 0
    number =. ParsePosition
    ParsePosition =: ParsePosition+1
    number
)
parse_take =: 3 : 0
    if. -.parse_at y do.
        apostrophe =. 39{a.
        parse_fail apostrophe,(,y),apostrophe
    end.
    advance_token ''
)
parse_type =: 3 : 0
    if. -.(<peek_text '')e.TypeNames do. parse_fail 'type' end.
    advance_token ''
)
parse_identifier =: 3 : 0
    if. -.'identifier'-:0{::peek_token '' do. parse_fail 'identifier' end.
    advance_token ''
)
allow_comments =: 3 : 0
    token =. y{::Tokens
    token =. (<1)7}token
    Tokens =: (<token)y}Tokens
)
parse_list =: 3 : 0
    'opening closing role' =. y
    left =. parse_take opening
    elements =. commas =. i.0
    trailing =. _1
    if. -.parse_at closing do.
        while. 1 do.
            select. role
            case. 'parameter' do. element =. parse_parameter ''
            case. 'argument' do. element =. parse_expression ''
            case. 'initializer' do. element =. parse_initializer ''
            end.
            elements =. elements,element
            allow_comments node_first element
            if. -.parse_at ',' do. break. end.
            comma =. parse_take ','
            if. (role-:'initializer')*.parse_at closing do.
                trailing =. comma
                token =. comma{::Tokens
                Tokens =: (<(<1)8}token)comma}Tokens
                break.
            end.
            commas =. commas,comma
        end.
    end.
    right =. parse_take closing
    data =. (<left),(<right),(<elements),(<commas),(<trailing),<role
    'list'new_node(<left),(<right),(<8),<data
)
parse_parameter =: 3 : 0
    typ =. parse_type ''
    name =. parse_identifier ''
    brackets =. 0 2$0
    while. parse_at '[' do.
        left =. parse_take '['
        right =. parse_take ']'
        brackets =. brackets,left,right
    end.
    data =. (<typ),(<name),<brackets
    'parameter'new_node(<typ),(<ParsePosition-1),(<8),<data
)
parse_variable =: 3 : 0
    'typ name semicolon' =. y
    dimensions =. 0$a:
    while. parse_at '[' do.
        left =. parse_take '['
        expression =. _1
        if. -.parse_at ']' do. expression =. parse_expression '' end.
        right =. parse_take ']'
        dimensions =. dimensions,<left,expression,right
    end.
    equals =. initializer =. semi =. _1
    if. parse_at '=' do.
        equals =. parse_take '='
        initializer =. parse_initializer ''
    end.
    if. semicolon do. semi =. parse_take ';' end.
    data =. (<typ),(<name),(<dimensions),(<equals),(<initializer),<semi
    'variable'new_node(<typ),(<ParsePosition-1),(<8),<data
)
parse_initializer =: 3 : 0
    if. parse_at '{' do.
        parse_list(<,'{'),(<,'}'),<'initializer'
    else.
        parse_expression ''
    end.
)
parse_item =: 3 : 0
    typ =. parse_type ''
    allow_comments typ
    name =. parse_identifier ''
    if. parse_at '(' do.
        parameters =. parse_list(<,'('),(<,')'),<'parameter'
        body =. parse_block ''
        data =. typ;name;parameters;body
        'function'new_node(<typ),(<node_last body),(<8),<data
    else.
        parse_variable typ,name,1
    end.
)
parse_block =: 3 : 0
    left =. parse_take '{'
    statements =. i.0
    while. (-.parse_at '}')*.-.'end'-:0{::peek_token '' do.
        statement =. parse_statement ''
        statements =. statements,statement
        allow_comments node_first statement
    end.
    right =. parse_take '}'
    allow_comments right
    data =. (<left),(<right),<statements
    'block'new_node(<left),(<right),(<8),<data
)
parse_body =: 3 : 0
    body =. parse_statement ''
    if. -.'block'-:node_tag body do. allow_comments node_first body end.
    body
)
parse_if =: 3 : 0
    keyword =. parse_take 'if'
    left =. parse_take '('
    condition =. parse_expression ''
    right =. parse_take ')'
    body =. parse_body ''
    otherwise =. alternative =. _1
    if. parse_at 'else' do.
        otherwise =. parse_take 'else'
        if. parse_at 'if' do.
            alternative =. parse_if ''
        else.
            alternative =. parse_body ''
        end.
    end.
    data =. keyword;left;condition;right;body;otherwise;alternative
    'if'new_node(<keyword),(<ParsePosition-1),(<8),<data
)
parse_while =: 3 : 0
    keyword =. parse_take 'while'
    left =. parse_take '('
    condition =. parse_expression ''
    right =. parse_take ')'
    body =. parse_body ''
    data =. keyword;left;condition;right;body
    'while'new_node(<keyword),(<node_last body),(<8),<data
)
parse_for =: 3 : 0
    keyword =. parse_take 'for'
    left =. parse_take '('
    initial =. condition =. update =. _1
    if. -.parse_at ';' do.
        if. (<peek_text '')e.TypeNames do.
            typ =. parse_type ''
            name =. parse_identifier ''
            initial =. parse_variable typ,name,0
        else.
            initial =. parse_simple ''
        end.
    end.
    first_semi =. parse_take ';'
    if. -.parse_at ';' do. condition =. parse_expression '' end.
    second_semi =. parse_take ';'
    if. -.parse_at ')' do. update =. parse_simple '' end.
    right =. parse_take ')'
    body =. parse_body ''
    data =. keyword;left;initial;first_semi;condition;second_semi;update;right;body
    'for'new_node(<keyword),(<node_last body),(<8),<data
)
parse_switch =: 3 : 0
    keyword =. parse_take 'switch'
    left =. parse_take '('
    condition =. parse_expression ''
    right =. parse_take ')'
    opening =. parse_take '{'
    clauses =. i.0
    while. (<peek_text '')e.'case';'default' do.
        label =. advance_token ''
        allow_comments label
        value =. _1
        if. 'case'-:1{::label{::Tokens do. value =. parse_expression '' end.
        colon =. parse_take ':'
        statements =. i.0
        while. 1 do.
            if. ((<peek_text '')e.('case';'default'),<,'}')+.'end'-:0{::peek_token '' do.
                break.
            end.
            statement =. parse_statement ''
            statements =. statements,statement
            allow_comments node_first statement
        end.
        data =. (<label),(<value),(<colon),<statements
        clause =. 'clause'new_node(<label),(<ParsePosition-1),(<8),<data
        clauses =. clauses,clause
    end.
    closing =. parse_take '}'
    allow_comments closing
    data =. (<keyword),(<left),(<condition),(<right),(<opening),(<closing),<clauses
    'switch'new_node(<keyword),(<closing),(<8),<data
)
parse_statement =: 3 : 0
    text =. peek_text ''
    if. parse_at '{' do. parse_block '' return. end.
    if. (<text)e.TypeNames do.
        typ =. parse_type ''
        name =. parse_identifier ''
        parse_variable typ,name,1 return.
    end.
    select. text
    case. 'if' do. parse_if ''
    case. 'while' do. parse_while ''
    case. 'for' do. parse_for ''
    case. 'switch' do. parse_switch ''
    case. 'return' do.
        keyword =. parse_take 'return'
        expression =. _1
        if. -.parse_at ';' do. expression =. parse_expression '' end.
        semi =. parse_take ';'
        'return'new_node(<keyword),(<semi),(<8),<keyword;expression;semi
    case. 'break';'continue' do.
        keyword =. advance_token ''
        semi =. parse_take ';'
        'flow'new_node(<keyword),(<semi),(<8),<keyword;semi
    case. do.
        expression =. parse_simple ''
        semi =. parse_take ';'
        'simple_stmt'new_node(<node_first expression),(<semi),(<8),<expression;semi
    end.
)
parse_simple =: 3 : 0
    left =. parse_expression ''
    if. (<peek_text '')e.AssignmentSymbols do.
        operator =. advance_token ''
        right =. parse_expression ''
        'assign'new_node(<node_first left),(<node_last right),(<8),<left;operator;right
    else.
        'expr_stmt'new_node(<node_first left),(<node_last left),(<8),<,left
    end.
)
parse_expression =: 3 : 0
    condition =. parse_binary 1
    if. parse_at '?' do.
        question =. parse_take '?'
        yes =. parse_expression ''
        colon =. parse_take ':'
        no =. parse_expression ''
        data =. condition;question;yes;colon;no
        'conditional'new_node(<node_first condition),(<node_last no),(<0),<data
    else.
        condition
    end.
)
parse_binary =: 3 : 0
    if. y>6 do. parse_unary '' return. end.
    left =. parse_binary y+1
    operators =. '||';'&&';'== !=';'< <= > >=';'+ -';'* / %'
    accepted =. <;._1 ' ',(y-1){::operators
    while. (<peek_text '')e.accepted do.
        operator =. advance_token ''
        right =. parse_binary y+1
        data =. left;operator;right
        left =. 'binary'new_node(<node_first left),(<node_last right),(<y),<data
    end.
    left
)
parse_unary =: 3 : 0
    if. (<peek_text '')e.(<,'-'),<,'!' do.
        operator =. advance_token ''
        operand =. parse_unary ''
        'unary'new_node(<operator),(<node_last operand),(<7),<operator;operand return.
    end.
    target =. parse_primary ''
    while. 1 do.
        if. parse_at '(' do.
            arguments =. parse_list(<,'('),(<,')'),<'argument'
            target =. 'call'new_node(<node_first target),(<node_last arguments),(<8),<target;arguments
        elseif. parse_at '[' do.
            left =. parse_take '['
            index =. parse_expression ''
            right =. parse_take ']'
            target =. 'index'new_node(<node_first target),(<right),(<8),<target;left;index;right
        elseif. parse_at '.' do.
            dot =. parse_take '.'
            member =. parse_identifier ''
            target =. 'member'new_node(<node_first target),(<member),(<8),<target;dot;member
        else.
            break.
        end.
    end.
    target
)
parse_primary =: 3 : 0
    token =. peek_token ''
    if. ((0{token)e.;:'identifier number string')+.((1{token)e.'true';'false') do.
        number =. advance_token ''
        'primary'new_node(<number),(<number),(<8),<,number
    elseif. parse_at '(' do.
        left =. parse_take '('
        inner =. parse_expression ''
        right =. parse_take ')'
        'paren'new_node(<left),(<right),(<8),<left;inner;right
    else.
        parse_fail 'expression'
    end.
)
parse_program =: 3 : 0
    SyntaxNodes =: 0$a:
    ParsePosition =: 0
    ParseError =: 0$a:
    items =. i.0
    while. -.'end'-:0{::peek_token '' do.
        items =. items,parse_item ''
    end.
    items
)
