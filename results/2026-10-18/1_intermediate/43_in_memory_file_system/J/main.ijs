LF =: 10{a.
Clock =: Current =: 0
NextInode =: 2
Previous =: ''
Nodes =: <(0;0;'';1;0;<i.0)
Retired =: i.0
number =: 3 : ',''0'' 8!:2 y'
lower =: 3 : 'a.{~(a.i.y)+32*y e.''ABCDEFGHIJKLMNOPQRSTUVWXYZ'''
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
terminal =: 3 : '(y,LF) 1!:2[4'
emit =: 3 : 0
    if. Streaming do. terminal y else. Output =: Output,<y end.
)
node_kind =: 3 : '0{::y{::Nodes'
node_parent =: 3 : '1{::y{::Nodes'
node_name =: 3 : '2{::y{::Nodes'
node_inode =: 3 : '3{::y{::Nodes'
node_time =: 3 : '4{::y{::Nodes'
node_data =: 3 : '5{::y{::Nodes'
setnode =: 4 : 'Nodes =: (<y) x}Nodes'
change =: 4 : 0
    'node field' =. x
    row =. node{::Nodes
    node setnode (<y) field}row
)
children =: 3 : 0
    kids =. node_data y
    names =. node_name&.><"0 kids
    (/:s:names){kids
)
child =: 4 : 0
    kids =. node_data x
    position =. (node_name&.><"0 kids)i.<y
    if. position=#kids do. _1 else. position{kids end.
)
attach =: 3 : 0
    'parent name node' =. y
    (node,1) change parent
    (node,2) change name
    (parent,5) change (node_data parent),node
    (parent,4) change Clock
)
create_node =: 3 : 0
    'parent name kind data' =. y
    node =. (#&>Nodes)i.0
    row =. kind;parent;name;NextInode;Clock;<data
    NextInode =: NextInode+1
    if. node=#Nodes do. Nodes =: Nodes,<row else. node setnode row end.
    attach parent;name;node
    node
)
detach =: 3 : 0
    parent =. node_parent y
    (parent,5) change (node_data parent)-.y
    (parent,4) change Clock
)
remove_node =: 3 : 0
    detach y
    Retired =: Retired,y
)
reclaim =: 3 : 0
    pending =. Retired
    while. #pending do.
        node =. {.pending
        pending =. }.pending
        if. 0=node_kind node do. pending =. pending,node_data node end.
        node setnode 0$a:
    end.
    Retired =: i.0
)
write_file =: 3 : 0
    'node lines append' =. y
    if. append do. lines =. (node_data node),lines end.
    (node,5) change lines
    (node,4) change Clock
)
descendant =: 4 : 0
    node =. x
    while. node~:y do.
        if. node=0 do. 0 return. end.
        node =. node_parent node
    end.
    1
)
absolute =: 3 : 0
    node =. y
    result =. ''
    while. node~:0 do.
        result =. '/',(node_name node),result
        node =. node_parent node
    end.
    if. #result do. result else. '/' end.
)
basename =: 3 : 0
    slash =. y i:'/'
    if. slash=#y do. y else. (slash+1)}.y end.
)
path_join =: 4 : 'if. x-:''/'' do. x,y else. x,''/'',y end.'
components =: 3 : 0
    parts =. <;._1 '/',y
    parts#~0<#&>parts
)

NB. Only the outer path can report an absent final component or create parents.
walk =: 3 : 0
    'path base follow original parents' =. y
    node =. base
    if. '/'={.path do. node =. 0 end.
    parts =. components path
    for_i. i.#parts do.
        if. 0~:node_kind node do. _1;_1;'';'Not a directory' return. end.
        name =. i{::parts
        if. name-:'.' do. continue. end.
        if. name-:'..' do. node =. node_parent node continue. end.
        last =. i=_1+#parts
        next =. node child name
        if. next=_1 do.
            if. original*.parents*.-.last do.
                next =. create_node node;name;0;<i.0
            else.
                parent =. _1
                if. original*.last do. parent =. node end.
                _1;parent;name;'No such file or directory' return.
            end.
        end.
        if. (2=node_kind next)*.(follow+.-.last) do.
            Expansions =: Expansions+1
            if. Expansions>8 do. _1;_1;'';'Too many levels of symbolic links' return. end.
            result =. walk (node_data next);node;1;0;0
            if. (0{::result)=_1 do. result return. end.
            next =. 0{::result
        end.
        node =. next
    end.
    node;_1;'';''
)
resolve =: 3 : 0
    'path follow parents' =. y
    Expansions =: 0
    walk path;Current;follow;1;parents
)
node_size =: 3 : 0
    data =. node_data y
    if. 1=node_kind y do. +/1+#&>data else. #data end.
)
node_links =: 3 : 0
    if. 0~:node_kind y do. 1 else. 2++/0=node_kind"0 node_data y end.
)
node_tag =: 3 : '(node_kind y){''dfl'''
parse_options =: 3 : 0
    flags =. ''
    at =. 0
    while. at<#y do.
        word =. at{::y
        if. '-'~:{.word do. break. end.
        flags =. flags,}.word
        at =. at+1
    end.
    (~.flags);<at}.y
)
bad_source =: 3 : '(<y)e.'''';''.'';''..'''
clone_tree =: 3 : 0
    pending =. ,<y
    while. #pending do.
        'source parent name' =. >{.pending
        pending =. }.pending
        kind =. node_kind source
        data =. node_data source
        if. kind=0 do. data =. i.0 end.
        copy =. create_node parent;name;kind;<data
        if. kind=0 do.
            next =. 0$a:
            for_entry. children source do. next =. next,<entry;copy;node_name entry end.
            pending =. next,pending
        end.
    end.
)
move_one =: 3 : 0
    'sourcepath destination' =. y
    name =. basename sourcepath
    if. bad_source name do. terminal 'mv: cannot move ''',sourcepath,''' to ''',destination,''': Invalid argument' return. end.
    'source unused unusedname problem' =. resolve sourcepath;0;0
    if. source=_1 do. terminal 'mv: cannot stat ''',sourcepath,''': ',problem return. end.
    'node unused unusedname problem' =. resolve destination;1;0
    directory =. 0
    if. node>:0 do. directory =. 0=node_kind node end.
    if. directory do.
        parent =. node
        target =. destination path_join name
    else.
        'node parent name problem' =. resolve destination;0;0
        if. node>:0 do.
            parent =. node_parent node
            name =. node_name node
        elseif. parent=_1 do.
            terminal 'mv: cannot move ''',sourcepath,''' to ''',destination,''': ',problem return.
        end.
        target =. destination
    end.
    existing =. parent child name
    exists =. existing>:0
    source_directory =. 0=node_kind source
    existing_directory =. 0
    if. exists do. existing_directory =. 0=node_kind existing end.
    if. source_directory*.parent descendant source do.
        terminal 'mv: cannot move ''',sourcepath,''' to a subdirectory of itself, ''',target,''''
    elseif. existing=source do. terminal 'mv: ''',sourcepath,''' and ''',target,''' are the same file'
    elseif. exists*.source_directory*.-.existing_directory do.
        terminal 'mv: cannot overwrite non-directory ''',target,''' with directory ''',sourcepath,''''
    elseif. exists*.existing_directory*.-.source_directory do.
        terminal 'mv: cannot overwrite directory ''',target,''' with non-directory ''',sourcepath,''''
    elseif. existing_directory do.
        if. #node_data existing do.
            terminal 'mv: cannot move ''',sourcepath,''' to ''',target,''': Directory not empty'
        elseif. existing=Current do.
            terminal 'mv: cannot move ''',sourcepath,''' to ''',target,''': Device or resource busy'
        else.
            remove_node existing
            detach source
            attach parent;name;source
        end.
    else.
        if. exists do. remove_node existing end.
        detach source
        attach parent;name;source
    end.
)
copy_one =: 3 : 0
    'sourcepath destination recursive' =. y
    name =. basename sourcepath
    if. bad_source name do. terminal 'cp: cannot copy ''',sourcepath,''' to ''',destination,''': Invalid argument' return. end.
    'source unused unusedname problem' =. resolve sourcepath;1;0
    if. source=_1 do. terminal 'cp: cannot stat ''',sourcepath,''': ',problem return. end.
    directory =. 0=node_kind source
    if. directory*.-.recursive do. terminal 'cp: -r not specified; omitting directory ''',sourcepath,'''' return. end.
    'node parent unusedname problem' =. resolve destination;1;0
    if. (node=_1)*.parent=_1 do.
        terminal 'cp: cannot copy ''',sourcepath,''' to ''',destination,''': ',problem return.
    end.
    target =. destination
    if. node>:0 do.
        if. 0=node_kind node do. target =. destination path_join name end.
    end.
    'node parent name problem' =. resolve target;(-.directory);0
    if. directory do.
        if. node>:0 do. terminal 'cp: cannot copy ''',sourcepath,''' to ''',target,''': File exists'
        elseif. parent descendant source do.
            terminal 'cp: cannot copy a directory, ''',sourcepath,''', into itself, ''',target,''''
        else. clone_tree source;parent;name end.
    elseif. parent>:0 do.
        create_node parent;name;1;<node_data source
    elseif. node=_1 do. terminal 'cp: cannot copy ''',sourcepath,''' to ''',target,''': ',problem
    elseif. node=source do. terminal 'cp: ''',sourcepath,''' and ''',target,''' are the same file'
    elseif. 0=node_kind node do. terminal 'cp: cannot overwrite directory ''',target,''' with non-directory ''',sourcepath,''''
    else. write_file node;(node_data source);0 end.
)

listing =: 3 : 0
    'flags paths' =. y
    if. 0=#paths do. paths =. ,<'.' end.
    for_path. paths do.
        path =. >path
        'node parent name problem' =. resolve path;(-.'l'e.flags);0
        if. node=_1 do. terminal 'ls: cannot access ''',path,''': ',problem continue. end.
        pairs =. 0$a:
        if. 0~:node_kind node do. pairs =. ,<path;node
        else.
            if. 1<#paths do. emit path,':' end.
            if. 'a'e.flags do. pairs =. ('.';node);<('..';node_parent node) end.
            for_entry. children node do.
                name =. node_name entry
                if. ('a'e.flags)+.'.'~:{.name do. pairs =. pairs,<name;entry end.
            end.
            if. 't'e.flags do.
                ids =. >1{&>pairs
                pairs =. (\:node_time"0 ids){pairs
            end.
        end.
        if. 'r'e.flags do. pairs =. |.pairs end.
        if. 0=#pairs do. continue. end.
        ids =. >1{&>pairs
        stats =. (node_links"0 ids),.(node_size"0 ids),.node_time"0 ids
        widths =. >./#&>number&.><"0 stats
        for_i. i.#pairs do.
            'name entry' =. i{::pairs
            if. -.'l'e.flags do. emit name continue. end.
            text =. ,(node_kind entry){'d-l'
            for_column. i.3 do.
                value =. number (<i,column){stats
                text =. text,' ',(-column{widths){.value
            end.
            text =. text,' ',name
            if. 2=node_kind entry do. text =. text,' -> ',node_data entry end.
            emit text
        end.
    end.
)
visits =: 3 : 0
    'node path limit' =. y
    name =. basename path
    if. path-:'/' do. name =. '/' end.
    pending =. ,<node;path;name;0
    result =. 0$a:
    while. #pending do.
        row =. >{.pending
        pending =. }.pending
        result =. result,<row
        'node path name depth' =. row
        if. (0=node_kind node)*.depth<limit do.
            next =. 0$a:
            for_entry. children node do.
                name =. node_name entry
                next =. next,<entry;(path path_join name);name;depth+1
            end.
            pending =. next,pending
        end.
    end.
    result
)
glob =: 4 : 0
    previous =. 1,(#y)#0
    for_character. x do.
        following =. (#previous)#0
        if. character='*' do.
            following =. ({.previous) 0}following
            for_i. i.#y do.
                value =. ((i+1){previous)+.i{following
                following =. value (i+1)}following
            end.
        else. following =. 0,(}:previous)*.((character='?')+.character=y) end.
        previous =. following
    end.
    {:previous
)
find_nodes =: 3 : 0
    path =. '.'
    args =. y
    if. #args do.
        if. '-'~:{.0{::args do.
            path =. 0{::args
            args =. }.args
        end.
    end.
    pattern =. type =. ''
    limit =. 1000
    for_i. 2*i.<.-:#args do.
        test =. i{::args
        value =. (i+1){::args
        if. test-:'-name' do. pattern =. value
        elseif. test-:'-type' do. type =. value
        else. limit =. 0".value end.
    end.
    'node parent name problem' =. resolve path;1;0
    if. node=_1 do. terminal 'find: ''',path,''': ',problem return. end.
    for_row. visits node;path;limit do.
        'entry display name depth' =. >row
        selected =. 1
        if. #pattern do. selected =. pattern glob name end.
        if. #type do. selected =. selected*.type-:,node_tag entry end.
        if. selected do. emit display end.
    end.
)
disk_usage =: 3 : 0
    'flags paths' =. y
    if. 0=#paths do. paths =. ,<'.' end.
    for_path. paths do.
        path =. >path
        'node parent name problem' =. resolve path;1;0
        if. node=_1 do. terminal 'du: cannot access ''',path,''': ',problem continue. end.
        amounts =. (#Nodes)#0
        pending =. ,<node;path;1;0
        while. #pending do.
            'node display show phase' =. >{.pending
            pending =. }.pending
            directory =. 0=node_kind node
            if. directory*.-.phase do.
                next =. 0$a:
                for_entry. children node do.
                    childshow =. show*.(-.'s'e.flags)*.((0=node_kind entry)+.'a'e.flags)
                    next =. next,<entry;(display path_join node_name entry);childshow;0
                end.
                pending =. next,(<node;display;show;1),pending
                continue.
            end.
            value =. node_size node
            if. directory do. value =. +/(node_data node){amounts end.
            amounts =. value node}amounts
            if. show do. emit (number value),' ',display end.
        end.
    end.
)
draw_entries =: 3 : 0
    'node prefix all' =. y
    kids =. children node
    if. -.all do. kids =. kids#~'.'~:{.&>node_name&.><"0 kids end.
    result =. 0$a:
    for_i. i.#kids do. result =. result,<(i{kids);prefix;i=_1+#kids end.
    result
)
draw_tree =: 3 : 0
    'flags paths' =. y
    path =. '.'
    if. #paths do. path =. 0{::paths end.
    'node parent name problem' =. resolve path;1;0
    if. node=_1 do. terminal 'tree: ',path,': ',problem return. end.
    if. 0~:node_kind node do. terminal 'tree: ',path,': Not a directory' return. end.
    emit path
    directories =. files =. 0
    pending =. draw_entries node;'';'a'e.flags
    while. #pending do.
        'entry prefix last' =. >{.pending
        pending =. }.pending
        text =. prefix,(last{::'|-- ';'`-- '),node_name entry
        if. 2=node_kind entry do. text =. text,' -> ',node_data entry end.
        emit text
        if. 0=node_kind entry do.
            directories =. directories+1
            prefix =. prefix,last{::'|   ';'    '
            pending =. (draw_entries entry;prefix;'a'e.flags),pending
        else. files =. files+1 end.
    end.
    dword =. 'directories'
    fword =. 'files'
    if. directories=1 do. dword =. 'directory' end.
    if. files=1 do. fword =. 'file' end.
    emit (number directories),' ',dword,', ',(number files),' ',fword
)

word_count =: 3 : 0
    if. 0=#y do. 0 return. end.
    inside =. y~:' '
    +/inside*.1,}:-.inside
)
report_counts =: 3 : 0
    'counts name' =. y
    selected =. 'lwc'e.TextFlags
    if. -. +./selected do. selected =. 3#1 end.
    text =. ' ' join number&.><"0 selected#counts
    if. #name do. text =. text,' ',name end.
    emit text
)
consume_input =: 3 : 0
    'name lines' =. y
    select. TextCommand
    case. 'cat' do.
        for_line. lines do. emit >line end.
    case. 'sort' do. SortedLines =: SortedLines,lines
    case. 'wc' do.
        counts =. (#lines),(+/word_count&>lines),+/1+#&>lines
        Totals =: Totals+counts
        report_counts counts;name
    case. 'head';'tail' do.
        signed =. ({.CountText)e.'-+'
        count =. 0".signed}.CountText
        start =. 0
        stop =. #lines
        if. TextCommand-:'head' do.
            if. signed do. stop =. 0>.stop-count else. stop =. stop<.count end.
        else.
            if. signed do. start =. stop<.0>.count-1 else. start =. 0>.stop-count end.
        end.
        for_i. start+i.stop-start do. emit i{::lines end.
    case. 'grep' do.
        prefix =. ''
        if. PrefixNames do. prefix =. name,':' end.
        count =. 0
        for_i. i.#lines do.
            line =. i{::lines
            value =. line
            if. 'i'e.TextFlags do. value =. lower value end.
            selected =. ('v'e.TextFlags)~:+./SearchPattern E.value
            if. selected do.
                count =. count+1
                if. -.'c'e.TextFlags do.
                    text =. prefix
                    if. 'n'e.TextFlags do. text =. text,(number i+1),':' end.
                    emit text,line
                end.
            end.
        end.
        if. 'c'e.TextFlags do. emit prefix,number count end.
    case. 'uniq' do.
        at =. 0
        while. at<#lines do.
            line =. at{::lines
            finish =. at+1
            while. finish<#lines do.
                if. -.line-:finish{::lines do. break. end.
                finish =. finish+1
            end.
            if. 'c'e.TextFlags do. emit (number finish-at),' ',line else. emit line end.
            at =. finish
        end.
    end.
)
numeric_prefix =: 3 : 0
    negative =. '-'={.y
    text =. negative}.y
    count =. (text e.'0123456789')i.0
    if. count=0 do. 0 return. end.
    value =. 0".count{.text
    if. negative do. -value else. value end.
)
text_command =: 4 : 0
    'command args' =. y
    TextCommand =: command
    TextFlags =: ''
    CountText =: '10'
    paths =. args
    if. (<command)e.'head';'tail' do.
        if. #args do.
            if. '-n'-:0{::args do. CountText =: 1{::args [ paths =. 2}.args end.
        end.
    else.
        'flags paths' =. parse_options args
        TextFlags =: flags
    end.
    recursive =. 0
    PrefixNames =: 0
    if. command-:'grep' do.
        SearchPattern =: 0{::paths
        paths =. }.paths
        if. 'i'e.TextFlags do. SearchPattern =: lower SearchPattern end.
        recursive =. 'r'e.TextFlags
        PrefixNames =: recursive+.1<#paths
        if. recursive*.0=#paths do. paths =. ,<'.' end.
    end.
    Totals =: 3#0
    SortedLines =: 0$a:
    if. 0=#paths do. consume_input '';<x
    else.
        for_path. paths do.
            path =. >path
            'node parent name problem' =. resolve path;1;0
            if. node=_1 do. terminal command,': ',path,': ',problem continue. end.
            if. recursive do.
                for_row. visits node;path;1000 do.
                    'entry display name depth' =. >row
                    if. 1=node_kind entry do. consume_input display;<node_data entry end.
                end.
            elseif. 0=node_kind node do. terminal command,': ',path,': Is a directory'
            else. consume_input path;<node_data node end.
        end.
    end.
    if. (command-:'wc')*.1<#paths do. report_counts Totals;'total' end.
    if. command-:'sort' do.
        ordered =. (/:s:SortedLines){SortedLines
        if. 'n'e.TextFlags do. ordered =. (/:numeric_prefix&>ordered){ordered end.
        if. 'r'e.TextFlags do. ordered =. |.ordered end.
        for_line. ordered do. emit >line end.
    end.
)

run_command =: 4 : 0
    if. 'echo '-:5{.y do. emit 5}.y return. end.
    words =. <;._1 ' ',y
    command =. 0{::words
    args =. }.words
    'flags paths' =. parse_options args
    select. command
    case. 'pwd' do. emit absolute Current
    case. 'cd' do.
        path =. '/'
        if. #args do. path =. 0{::args end.
        previous =. path-:'-'
        if. previous do.
            if. 0=#Previous do. terminal 'cd: OLDPWD not set' return. end.
            path =. Previous
        end.
        'node parent name problem' =. resolve path;1;0
        if. node=_1 do. terminal 'cd: ',path,': ',problem
        elseif. 0~:node_kind node do. terminal 'cd: ',path,': Not a directory'
        else.
            Previous =: absolute Current
            Current =: node
            if. previous do. emit absolute Current end.
        end.
    case. 'mkdir' do.
        parents =. 'p'e.flags
        for_path. paths do.
            path =. >path
            'node parent name problem' =. resolve path;0;parents
            if. parent>:0 do. create_node parent;name;0;<i.0
            elseif. node=_1 do. terminal 'mkdir: cannot create directory ''',path,''': ',problem
            else.
                existing_directory =. 0
                if. parents do.
                    'existing unused unusedname unusedproblem' =. resolve path;1;0
                    if. existing>:0 do. existing_directory =. 0=node_kind existing end.
                end.
                if. -.existing_directory do. terminal 'mkdir: cannot create directory ''',path,''': File exists' end.
            end.
        end.
    case. 'touch' do.
        for_path. args do.
            path =. >path
            'node parent name problem' =. resolve path;1;0
            if. parent>:0 do. create_node parent;name;1;<0$a:
            elseif. node=_1 do. terminal 'touch: cannot touch ''',path,''': ',problem
            else. (node,4) change Clock end.
        end.
    case. 'ls' do. listing flags;<paths
    case. 'stat' do.
        for_path. args do.
            path =. >path
            'node parent name problem' =. resolve path;0;0
            if. node=_1 do. terminal 'stat: cannot stat ''',path,''': ',problem continue. end.
            kind =. node_kind node
            type =. kind{::'directory';'regular file';'symbolic link'
            if. kind=1 do. if. 0=#node_data node do. type =. 'regular empty file' end. end.
            emit path,': ',type,', size ',(number node_size node),', inode ',(number node_inode node),', links ',(number node_links node),', modified ',number node_time node
        end.
    case. 'rm';'rmdir' do.
        removing_directory =. command-:'rmdir'
        for_path. paths do.
            path =. >path
            prefix =. 'rm: cannot remove '''
            if. removing_directory do. prefix =. 'rmdir: failed to remove ''' end.
            prefix =. prefix,path,''': '
            if. (<basename path)e.'.';'..' do.
                if. removing_directory do. terminal prefix,'Invalid argument'
                else. terminal 'rm: refusing to remove ''.'' or ''..'' directory: skipping ''',path,'''' end.
                continue.
            end.
            'node parent name problem' =. resolve path;0;0
            if. node=_1 do.
                if. (-.removing_directory)*.('f'e.flags)*.problem-:'No such file or directory' do. continue. end.
                terminal prefix,problem
                continue.
            end.
            directory =. 0=node_kind node
            if. removing_directory*.-.directory do. terminal prefix,'Not a directory'
            elseif. (-.removing_directory)*.directory*.-.'r'e.flags do. terminal prefix,'Is a directory'
            elseif. Current descendant node do. terminal prefix,'Device or resource busy'
            elseif. removing_directory*.0<#node_data node do. terminal prefix,'Directory not empty'
            else. remove_node node end.
        end.
    case. 'mv';'cp' do.
        destination =. >{:paths
        sources =. }:paths
        if. 1<#sources do.
            'node parent name problem' =. resolve destination;1;0
            directory =. 0
            if. node>:0 do. directory =. 0=node_kind node end.
            if. -.directory do. terminal command,': target ''',destination,''' is not a directory' return. end.
        end.
        for_source. sources do.
            if. command-:'mv' do. move_one (>source);destination
            else. copy_one (>source);destination;'r'e.flags end.
        end.
    case. 'ln' do.
        target =. 1{::args
        path =. 2{::args
        'node parent name problem' =. resolve path;0;0
        if. parent>:0 do. create_node parent;name;2;<target
        else.
            if. node>:0 do. problem =. 'File exists' end.
            terminal 'ln: failed to create symbolic link ''',path,''': ',problem
        end.
    case. 'readlink';'realpath' do.
        path =. 0{::args
        'node parent name problem' =. resolve path;(command-:'realpath');0
        if. node=_1 do. terminal command,': ',path,': ',problem
        elseif. command-:'realpath' do. emit absolute node
        elseif. 2=node_kind node do. emit node_data node
        else. terminal 'readlink: ',path,': Invalid argument' end.
    case. 'find' do. find_nodes args
    case. 'du' do. disk_usage flags;<paths
    case. 'tree' do. draw_tree flags;<paths
    case. 'cat';'wc';'head';'tail';'grep';'sort';'uniq' do. x text_command command;<args
    case. do. terminal command,': command not found'
    end.
)
process =: 3 : 0
    Clock =: Clock+1
    terminal (absolute Current),'$ ',y
    pipeline =. y
    redirect =. _1
    positions =. I.' >> ' E.y
    separator =. 4
    append =. 1
    if. 0=#positions do.
        positions =. I.' > ' E.y
        separator =. 3
        append =. 0
    end.
    if. #positions do.
        position =. {.positions
        pipeline =. position{.y
        path =. (position+separator)}.y
        'node parent name problem' =. resolve path;1;0
        if. parent>:0 do. node =. create_node parent;name;1;<0$a:
        elseif. node=_1 do. terminal 'sh: ',path,': ',problem return.
        elseif. 0=node_kind node do. terminal 'sh: ',path,': Is a directory' return.
        end.
        redirect =. node
        if. -.append do. write_file node;(0$a:);0 end.
    end.
    positions =. I.' | ' E.pipeline
    commands =. 0$a:
    start =. 0
    for_position. positions,#pipeline do.
        commands =. commands,<(position-start){.start}.pipeline
        start =. position+3
    end.
    input =. 0$a:
    for_i. i.#commands do.
        Streaming =: (i=_1+#commands)*.redirect=_1
        Output =: 0$a:
        input run_command i{::commands
        input =. Output
    end.
    if. (redirect>:0)*.0<#input do. write_file redirect;input;1 end.
    reclaim''
)
main =: 3 : 0
    while. 1 do.
        line =. 1!:1[3
        if. line-:'exit' do. break. end.
        process line
    end.
)
main''
2!:55[0
