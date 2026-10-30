ScriptPath =: >{:4!:3''
SourceDirectory =: (1+>./_1,I.ScriptPath e.'/\'){.ScriptPath
load SourceDirectory,'lexer.ijs'
load SourceDirectory,'parser.ijs'
load SourceDirectory,'doc_builder.ijs'
load SourceDirectory,'printer.ijs'
load SourceDirectory,'report.ijs'

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
split_words =: 3 : '<;._1 '' '',y'
trim_spaces =: 3 : 0
    text =. y
    while. #text do.
        if. ' '~:{:text do. break. end.
        text =. }:text
    end.
    text
)
profile =: 3 : '(ProfileKeys i.<y){::ProfileValues'
token_field =: 4 : 'x{::y{::Tokens'
set_token_field =: 4 : 0
    'number value' =. y
    token =. number{::Tokens
    Tokens =: (<(<value)x}token)number}Tokens
)
attach_comments =: 3 : 0
    next_tokens =. (#LexicalItems)$0
    following =. (#Tokens)-1
    for_i. |.i.#LexicalItems do.
        next_tokens =. following i}next_tokens
        'comment number' =. i{::LexicalItems
        if. -.comment do. following =. number end.
    end.
    previous =. _1
    for_i. i.#LexicalItems do.
        'is_comment number' =. i{::LexicalItems
        if. -.is_comment do.
            previous =. number
            continue.
        end.
        comment =. number{::Comments
        following =. i{next_tokens
        own =. 'line_comment'-:0{::comment
        if. i=(#LexicalItems)-1 do.
            own =. 1
        else.
            'next_is_comment next_number' =. (i+1){::LexicalItems
            if. next_is_comment do.
                next_line =. 2{::next_number{::Comments
            else.
                next_line =. 2 token_field next_number
            end.
            own =. own+.next_line>2{::comment
        end.
        comment =. (<own)5}comment
        Comments =: (<comment)number}Comments
        trailing =. 0
        if. previous~:_1 do.
            trailing =. ((2 token_field previous)=2{::comment)*.(2 token_field following)>2{::comment
        end.
        if. trailing do.
            6 set_token_field(<previous),<(6 token_field previous),number
        else.
            5 set_token_field(<following),<(5 token_field following),number
        end.
    end.
)
check_comment_positions =: 3 : 0
    for_i. i.#Tokens do.
        token =. i{::Tokens
        for_number. 5{::token do.
            comment =. number{::Comments
            if. (8{::token)+.(5{::comment)*.-.7{::token do.
                (<2{::comment),(<3{::comment),<'comment not allowed here' return.
            end.
        end.
    end.
    0$a:
)
comment_strings =: 3 : 0
    strings =. 0$a:
    for_number. y do. strings =. strings,<1{::number{::Comments end.
    ' 'join strings
)
pre_blank =: 3 : 0
    comments =. 5 token_field y
    if. #comments do.
        4{::({.comments){::Comments
    else.
        4 token_field y
    end.
)
separator_document =: 3 : 'doc_concat(1+y<.profile ''max_blank_lines'')$HardLineDoc'
comments_document =: 4 : 0
    pieces =. i.0
    for_i. i.#y do.
        comment =. (i{y){::Comments
        pieces =. pieces,doc_text 1{::comment
        following_blank =. _1
        if. i<(#y)-1 do.
            following_blank =. 4{::((i+1){y){::Comments
        elseif. x~:_1 do.
            following_blank =. 4 token_field x
        end.
        if. following_blank~:_1 do.
            if. 5{::comment do.
                pieces =. pieces,separator_document following_blank
            else.
                pieces =. pieces,doc_text ' '
            end.
        end.
    end.
    doc_concat pieces
)
token_document_with =: 4 : 0
    prefix =. y comments_document x
    pieces =. prefix,doc_text 1 token_field y
    trailing =. 6 token_field y
    if. #trailing do. pieces =. pieces,doc_suffix comment_strings trailing end.
    doc_concat pieces
)
token_document =: 3 : '(5 token_field y)token_document_with y'
split_closing_comments =: 3 : 0
    comments =. 5 token_field y
    last =. _1
    for_i. i.#comments do.
        if. 5{::(i{comments){::Comments do. last =. i end.
    end.
    (<(last+1){.comments),<(last+1)}.comments
)
closing_document =: 4 : 0
    if. 0=#y do. EmptyDoc return. end.
    pieces =. i.0
    if. x do. pieces =. ,separator_document 4{::({.y){::Comments end.
    pieces =. pieces,_1 comments_document y
    doc_concat pieces
)
parameter_document =: 3 : 0
    'typ name brackets' =. node_data y
    pieces =. (token_document typ),(doc_text ' '),token_document name
    for_pair. brackets do.
        pieces =. pieces,(token_document 0{pair),token_document 1{pair
    end.
    doc_concat pieces
)
initializer_document =: 3 : 0
    if. 'list'-:node_tag y do. list_document y else. 0 expression_document y end.
)
variable_document =: 3 : 0
    'typ name dimensions equals initializer semi' =. node_data y
    pieces =. (token_document typ),(doc_text ' '),token_document name
    for_dimension. dimensions do.
        'left expression right' =. >dimension
        pieces =. pieces,token_document left
        if. expression~:_1 do. pieces =. pieces,0 expression_document expression end.
        pieces =. pieces,token_document right
    end.
    if. equals~:_1 do.
        pieces =. pieces,SpaceDoc,(token_document equals),SpaceDoc,initializer_document initializer
    end.
    if. semi~:_1 do. pieces =. pieces,token_document semi end.
    doc_concat pieces
)
list_document =: 3 : 0
    'left right elements commas trailing role' =. node_data y
    if. 0=#elements do.
        doc_concat(token_document left),token_document right return.
    end.
    contents =. ,SoftLineDoc
    for_i. i.#elements do.
        if. i do.
            contents =. contents,(token_document(i-1){commas),LineDoc
        end.
        element =. i{elements
        if. role-:'parameter' do.
            document =. parameter_document element
        elseif. role-:'initializer' do.
            document =. initializer_document element
        else.
            document =. 0 expression_document element
        end.
        contents =. contents,document
    end.
    if. role-:'initializer' do.
        contents =. contents,doc_if_break(<,','),<''
        if. trailing~:_1 do.
            comments =. 6 token_field trailing
            if. #comments do. contents =. contents,doc_suffix comment_strings comments end.
        end.
    end.
    marker =. EmptyDoc
    if. +./(left+i.right-left){OriginalTrailing do. marker =. BreakParentDoc end.
    pieces =. marker,(token_document left),((profile 'indent')doc_nest contents),SoftLineDoc
    doc_group pieces,token_document right
)
block_document =: 3 : 0
    'left right statements' =. node_data y
    'own inline' =. split_closing_comments right
    if. (0=#statements)*.0=#own do.
        doc_concat(token_document left),inline token_document_with right return.
    end.
    contents =. ,HardLineDoc
    for_i. i.#statements do.
        statement =. i{statements
        if. i do. contents =. contents,separator_document pre_blank node_first statement end.
        contents =. contents,statement_document statement
    end.
    contents =. contents,(0<#statements)closing_document own
    pieces =. (token_document left),((profile 'indent')doc_nest contents),HardLineDoc
    doc_concat pieces,inline token_document_with right
)
body_document =: 3 : 0
    if. 'block'-:node_tag y do.
        doc_concat BraceSeparator,block_document y
    elseif. profile 'add_braces' do.
        contents =. HardLineDoc,statement_document y
        pieces =. BraceSeparator,(doc_text '{'),((profile 'indent')doc_nest contents),HardLineDoc
        doc_concat pieces,doc_text '}'
    else.
        (profile 'indent')doc_nest HardLineDoc,statement_document y
    end.
)
simple_document =: 3 : 0
    if. 'assign'-:node_tag y do.
        'left operator right' =. node_data y
        pieces =. (0 expression_document left),SpaceDoc,(token_document operator),SpaceDoc
        doc_concat pieces,0 expression_document right
    else.
        0 expression_document {.node_data y
    end.
)
if_document =: 3 : 0
    'keyword left condition right body otherwise alternative' =. node_data y
    pieces =. (token_document keyword),KeywordSpaceDoc,(token_document left),(0 expression_document condition)
    pieces =. pieces,(token_document right),body_document body
    if. otherwise~:_1 do.
        separator =. HardLineDoc
        if. KrBraces*.('block'-:node_tag body)+.profile 'add_braces' do.
            separator =. doc_text ' '
        end.
        pieces =. pieces,separator,token_document otherwise
        if. 'if'-:node_tag alternative do.
            pieces =. pieces,(doc_text ' '),if_document alternative
        else.
            pieces =. pieces,body_document alternative
        end.
    end.
    doc_concat pieces
)
while_document =: 3 : 0
    'keyword left condition right body' =. node_data y
    pieces =. (token_document keyword),KeywordSpaceDoc,(token_document left),(0 expression_document condition)
    doc_concat pieces,(token_document right),body_document body
)
for_document =: 3 : 0
    'keyword left initial first_semi condition second_semi update right body' =. node_data y
    contents =. i.0
    if. initial~:_1 do.
        if. 'variable'-:node_tag initial do.
            contents =. ,variable_document initial
        else.
            contents =. ,simple_document initial
        end.
    end.
    contents =. contents,token_document first_semi
    if. condition~:_1 do. contents =. contents,LineDoc,0 expression_document condition end.
    contents =. contents,token_document second_semi
    if. update~:_1 do. contents =. contents,LineDoc,simple_document update end.
    loop =. doc_group,doc_align contents
    pieces =. (token_document keyword),KeywordSpaceDoc,(token_document left),loop,token_document right
    doc_concat pieces,body_document body
)
clause_document =: 3 : 0
    'label value colon statements' =. node_data y
    pieces =. ,token_document label
    if. value~:_1 do. pieces =. pieces,(doc_text ' '),0 expression_document value end.
    pieces =. pieces,token_document colon
    if. #statements do.
        contents =. ,HardLineDoc
        for_i. i.#statements do.
            statement =. i{statements
            if. i do. contents =. contents,separator_document pre_blank node_first statement end.
            contents =. contents,statement_document statement
        end.
        pieces =. pieces,(profile 'indent')doc_nest contents
    end.
    doc_concat pieces
)
switch_document =: 3 : 0
    'keyword left condition right opening closing clauses' =. node_data y
    'own inline' =. split_closing_comments closing
    pieces =. (token_document keyword),KeywordSpaceDoc,(token_document left),(0 expression_document condition)
    pieces =. pieces,(token_document right),BraceSeparator,token_document opening
    if. (0=#clauses)*.0=#own do.
        doc_concat pieces,inline token_document_with closing return.
    end.
    contents =. ,HardLineDoc
    for_i. i.#clauses do.
        clause =. i{clauses
        if. i do. contents =. contents,separator_document pre_blank node_first clause end.
        contents =. contents,clause_document clause
    end.
    contents =. contents,(0<#clauses)closing_document own
    extra =. (profile 'indent')*profile 'indent_case_labels'
    doc_concat pieces,(extra doc_nest contents),HardLineDoc,inline token_document_with closing
)
statement_document =: 3 : 0
    select. node_tag y
    case. 'block' do. block_document y
    case. 'variable' do. variable_document y
    case. 'simple_stmt' do.
        'expression semi' =. node_data y
        doc_concat(simple_document expression),token_document semi
    case. 'return' do.
        'keyword expression semi' =. node_data y
        pieces =. ,token_document keyword
        if. expression~:_1 do. pieces =. pieces,(doc_text ' '),0 expression_document expression end.
        doc_concat pieces,token_document semi
    case. 'flow' do.
        'keyword semi' =. node_data y
        doc_concat(token_document keyword),token_document semi
    case. 'if' do. if_document y
    case. 'while' do. while_document y
    case. 'for' do. for_document y
    case. 'switch' do. switch_document y
    end.
)
open_expression =: 4 : 0
    number =. y
    if. -.profile 'remove_parens' do. number return. end.
    while. 'paren'-:node_tag number do.
        'left inner right' =. node_data number
        if. (node_level inner)<x do. break. end.
        if. (0<#5 token_field left)+.0<#5 token_field right do. break. end.
        first =. node_first inner
        last =. node_last inner
        6 set_token_field(<first),<(6 token_field left),6 token_field first
        6 set_token_field(<left),<i.0
        6 set_token_field(<last),<(6 token_field last),6 token_field right
        6 set_token_field(<right),<i.0
        number =. inner
    end.
    number
)
binary_document =: 3 : 0
    precedence =. node_level y
    current =. y
    operators =. operands =. i.0
    while. 'binary'-:node_tag current do.
        if. precedence~:node_level current do. break. end.
        'left operator right' =. node_data current
        operators =. operator,operators
        operands =. right,operands
        current =. precedence open_expression left
    end.
    contents =. i.0
    for_i. i.#operators do.
        contents =. contents,OperatorBreakDoc,(token_document i{operators),SpaceDoc
        contents =. contents,(precedence+1)expression_document i{operands
    end.
    doc_group(precedence expression_document current),(profile 'indent')doc_nest contents
)
conditional_document =: 3 : 0
    condition =. 0{::node_data y
    contents =. i.0
    current =. y
    while. 1 do.
        'test question yes colon no' =. node_data current
        contents =. contents,OperatorBreakDoc,(token_document question),SpaceDoc,(0 expression_document yes)
        contents =. contents,OperatorBreakDoc,(token_document colon),SpaceDoc
        following =. 0 open_expression no
        if. -.'conditional'-:node_tag following do.
            contents =. contents,0 expression_document following
            break.
        end.
        contents =. contents,1 expression_document 0{::node_data following
        current =. following
    end.
    doc_group(1 expression_document condition),(profile 'indent')doc_nest contents
)
postfix_piece =: 3 : 0
    select. node_tag y
    case. 'call' do.
        'target arguments' =. node_data y
        list_document arguments
    case. 'index' do.
        'target left index right' =. node_data y
        doc_concat(token_document left),(0 expression_document index),token_document right
    case. 'member' do.
        'target dot member' =. node_data y
        doc_concat(token_document dot),token_document member
    end.
)
postfix_document =: 3 : 0
    operators =. i.0
    current =. y
    while. (<node_tag current)e.'call';'index';'member' do.
        operators =. current,operators
        current =. 8 open_expression 0{::node_data current
    end.
    segments =. ,<i.0
    for_operation. operators do.
        if. 'member'-:node_tag operation do. segments =. segments,<i.0 end.
        last =. (#segments)-1
        segments =. (<(last{::segments),operation)last}segments
    end.
    calls =. i.0
    for_i. 1+i.(#segments)-1 do.
        for_operation. i{::segments do.
            if. 'call'-:node_tag operation do.
                calls =. calls,i
                break.
            end.
        end.
    end.
    head =. 8 expression_document current
    if. (#calls)<2 do.
        pieces =. ,head
        for_operation. operators do. pieces =. pieces,postfix_piece operation end.
        doc_concat pieces return.
    end.
    split =. {.calls
    pieces =. ,head
    contents =. i.0
    for_i. i.#segments do.
        segment =. i{::segments
        if. i<split do.
            for_operation. segment do. pieces =. pieces,postfix_piece operation end.
        else.
            contents =. contents,SoftLineDoc
            for_operation. segment do. contents =. contents,postfix_piece operation end.
        end.
    end.
    doc_group pieces,(profile 'indent')doc_nest contents
)
expression_document =: 4 : 0
    number =. x open_expression y
    select. node_tag number
    case. 'primary' do. token_document {.node_data number
    case. 'paren' do.
        'left inner right' =. node_data number
        doc_concat(token_document left),(0 expression_document inner),token_document right
    case. 'unary' do.
        'operator operand' =. node_data number
        doc_concat(token_document operator),8 expression_document operand
    case. 'binary' do. binary_document number
    case. 'conditional' do. conditional_document number
    case. 'call';'index';'member' do. postfix_document number
    end.
)
item_document =: 3 : 0
    if. 'function'-:node_tag y do.
        'typ name parameters body' =. node_data y
        pieces =. (token_document typ),(doc_text ' '),(token_document name),list_document parameters
        document =. doc_concat pieces,HardLineDoc,block_document body
        if. FirstFunctionDoc=_1 do.
            FirstFunctionDoc =: document
            FirstFunctionName =: 1 token_field name
        end.
        document
    else.
        variable_document y
    end.
)
whole_document =: 3 : 0
    pieces =. i.0
    for_i. i.#y do.
        item =. i{y
        if. i do. pieces =. pieces,separator_document pre_blank node_first item end.
        pieces =. pieces,item_document item
    end.
    comments =. 5 token_field(#Tokens)-1
    pieces =. pieces,(0<#y)closing_document comments
    doc_concat pieces
)

render_once =: 3 : 0
    error =. lex_source y
    items =. i.0
    if. 0=#error do.
        attach_comments ''
        try.
            items =. parse_program ''
        catch.
            if. 0=#ParseError do. 13!:8 3 end.
            error =. ParseError
        end.
        if. 0=#error do. error =. check_comment_positions '' end.
    end.
    if. #error do.
        ( <0$a:),(<error),(<#Comments),(<0$a:),(<_1),(<_1),<'' return.
    end.
    OriginalTrailing =: i.0
    for_token. Tokens do. OriginalTrailing =: OriginalTrailing,0<#6{::>token end.
    initialize_documents ''
    FirstFunctionDoc =: _1
    FirstFunctionName =: ''
    SpaceDoc =: doc_text (profile 'space_around_operators')$' '
    KeywordSpaceDoc =: doc_text (profile 'space_after_keyword')$' '
    OperatorBreakDoc =: SoftLineDoc
    if. profile 'space_around_operators' do. OperatorBreakDoc =: LineDoc end.
    KrBraces =: 'kr'-:profile 'brace_style'
    BraceSeparator =: HardLineDoc
    if. KrBraces do. BraceSeparator =: doc_text ' ' end.
    if. (0=#items)*.0=#5 token_field(#Tokens)-1 do.
        document =. _1
        formatted =. 0$a:
    else.
        document =. whole_document items
        formatted =. layout_document document
    end.
    (<formatted),(<0$a:),(<#Comments),(<Documents),(<document),(<FirstFunctionDoc),<FirstFunctionName
)
read_profiles =: 3 : 0
    ProfileNames =: Profiles =: 0$a:
    keys =. values =. 0$a:
    for_line. <;._2(1!:1 <'input/style.txt') do.
        line =. >line
        if. 0=#line do. continue. end.
        if. '['={.line do.
            if. #ProfileNames do. Profiles =: Profiles,<(<keys),<values end.
            ProfileNames =: ProfileNames,<}:}.line
            keys =. values =. 0$a:
        else.
            split =. line i.'='
            key =. split{.line
            value =. (split+1)}.line
            if. (<key)e.;:'width indent max_blank_lines comment_column' do.
                value =. ".value
            elseif. (<key)e.;:'space_around_operators space_after_keyword indent_case_labels add_braces remove_parens' do.
                value =. value-:'yes'
            end.
            keys =. keys,<key
            values =. values,<value
        end.
    end.
    Profiles =: Profiles,<(<keys),<values
)
read_sources =: 3 : 0
    SourceFiles =: 0$a:
    lines =. 0$a:
    header =. ''
    for_line. <;._2(1!:1 <'input/sources.txt') do.
        line =. >line
        if. '=== '-:4{.line do.
            if. #header do.
                SourceFiles =: SourceFiles,<(<header),(<name),(<style),<lines
            end.
            header =. line
            'marker name style' =. split_words line
            lines =. 0$a:
        else.
            lines =. lines,<line
        end.
    end.
    SourceFiles =: SourceFiles,<(<header),(<name),(<style),<lines
)
error_position =: 3 : 0
    'row column message' =. y
    (integer row),':',(integer column),': ',message
)
first_difference =: 4 : 0
    for_i. i.(#x)<.#y do.
        if. -.(i{::x)-:i{::y do. i+1 return. end.
    end.
    1+(#x)<.#y
)
write_lines =: 4 : 0
    text =. ''
    for_line. y do. text =. text,(>line),LF end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_profiles ''
    read_sources ''
    formatted_lines =. idempotency =. diagnostics =. trees =. changes =. 0$a:
    for_source. SourceFiles do.
        'header name style lines' =. >source
        'ProfileKeys ProfileValues' =: (ProfileNames i.<style){::Profiles
        original =. trim_spaces&.>lines
        first =. render_once lines
        'formatted error comment_count first_documents document first_function function_name' =. first
        trees =. trees,<'=== ',name
        changes =. changes,<'=== ',name
        if. #error do.
            formatted_lines =. formatted_lines,(<header),original
            idempotency =. idempotency,<name,': skipped (syntax error)'
            'row column message' =. error
            text =. name,':',(integer row),':',(integer column),': error: ',message
            diagnostics =. diagnostics,<text
            trees =. trees,<'syntax error'
            changes =. changes,<'skipped (syntax error)'
            continue.
        end.
        formatted_lines =. formatted_lines,(<header),formatted
        second =. render_once formatted
        'second_lines second_error second_comments second_documents second_doc second_function second_name' =. second
        if. #second_error do.
            text =. name,': unstable (second pass: ',(error_position second_error),')'
        elseif. formatted-:second_lines do.
            text =. name,': stable'
        else.
            text =. name,': unstable at line ',integer formatted first_difference second_lines
        end.
        idempotency =. idempotency,<text
        longest =. 0
        for_i. i.#formatted do.
            length =. #i{::formatted
            longest =. longest>.length
            if. length>profile 'width' do.
                text =. name,':',(integer i+1),': warning: line too long (',integer length
                diagnostics =. diagnostics,<text,' > ',(integer profile 'width'),')'
            end.
        end.
        Documents =: first_documents
        groups =. i.0
        if. document~:_1 do. groups =. doc_groups document end.
        broken =. forced =. 0
        for_group. groups do.
            mode =. 4{::group{::Documents
            broken =. broken+-.'flat'-:mode
            forced =. forced+'forced'-:mode
        end.
        text =. 'metrics lines=',(integer #formatted),' longest=',(integer longest),' comments=',integer comment_count
        text =. text,' groups=',(integer #groups),' broken=',(integer broken),' forced=',integer forced
        trees =. trees,<text
        if. first_function=_1 do.
            trees =. trees,<'no function'
        else.
            trees =. trees,(<'function ',function_name),0 document_tree first_function
        end.
        changes =. changes,original line_diff formatted
    end.
    if. 0=#diagnostics do. diagnostics =. <'no diagnostics' end.
    try.
        1!:5 <'output'
    catch.
    end.
    'formatted.txt'write_lines formatted_lines
    'idempotency.txt'write_lines idempotency
    'diagnostics.txt'write_lines diagnostics
    'doc_tree.txt'write_lines trees
    'changes.txt'write_lines changes
)
run ''
