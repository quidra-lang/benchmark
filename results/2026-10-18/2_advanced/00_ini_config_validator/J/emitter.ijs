MASK =: '********'
string_notation =: 3 : 0
    text =. '"'
    for_char. y do.
        select. char
        case. '\' do. text =. text,'\\'
        case. '"' do. text =. text,'\"'
        case. LF do. text =. text,'\n'
        case. HT do. text =. text,'\t'
        case. do. text =. text,char
        end.
    end.
    text,'"'
)
value_notation =: 3 : 0
    'kind item value' =. y
    select. kind
    case. 'list' do.
        pieces =. 0$a:
        for_box. value do.
            pieces =. pieces,<value_notation (<item),(<''),< >box
        end.
        '[',(', ' join pieces),']'
    case. 'string' do. string_notation value
    case. 'bool' do. value{::'false';'true'
    case. 'int';'size';'duration' do. number value
    case. do. value
    end.
)
NB. Output records are (definition; spec; value; notation; secret; kind).
shown =: 3 : 0
    if. 4{::y do. MASK else. 3{::y end.
)
origin_text =: 3 : '(0{::y),'':'',number 1{::y'
normalized_block =: 3 : 0
    lines =. <'profile ','name' get_key y
    outputs =. 'outputs' get_key y
    previous =. ''
    for_box. sort_keys table_keys outputs do.
        key =. >box
        section =. section_of key
        if. -.section-:previous do. lines =. lines,<'[',section,']' end.
        lines =. lines,<(key_name key),' = ',shown key get_key outputs
        previous =. section
    end.
    lines
)
diagnostics_block =: 3 : 0
    lines =. <'profile ',('name' get_key y),' errors ',(number 'errors' get_key y),' warnings ',number 'warnings' get_key y
    for_box. 'diagnostics' get_key y do.
        'document line code message' =. >box
        lines =. lines,<document,':',(number line),' ',code,' ',message
    end.
    lines
)
diff_block =: 3 : 0
    lines =. <'diff ',('first' get_key y),' -> ',('second' get_key y),': ',(number 'added' get_key y),' added, ',(number 'removed' get_key y),' removed, ',(number 'changed' get_key y),' changed'
    for_box. 'entries' get_key y do.
        'sign key before after' =. >box
        if. sign-:'+' do. line =. '+ ',key,' = ',shown after
        elseif. sign-:'-' do. line =. '- ',key,' = ',shown before
        else. line =. '~ ',key,': ',(shown before),' -> ',shown after end.
        lines =. lines,<line
    end.
    lines
)
report_block =: 3 : 0
    lines =. (<'profile ','name' get_key y),<'includes'
    for_box. 'tree' get_key y do.
        'depth text' =. >box
        lines =. lines,<((2+2*depth)#' '),text
    end.
    lines =. lines,<'overridden'
    outputs =. 'outputs' get_key y
    found =. 0
    for_box. sort_keys table_keys outputs do.
        key =. >box
        definition =. 0{::key get_key outputs
        history =. 3{::definition
        if. (#history)>:2 do.
            found =. 1
            lines =. lines,<'  ',key,': ',' -> ' join origin_text&.>history
        end.
    end.
    if. -.found do. lines =. lines,<'  (none)' end.
    lines =. lines,<'keys ',(number #outputs),' documents ',(number 'document_keys' get_key y),' manifest ',(number 'manifest_keys' get_key y),' defaults ',number 'default_keys' get_key y
    lines =. lines,<'dropped ',number 'dropped' get_key y
    lines,< 'errors ',(number 'errors' get_key y),' warnings ',number 'warnings' get_key y
)
write_blocks =: 4 : 0
    text =. (LF,LF) join (LF&join)&.>y
    (text,LF) 1!:2 <x
    i.0
)
write_outputs =: 3 : 0
    'profiles diffs' =. y
    if. 0=#1!:0 <'output' do. 1!:5 <'output' end.
    'output/normalized.txt' write_blocks normalized_block&.>profiles
    'output/diagnostics.txt' write_blocks diagnostics_block&.>profiles
    'output/diff.txt' write_blocks diff_block&.>diffs
    'output/report.txt' write_blocks report_block&.>profiles
    i.0
)
