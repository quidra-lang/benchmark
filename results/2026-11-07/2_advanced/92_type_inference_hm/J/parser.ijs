OperatorNames =: <;._1 ' || && = <> < > <= >= :: ^ + - * / mod'
OperatorPrecedence =: 1 2 3 3 3 3 3 3 4 4 5 5 6 6 6
OperatorRight =: 1 1 0 0 0 0 0 0 1 1 0 0 0 0 0
node_kind =: 3 : '0{::y{::Nodes'
node_position =: 3 : '1{::y{::Nodes'
node_children =: 3 : '2{::y{::Nodes'
node_value =: 3 : '3{::y{::Nodes'
node_type =: 3 : '4{::y{::Nodes'
new_node =: 4 : 0
    number =. #Nodes
    Nodes =: Nodes,<(<x),y,<_1
    number
)
peek_token =: 3 : 'ParseIndex{::Tokens'
peek_kind =: 3 : '0{::peek_token '''''
parser_at =: 3 : '(,y)-:peek_kind '''''
parser_name =: 3 : '(''identifier''-:0{::y)*.-.(1{::y)-:,''_'''
syntax_fail =: 3 : 0
    SyntaxError =: peek_token ''
    13!:8 3
)
parser_take =: 3 : 0
    if. -.parser_at y do. syntax_fail '' end.
    token =. peek_token ''
    ParseIndex =: ParseIndex+1
    token
)
parser_accept =: 3 : 0
    if. parser_at y do.
        parser_take y
    else.
        0$a:
    end.
)
read_name =: 3 : 0
    if. -.parser_name peek_token '' do. syntax_fail '' end.
    parser_take 'identifier'
)
read_binding =: 3 : 0
    name =. read_name ''
    parameters =. 0$a:
    while. parser_at 'identifier' do. parameters =. parameters,<parser_take 'identifier' end.
    parser_take '='
    expression =. read_expression ''
    for_parameter. |.parameters do.
        token =. >parameter
        expression =. 'fun'new_node(<3{::token),(<,expression),<token
    end.
    number =. #Bindings
    binding =. (<1{::name),(<3{::name),(<expression),(<0$a:),<''
    Bindings =: Bindings,<binding
    number
)
read_group =: 3 : 0
    rec =. parser_accept 'rec'
    position =. i.0
    if. #rec do. position =. 3{::rec end.
    bindings =. ,read_binding ''
    while. parser_at 'and' do.
        parser_take 'and'
        bindings =. bindings,read_binding ''
    end.
    number =. #Groups
    Groups =: Groups,<(<bindings),<position
    number
)
read_item =: 3 : 0
    if. parser_at 'val' do.
        parser_take 'val'
        name =. read_name ''
        parser_take ':'
        declared =. read_type ''
        parser_take ';;'
        (<'signature'),<(<name),<declared return.
    end.
    if. parser_at 'let' do.
        opening =. parser_take 'let'
        group =. read_group ''
        if. parser_at 'in' do.
            parser_take 'in'
            body =. read_expression ''
            expression =. 'let'new_node(<3{::opening),(<,body),<group
            item =. (<'expression'),<expression
        else.
            item =. (<'declaration'),<group
        end.
    else.
        item =. (<'expression'),<read_expression ''
    end.
    parser_take ';;'
    item
)
read_expression =: 3 : 0
    select. peek_kind ''
    case. 'let' do.
        opening =. parser_take 'let'
        group =. read_group ''
        parser_take 'in'
        body =. read_expression ''
        'let'new_node(<3{::opening),(<,body),<group
    case. 'fun' do.
        opening =. parser_take 'fun'
        parameters =. ,<parser_take 'identifier'
        while. parser_at 'identifier' do. parameters =. parameters,<parser_take 'identifier' end.
        parser_take '->'
        body =. read_expression ''
        for_parameter. |.parameters do.
            token =. >parameter
            body =. 'fun'new_node(<3{::token),(<,body),<token
        end.
        node =. body{::Nodes
        Nodes =: (<(<3{::opening)1}node)body}Nodes
        body
    case. 'if' do.
        opening =. parser_take 'if'
        condition =. read_expression ''
        parser_take 'then'
        yes =. read_expression ''
        parser_take 'else'
        no =. read_expression ''
        'if'new_node(<3{::opening),(<condition,yes,no),<''
    case. 'match' do.
        opening =. parser_take 'match'
        matched =. read_expression ''
        parser_take 'with'
        parser_accept '|'
        arms =. 0 2$0
        while. 1 do.
            pattern =. read_pattern ''
            parser_take '->'
            body =. read_expression ''
            arms =. arms,pattern,body
            if. -.parser_at '|' do. break. end.
            parser_take '|'
        end.
        'match'new_node(<3{::opening),(<,matched),<arms
    case. do. read_binary 1
    end.
)
read_binary =: 3 : 0
    expression =. read_unary ''
    while. 1 do.
        index =. OperatorNames i.<peek_kind ''
        if. index=#OperatorNames do. break. end.
        precedence =. index{OperatorPrecedence
        if. precedence<y do. break. end.
        token =. parser_take peek_kind ''
        right =. read_binary precedence+-.index{OperatorRight
        expression =. 'binary'new_node(<node_position expression),(<expression,right),<token
    end.
    expression
)
starts_atom =: 3 : 0
    token =. peek_token ''
    (parser_name token)+.(0{token)e.('integer';'string';'true';'false'),(<,'('),<,'['
)
read_unary =: 3 : 0
    if. parser_at '-' do.
        token =. parser_take '-'
        body =. read_unary ''
        'negate'new_node(<3{::token),(<,body),<token return.
    end.
    expression =. read_atom ''
    while. starts_atom '' do.
        argument =. read_atom ''
        expression =. 'apply'new_node(<node_position expression),(<expression,argument),<''
    end.
    expression
)
read_atom =: 3 : 0
    token =. peek_token ''
    'kind spelling value position' =. token
    if. (<kind)e.'integer';'string' do.
        parser_take kind
        kind new_node(<position),(<i.0),<value return.
    elseif. (<kind)e.'true';'false' do.
        parser_take kind
        'boolean'new_node(<position),(<i.0),<kind-:'true' return.
    elseif. parser_name token do.
        parser_take 'identifier'
        'name'new_node(<position),(<i.0),<spelling return.
    elseif. parser_at '(' do.
        parser_take '('
        first =. read_expression ''
        if. parser_at ',' do.
            parser_take ','
            second =. read_expression ''
            parser_take ')'
            'pair'new_node(<position),(<first,second),<'' return.
        end.
        parser_take ')'
        first return.
    elseif. parser_at '[' do.
        parser_take '['
        elements =. i.0
        if. -.parser_at ']' do.
            elements =. ,read_expression ''
            while. parser_at ';' do.
                parser_take ';'
                elements =. elements,read_expression ''
            end.
        end.
        parser_take ']'
        'list'new_node(<position),(<elements),<'' return.
    end.
    syntax_fail ''
)
read_pattern =: 3 : 0
    first =. read_pattern_atom ''
    if. parser_at '::' do.
        parser_take '::'
        second =. read_pattern ''
        'cons'new_node(<node_position first),(<first,second),<''
    else.
        first
    end.
)
read_pattern_atom =: 3 : 0
    token =. peek_token ''
    'kind spelling value position' =. token
    if. kind-:'identifier' do.
        parser_take 'identifier'
        kind =. 'name'
        if. spelling-:,'_' do. kind =. 'wildcard' end.
        kind new_node(<position),(<i.0),<spelling return.
    elseif. parser_at '-' do.
        parser_take '-'
        token =. parser_take 'integer'
        'integer'new_node(<position),(<i.0),<-2{::token return.
    elseif. (<kind)e.;:'integer string true false' do.
        read_atom '' return.
    elseif. parser_at '(' do.
        parser_take '('
        first =. read_pattern ''
        if. parser_at ',' do.
            parser_take ','
            second =. read_pattern ''
            parser_take ')'
            'pair'new_node(<position),(<first,second),<'' return.
        end.
        parser_take ')'
        first return.
    elseif. parser_at '[' do.
        parser_take '['
        elements =. i.0
        if. -.parser_at ']' do.
            elements =. ,read_pattern ''
            while. parser_at ';' do.
                parser_take ';'
                elements =. elements,read_pattern ''
            end.
        end.
        parser_take ']'
        'list'new_node(<position),(<elements),<'' return.
    end.
    syntax_fail ''
)
read_type =: 3 : 0
    first =. read_list_type ''
    if. parser_at '*' do.
        parser_take '*'
        second =. read_list_type ''
        first =. 'pair'new_node(<node_position first),(<first,second),<''
    end.
    if. parser_at '->' do.
        parser_take '->'
        second =. read_type ''
        first =. 'function'new_node(<node_position first),(<first,second),<''
    end.
    first
)
read_list_type =: 3 : 0
    expression =. read_type_atom ''
    while. parser_at 'identifier' do.
        if. -.'list'-:1{::peek_token '' do. break. end.
        parser_take 'identifier'
        expression =. 'list'new_node(<node_position expression),(<,expression),<''
    end.
    expression
)
read_type_atom =: 3 : 0
    token =. peek_token ''
    'kind spelling value position' =. token
    if. (kind-:'identifier')*.(<spelling)e.;:'int bool string' do.
        parser_take 'identifier'
        spelling new_node(<position),(<i.0),<''
    elseif. kind-:'type_variable' do.
        parser_take 'type_variable'
        'type_variable'new_node(<position),(<i.0),<spelling
    elseif. parser_at '(' do.
        parser_take '('
        expression =. read_type ''
        parser_take ')'
        expression
    else.
        syntax_fail ''
    end.
)
recover_item =: 3 : 0
    while. -.(<peek_kind '')e.';;';'EOF' do. ParseIndex =: ParseIndex+1 end.
    if. parser_at ';;' do. ParseIndex =: ParseIndex+1 end.
)
