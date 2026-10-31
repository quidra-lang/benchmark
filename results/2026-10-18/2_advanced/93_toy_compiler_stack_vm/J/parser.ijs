TypeNames =: ;:'int bool void'
OperatorGroups =: '||';'&&';'== !=';'< <= > >=';'+ -';'* / %'
node_kind =: 3 : '0{::y{::Nodes'
node_position =: 3 : '1{::y{::Nodes'
node_children =: 3 : '2{::y{::Nodes'
node_value =: 3 : '3{::y{::Nodes'
node_extra =: 3 : '4{::y{::Nodes'
node_type =: 3 : '5{::y{::Nodes'
node_referent =: 3 : '6{::y{::Nodes'
new_node =: 4 : 0
    number =. #Nodes
    Nodes =: Nodes,<(<x),y,(<''),(<_1),<_1
    number
)
set_node =: 4 : 0
    'number value' =. y
    node =. number{::Nodes
    Nodes =: (<(<value)x}node)number}Nodes
)
declaration_name =: 3 : '0{::node_extra y'
declaration_position =: 3 : '1{::node_extra y'
declaration_type =: 3 : '2{::node_extra y'
declaration_size =: 3 : '3{::node_extra y'
peek_token =: 3 : 'ParsePosition{::Tokens'
peek_text =: 3 : '1{::peek_token '''''
parser_at =: 3 : '(,y)-:peek_text '''''
syntax_fail =: 3 : 0
    'kind spelling position' =. peek_token ''
    message =. 'unexpected end of program'
    if. -.kind-:'end' do.
        quote =. 39{a.
        message =. 'unexpected ',quote,spelling,quote
    end.
    compile_fail(<'syntax'),(<position),<message
)
parser_take =: 3 : 0
    token =. peek_token ''
    ParsePosition =: ParsePosition+1
    token
)
parser_expect =: 3 : 0
    if. -.parser_at y do. syntax_fail '' end.
    parser_take ''
)
parser_identifier =: 3 : 0
    if. -.'identifier'-:0{::peek_token '' do. syntax_fail '' end.
    parser_take ''
)
read_head =: 3 : 0
    if. -.(<peek_text '')e.TypeNames do. syntax_fail '' end.
    typ =. parser_take ''
    name =. parser_identifier ''
    extra =. (<1{::name),(<2{::name),(<1{::typ),(<_1),<i.0
    (<2{::typ),<extra
)
read_program =: 3 : 0
    declarations =. i.0
    while. -.'end'-:0{::peek_token '' do.
        'position extra' =. read_head ''
        if. parser_at '(' do.
            parser_expect '('
            parameters =. i.0
            if. -.parser_at ')' do.
                while. 1 do.
                    'parameter_position parameter_extra' =. read_head ''
                    parameter =. 'parameter'new_node(<parameter_position),(<i.0),(<' '),<parameter_extra
                    parameters =. parameters,parameter
                    if. -.parser_at ',' do. break. end.
                    parser_expect ','
                end.
            end.
            parser_expect ')'
            body =. read_block ''
            node =. 'function'new_node(<position),(<,body),(<parameters),<extra
        else.
            initializer =. i.0
            if. parser_at '[' do.
                parser_expect '['
                if. -.'integer'-:0{::peek_token '' do. syntax_fail '' end.
                token =. parser_take ''
                size =. ".(1{::token),'x'
                extra =. (<size)3}extra
                extra =. (<2{::token)4}extra
                parser_expect ']'
            elseif. parser_at '=' do.
                parser_expect '='
                initializer =. ,read_expression 0
            end.
            parser_expect ';'
            node =. 'global'new_node(<position),(<initializer),(<''),<extra
        end.
        declarations =. declarations,node
    end.
    declarations
)
read_declaration =: 3 : 0
    'position extra' =. read_head ''
    initializer =. i.0
    if. y do.
        parser_expect '='
        initializer =. ,read_expression 0
    else.
        if. parser_at '=' do.
            parser_expect '='
            initializer =. ,read_expression 0
        end.
        parser_expect ';'
    end.
    'declaration'new_node(<position),(<initializer),(<''),<extra
)
read_block =: 3 : 0
    opening =. parser_expect '{'
    statements =. i.0
    while. -.parser_at '}' do.
        if. (<peek_text '')e.TypeNames do.
            statement =. read_declaration 0
        else.
            statement =. read_statement ''
        end.
        statements =. statements,statement
    end.
    closing =. parser_expect '}'
    'block'new_node(<2{::opening),(<statements),(<2{::closing),<''
)
read_statement =: 3 : 0
    token =. peek_token ''
    text =. 1{::token
    position =. 2{::token
    if. parser_at '{' do. read_block '' return. end.
    select. text
    case. 'if';'while' do.
        parser_take ''
        parser_expect '('
        condition =. read_expression 0
        parser_expect ')'
        body =. read_statement ''
        if. text-:'while' do.
            'while'new_node(<position),(<condition,body),(<''),<''
        else.
            alternative =. _1
            if. parser_at 'else' do.
                parser_take ''
                alternative =. read_statement ''
            end.
            'if'new_node(<position),(<condition,body,alternative),(<''),<''
        end.
    case. 'for' do.
        parser_take ''
        parser_expect '('
        initial =. condition =. update =. _1
        if. (<peek_text '')e.TypeNames do.
            initial =. read_declaration 1
        elseif. -.parser_at ';' do.
            initial =. read_simple ''
        end.
        parser_expect ';'
        if. -.parser_at ';' do. condition =. read_expression 0 end.
        parser_expect ';'
        if. -.parser_at ')' do. update =. read_simple '' end.
        parser_expect ')'
        body =. read_statement ''
        'for'new_node(<position),(<initial,condition,update,body),(<''),<''
    case. 'break';'continue' do.
        parser_take ''
        parser_expect ';'
        text new_node(<position),(<i.0),(<' '),<''
    case. 'return' do.
        parser_take ''
        children =. i.0
        if. -.parser_at ';' do. children =. ,read_expression 0 end.
        parser_expect ';'
        'return'new_node(<position),(<children),(<''),<''
    case. 'print' do.
        parser_take ''
        parser_expect '('
        arguments =. ,read_expression 0
        while. parser_at ',' do.
            parser_take ''
            arguments =. arguments,read_expression 0
        end.
        parser_expect ')'
        parser_expect ';'
        'print'new_node(<position),(<arguments),(<''),<''
    case. do.
        if. ('identifier'-:0{::token)+.text-:'read' do.
            statement =. read_simple ''
            parser_expect ';'
            statement
        else.
            syntax_fail ''
        end.
    end.
)
read_simple =: 3 : 0
    token =. peek_token ''
    if. -.('identifier'-:0{::token)+.(1{::token)-:'read' do. syntax_fail '' end.
    expression =. read_primary ''
    if. (<node_kind expression)e.'call';'read' do.
        'call_statement'new_node(<node_position expression),(<,expression),(<''),<''
    else.
        parser_expect '='
        index =. _1
        if. 'array'-:node_kind expression do. index =. {.node_children expression end.
        right =. read_expression 0
        'assignment'new_node(<node_position expression),(<index,right),(<node_value expression),<''
    end.
)
read_expression =: 3 : 0
    if. y=6 do.
        if. (<peek_text '')e.(<,'-'),<,'!' do.
            operator =. parser_take ''
            operand =. read_expression 6
            'unary'new_node(<2{::operator),(<,operand),(<1{::operator),<'' return.
        end.
        read_primary '' return.
    end.
    result =. read_expression y+1
    operators =. <;._1 ' ',y{::OperatorGroups
    while. (<peek_text '')e.operators do.
        operator =. parser_take ''
        right =. read_expression y+1
        result =. 'binary'new_node(<2{::operator),(<result,right),(<1{::operator),<''
    end.
    result
)
read_primary =: 3 : 0
    'kind text position' =. peek_token ''
    if. kind-:'integer' do.
        parser_take ''
        'integer'new_node(<position),(<i.0),(<".text,'x'),<'' return.
    elseif. (<text)e.'true';'false' do.
        parser_take ''
        'boolean'new_node(<position),(<i.0),(<text-:'true'),<'' return.
    elseif. text-:'read' do.
        parser_take ''
        parser_expect '('
        parser_expect ')'
        'read'new_node(<position),(<i.0),(<''),<'' return.
    elseif. parser_at '(' do.
        parser_take ''
        result =. read_expression 0
        parser_expect ')'
        result return.
    elseif. kind-:'identifier' do.
        parser_take ''
        if. parser_at '(' do.
            parser_take ''
            arguments =. i.0
            if. -.parser_at ')' do.
                arguments =. ,read_expression 0
                while. parser_at ',' do.
                    parser_take ''
                    arguments =. arguments,read_expression 0
                end.
            end.
            parser_expect ')'
            'call'new_node(<position),(<arguments),(<text),<'' return.
        elseif. parser_at '[' do.
            parser_take ''
            index =. read_expression 0
            parser_expect ']'
            'array'new_node(<position),(<,index),(<text),<'' return.
        end.
        'variable'new_node(<position),(<i.0),(<text),<'' return.
    end.
    syntax_fail ''
)
expression_children =: 3 : 0
    if. (<node_kind y)e.;:'binary unary array call' do. node_children y else. i.0 end.
)
statement_children =: 3 : 0
    children =. node_children y
    select. node_kind y
    case. 'block' do. children
    case. 'if' do. children =. }.children
    case. 'while' do. children =. ,1{children
    case. 'for' do. children =. 0 2 3{children
    case. do. i.0 return.
    end.
    children#~children~:_1
)
