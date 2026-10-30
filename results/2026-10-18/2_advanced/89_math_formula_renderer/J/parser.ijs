check_braces =: 3 : 0
    stack =. i.0
    for_token. y do.
        'kind value column' =. >token
        if. kind-:'{' do.
            stack =. stack,column
        elseif. kind-:'}' do.
            if. 0=#stack do.
                (<column),<'unmatched }' return.
            end.
            stack =. }:stack
        end.
    end.
    if. #stack do.
        (<{:stack),<'unclosed {'
    else.
        0$a:
    end.
)
create_node =: 4 : 0
    number =. #NodePool
    NodePool =: NodePool,<(<x),y
    number
)
collapse_nodes =: 3 : 0
    if. 1=#y do.
        {.y
    else.
        'row'create_node(<y),(<''),<0
    end.
)
parser_peek =: 3 : 'ParserPosition{::ParserTokens'
parser_take =: 3 : 0
    token =. parser_peek ''
    if. -.'eof'-:0{::token do.
        ParserPosition =: ParserPosition+1
    end.
    token
)
parse_fail =: 4 : 0
    if. 0=#ParserError do.
        ParserError =: (<x),<y
    end.
    _1
)
unexpected_token =: 3 : 0
    'kind value column' =. parser_peek ''
    select. kind
    case. 'right' do. message =. 'unexpected \right'
    case. 'end' do. message =. 'unexpected \end'
    case. '&' do. message =. 'misplaced &'
    case. 'newline' do. message =. 'misplaced \\'
    end.
    column parse_fail message
)
read_element_list =: 3 : 0
    'top index' =. y
    elements =. i.0
    while. 0=#ParserError do.
        token =. parser_peek ''
        'kind value column' =. token
        if. (<kind)e.('}';'&';'newline';'right';'end';'eof') do.
            break.
        end.
        if. index*.('symbol'-:kind)*.value-:,']' do.
            break.
        end.
        if. (<kind)e.'tag';'label' do.
            if. -.top do.
                column parse_fail 'misplaced \',kind
                break.
            end.
            previous =. ParserTag
            if. kind-:'label' do.
                previous =. ParserLabel
            end.
            if. #previous do.
                column parse_fail 'duplicate \',kind
                break.
            end.
            token =. parser_take ''
            if. kind-:'tag' do.
                ParserTag =: token
            else.
                ParserLabel =: token
            end.
            continue.
        end.
        node =. read_element ''
        if. 0=#ParserError do.
            elements =. elements,node
        end.
    end.
    elements
)
read_element =: 3 : 0
    token =. parser_peek ''
    kind =. 0{::token
    if. (<kind)e.'^';'_' do.
        base =. collapse_nodes i.0
    else.
        base =. read_nucleus ''
    end.
    if. #ParserError do.
        _1 return.
    end.
    sub =. _1
    sup =. _1
    while. 1 do.
        token =. parser_peek ''
        'kind value column' =. token
        if. -.(<kind)e.'^';'_' do.
            break.
        end.
        parser_take ''
        if. kind-:'^' do.
            if. sup~:_1 do.
                column parse_fail 'double superscript' return.
            end.
            sup =. read_argument '^'
        else.
            if. sub~:_1 do.
                column parse_fail 'double subscript' return.
            end.
            sub =. read_argument '_'
        end.
        if. #ParserError do.
            _1 return.
        end.
    end.
    if. (sub=_1)*.sup=_1 do.
        base
    else.
        'script'create_node(<base,sub,sup),(<''),<0
    end.
)
read_argument =: 3 : 0
    token =. parser_peek ''
    kind =. 0{::token
    allowed =. ('identifier';'number';'symbol';'command';'text';'eqref'),('{';'frac';'binom';'overset';'underset';'sqrt';'accent')
    if. (<kind)e.allowed do.
        read_nucleus ''
    else.
        (2{::token)parse_fail 'missing argument for ',y
    end.
)
read_delimiter =: 3 : 0
    'kind value column' =. parser_take ''
    if. kind-:'symbol' do.
        if. (1=#value)*.({.value)e.'()[]|.' do.
            value return.
        end.
    elseif. kind-:'command' do.
        if. (<value)e.'\{';'\}' do.
            value return.
        end.
    end.
    column parse_fail 'invalid delimiter'
)
read_nucleus =: 3 : 0
    'kind value column' =. parser_take ''
    if. (<kind)e.;:'identifier number symbol command text eqref' do.
        if. kind-:'eqref' do.
            kind =. 'reference'
        end.
        kind create_node(<i.0),(<value),<column return.
    end.
    select. kind
    case. '{' do.
        elements =. read_element_list 0 0
        if. #ParserError do.
            _1 return.
        end.
        if. -.'}'-:0{::parser_peek '' do.
            unexpected_token '' return.
        end.
        parser_take ''
        collapse_nodes elements
    case. 'frac';'binom';'overset';'underset' do.
        first =. read_argument '\',kind
        if. #ParserError do.
            _1 return.
        end.
        second =. read_argument '\',kind
        if. #ParserError do.
            _1 return.
        end.
        kind create_node(<first,second),(<''),<0
    case. 'sqrt' do.
        index =. _1
        token =. parser_peek ''
        if. ('symbol'-:0{::token)*.(1{::token)-:,'[' do.
            opening =. parser_take ''
            elements =. read_element_list 0 1
            if. #ParserError do.
                _1 return.
            end.
            token =. parser_peek ''
            if. -.('symbol'-:0{::token)*.(1{::token)-:,']' do.
                (2{::opening)parse_fail 'missing ]' return.
            end.
            parser_take ''
            index =. collapse_nodes elements
        end.
        body =. read_argument '\sqrt'
        if. #ParserError do.
            _1 return.
        end.
        if. index=_1 do.
            'sqrt'create_node(<,body),(<''),<0
        else.
            'root'create_node(<index,body),(<''),<0
        end.
    case. 'accent' do.
        body =. read_argument '\',value
        if. #ParserError do.
            _1 return.
        end.
        'accent'create_node(<,body),(<value),<0
    case. 'left' do.
        left =. read_delimiter ''
        if. #ParserError do.
            _1 return.
        end.
        elements =. read_element_list 0 0
        if. #ParserError do.
            _1 return.
        end.
        if. -.'right'-:0{::parser_peek '' do.
            column parse_fail 'missing \right' return.
        end.
        closing =. parser_take ''
        right =. read_delimiter ''
        if. #ParserError do.
            _1 return.
        end.
        child =. collapse_nodes elements
        delimiters =. (<left),<right
        'delim'create_node(<,child),(<delimiters),<2{::closing
    case. 'begin' do.
        read_matrix(<value),<column
    end.
)
read_matrix =: 3 : 0
    'environment column' =. y
    rows =. ,<i.0
    while. 0=#ParserError do.
        elements =. read_element_list 0 0
        if. #ParserError do.
            _1 return.
        end.
        cell =. collapse_nodes elements
        index =. (#rows)-1
        rows =. (<(index{::rows),cell)index}rows
        'kind value closing' =. parser_take ''
        if. kind-:'&' do.
            continue.
        elseif. kind-:'newline' do.
            rows =. rows,<i.0
            continue.
        elseif. -.kind-:'end' do.
            column parse_fail 'missing \end' return.
        elseif. -.value-:environment do.
            closing parse_fail 'mismatched \end' return.
        end.
        break.
    end.
    if. 1<#rows do.
        last =. _1{::rows
        if. 1=#last do.
            node =. ({.last){::NodePool
            if. ('row'-:0{::node)*.0=#1{::node do.
                rows =. }:rows
            end.
        end.
    end.
    columns =. >./#&>rows
    for_i. i.#rows do.
        row =. i{::rows
        while. (#row)<columns do.
            row =. row,collapse_nodes i.0
        end.
        rows =. (<row)i}rows
    end.
    'matrix'create_node(<rows),(<environment),<0
)
parse_formula =: 3 : 0
    ParserTokens =: y
    ParserPosition =: 0
    ParserTag =: 0$a:
    ParserLabel =: 0$a:
    ParserError =: check_braces y
    NodePool =: 0$a:
    elements =. i.0
    if. 0=#ParserError do.
        elements =. read_element_list 1 0
        if. 0=#ParserError do.
            if. -.'eof'-:0{::parser_peek '' do.
                unexpected_token ''
            end.
        end.
    end.
    (<NodePool),(<elements),(<ParserTag),(<ParserLabel),<ParserError
)
