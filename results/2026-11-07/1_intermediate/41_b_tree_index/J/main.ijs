LF =: 10{a.
Have =: Root =: Cursor =: CursorKey =: TraceMode =: DoTrace =: 0
Degree =: 2
Nodes =: Saved =: 0$a:
Counters =: 3#0
Error =: ''
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
numbers =: 3 : ''' '' join number&.><"0 y'
emit =: 3 : 'Output =: Output,<y'
step =: 3 : 'if. DoTrace do. emit ''STEP '',y end.'
fail =: 3 : 0
    Error =: y
    throw.
)
empty_node =: 3 : '(i.0);(0$a:);<i.0'
nodekeys =: 3 : '0{::y{::Nodes'
nodevalues =: 3 : '1{::y{::Nodes'
nodekids =: 3 : '2{::y{::Nodes'
notation =: 3 : '''['',(numbers nodekeys y),'']'''
entry_text =: 3 : '(number 0{::y),''='',1{::y'
entry_at =: 4 : '(y{nodekeys x);y{::nodevalues x'
setnode =: 4 : 'Nodes =: (<y) x}Nodes'
remove =: 4 : '((i.#y)-.x){y'
pages =: 3 : 'I.0<#&>Nodes'
allocate =: 3 : 0
    page =. (#&>Nodes)i.0
    if. page=#Nodes do. Nodes =: Nodes,<y
    else. page setnode y end.
    page
)
snapshot =: 3 : 'Degree;Root;Nodes;<Counters'
restore =: 3 : '''Degree Root Nodes Counters'' =: y'
create =: 3 : 0
    Degree =: y
    Root =: 0
    Nodes =: <empty_node ''
    Counters =: 3#0
)
inorder =: 3 : 0
    'keys values kids' =. y{::Nodes
    entries =. 0$a:
    for_j. i.1+#keys do.
        if. #kids do. entries =. entries,inorder j{kids end.
        if. j<#keys do. entries =. entries,<(j{keys);j{::values end.
    end.
    entries
)
search =: 3 : 0
    page =. Root
    path =. 0$a:
    while. 1 do.
        keys =. nodekeys page
        path =. path,<notation page
        position =. (y<:keys)i.1
        if. position<#keys do.
            if. y=position{keys do. page;position;1;<path return. end.
        end.
        kids =. nodekids page
        if. 0=#kids do. page;position;0;<path return. end.
        page =. position{kids
    end.
)
height =: 3 : 0
    page =. Root
    depth =. 0
    while. #nodekids page do.
        page =. {.nodekids page
        depth =. depth+1
    end.
    depth
)

check_node =: 3 : 0
    'page location depth low high' =. y
    'keys values kids' =. page{::Nodes
    minimum =. Degree-1
    if. page=Root do. minimum =. 0<#kids end.
    maximum =. 2*Degree
    maximum =. maximum-1
    details =. 'at=',location,' node=',notation page
    if. ((#keys)<minimum)+.(#keys)>maximum do.
        'COUNT ',details,' keys=',(number #keys),' allowed=',(number minimum),'..',number maximum return.
    end.
    for_j. i.0>.(_1+#keys) do.
        if. (j{keys)>:(j+1){keys do.
            'ORDER ',details,' ',(number j{keys),'>=',number (j+1){keys return.
        end.
    end.
    for_key. keys do.
        if. (key<:low)+.key>:high do.
            lower =. '-inf'
            upper =. '+inf'
            if. low~:__ do. lower =. number low end.
            if. high~:_ do. upper =. number high end.
            'RANGE ',details,' key=',(number key),' low=',lower,' high=',upper return.
        end.
    end.
    if. 0=#kids do.
        if. ReferenceDepth=_1 do. ReferenceDepth =: depth
        elseif. depth~:ReferenceDepth do.
            'DEPTH ',details,' depth=',(number depth),' expected=',number ReferenceDepth return.
        end.
    end.
    for_j. i.#kids do.
        lower =. low
        upper =. high
        if. j do. lower =. (j-1){keys end.
        if. j<#keys do. upper =. j{keys end.
        problem =. check_node (j{kids);(location,'.',number j);(depth+1);lower;upper
        if. #problem do. problem return. end.
    end.
    ''
)
violation =: 3 : 0
    ReferenceDepth =: _1
    check_node Root;'root';0;__;_
)
status =: 3 : '(0<#violation ''''){::''OK'';''DAMAGED'''
summary =: 3 : 0
    'nodes=',(number #pages ''),' keys=',(number #inorder Root),' ',status ''
)
peek =: 3 : 0
    if. ParseAt=#ParseWords do. '' else. ParseAt{::ParseWords end.
)
parse_entry =: 3 : 0
    token =. peek ''
    at =. token i.'='
    if. at=#token do. fail 'SYNTAX ',number ParseAt+1 end.
    ParseAt =: ParseAt+1
    (0".at{.token);(at+1)}.token
)
parse_node =: 3 : 0
    if. -.'('-:peek '' do. fail 'SYNTAX ',number ParseAt+1 end.
    ParseAt =: ParseAt+1
    page =. allocate empty_node ''
    keys =. kids =. i.0
    values =. 0$a:
    internal =. '('-:peek ''
    if. internal do. kids =. ,parse_node '' end.
    while. -.')'-:peek '' do.
        'key value' =. parse_entry ''
        keys =. keys,key
        values =. values,<value
        if. internal do. kids =. kids,parse_node '' end.
    end.
    ParseAt =: ParseAt+1
    page setnode keys;values;<kids
    page
)
load_tree =: 3 : 0
    old =. Nodes
    Nodes =: 0$a:
    ParseWords =: y
    ParseAt =: 0
    try.
        root =. parse_node ''
        if. ParseAt~:#y do. fail 'SYNTAX ',number ParseAt+1 end.
    catcht.
        Nodes =: old
        throw.
    end.
    Root =: root
    Counters =: 3#0
)
changes =: 3 : 0
    before =. I.0<#&>y
    after =. pages ''
    writes =. #after-.before
    for_page. after#~after e.before do.
        writes =. writes+-. (page{y)-:page{Nodes
    end.
    writes,#before-.after
)

split =: 3 : 0
    'parent position' =. y
    'keys values kids' =. parent{::Nodes
    child =. position{kids
    'oldkeys oldvalues oldkids' =. child{::Nodes
    oldtext =. notation child
    middle =. (Degree-1){oldkeys
    middlevalue =. (Degree-1){oldvalues
    rightkids =. i.0
    if. #oldkids do.
        rightkids =. Degree}.oldkids
        oldkids =. Degree{.oldkids
    end.
    right =. allocate (Degree}.oldkeys);(Degree}.oldvalues);<rightkids
    child setnode ((Degree-1){.oldkeys);((Degree-1){.oldvalues);<oldkids
    keys =. (position{.keys),middle,position}.keys
    values =. (position{.values),middlevalue,position}.values
    kids =. ((position+1){.kids),right,(position+1)}.kids
    parent setnode keys;values;<kids
    Counters =: Counters+1 0 0
    step 'split page=',(number child),' keys=',oldtext,' up=',(number middle),' new=',number right
)
upsert =: 3 : 0
    'key value' =. y
    'page position found path' =. search key
    if. found do.
        'keys values kids' =. page{::Nodes
        old =. position{::values
        values =. (<value) position}values
        page setnode keys;values;<kids
        1;old return.
    end.
    if. (2*Degree)=1+#nodekeys Root do.
        Root =: allocate (i.0);(0$a:);<,Root
        step 'grow page=',number Root
        split Root,0
    end.
    page =. Root
    while. #nodekids page do.
        position =. (key<:nodekeys page)i.1
        child =. position{nodekids page
        if. (2*Degree)=1+#nodekeys child do.
            split page,position
            if. key>position{nodekeys page do. position =. position+1 end.
        end.
        page =. position{nodekids page
    end.
    'keys values kids' =. page{::Nodes
    position =. (key<:keys)i.1
    keys =. (position{.keys),key,position}.keys
    values =. (position{.values),(<value),position}.values
    page setnode keys;values;<kids
    step 'place page=',(number page),' keys=',notation page
    0;''
)
extreme =: 4 : 0
    page =. y
    while. #nodekids page do.
        if. x do. page =. {:nodekids page else. page =. {.nodekids page end.
    end.
    position =. 0
    if. x do. position =. _1+#nodekeys page end.
    page entry_at position
)
merge =: 3 : 0
    'parent position label' =. y
    'keys values kids' =. parent{::Nodes
    'left right' =. (position+i.2){kids
    'leftkeys leftvalues leftkids' =. left{::Nodes
    'rightkeys rightvalues rightkids' =. right{::Nodes
    left setnode (leftkeys,(position{keys),rightkeys);(leftvalues,(position{values),rightvalues);<leftkids,rightkids
    parent setnode (position remove keys);(position remove values);<(position+1) remove kids
    Nodes =: a: right}Nodes
    Counters =: Counters+0 1 0
    step label,' page=',(number parent),' merge=',(number left),'+',(number right),' keys=',notation left
    if. parent=Root do.
        if. 0=#nodekeys parent do.
            Root =: left
            Nodes =: a: parent}Nodes
            step 'shrink page=',number left
        end.
    end.
    left
)
delete_at =: 3 : 0
    'page key' =. y
    'keys values kids' =. page{::Nodes
    position =. (key<:keys)i.1
    found =. 0
    if. position<#keys do. found =. key=position{keys end.
    if. found do.
        if. 0=#kids do.
            Cases =: Cases,<'1'
            page setnode (position remove keys);(position remove values);<kids
            step '1 page=',(number page),' keys=',notation page
            return.
        end.
        'left right' =. (position+i.2){kids
        if. Degree<:#nodekeys left do.
            Cases =: Cases,<'2a'
            'next value' =. 1 extreme left
            step '2a page=',(number page),' pred=',number next
            delete_at left,next
            keys =. next position}keys
            values =. (<value) position}values
            page setnode keys;values;<kids
        elseif. Degree<:#nodekeys right do.
            Cases =: Cases,<'2b'
            'next value' =. 0 extreme right
            step '2b page=',(number page),' succ=',number next
            delete_at right,next
            keys =. next position}keys
            values =. (<value) position}values
            page setnode keys;values;<kids
        else.
            Cases =: Cases,<'2c'
            child =. merge page;position;'2c'
            delete_at child,key
        end.
        return.
    end.
    child =. position{kids
    'childkeys childvalues childkids' =. child{::Nodes
    if. (#childkeys)=Degree-1 do.
        left =. right =. _1
        canleft =. canright =. 0
        if. position do.
            left =. (position-1){kids
            canleft =. Degree<:#nodekeys left
        end.
        if. position<#keys do.
            right =. (position+1){kids
            canright =. Degree<:#nodekeys right
        end.
        if. canleft do.
            Cases =: Cases,<'3a-left'
            'skeys svalues skids' =. left{::Nodes
            childkeys =. ((position-1){keys),childkeys
            childvalues =. ((position-1){values),childvalues
            keys =. ({:skeys) (position-1)}keys
            values =. ({:svalues) (position-1)}values
            if. #skids do.
                childkids =. ({:skids),childkids
                skids =. }:skids
            end.
            left setnode (}:skeys);(}:svalues);<skids
            child setnode childkeys;childvalues;<childkids
            page setnode keys;values;<kids
            Counters =: Counters+0 0 1
            step '3a-left page=',(number page),' child=',(number child),' from=',(number left),' keys=',notation child
        elseif. canright do.
            Cases =: Cases,<'3a-right'
            'skeys svalues skids' =. right{::Nodes
            childkeys =. childkeys,position{keys
            childvalues =. childvalues,position{values
            keys =. ({.skeys) position}keys
            values =. ({.svalues) position}values
            if. #skids do.
                childkids =. childkids,{.skids
                skids =. }.skids
            end.
            right setnode (}.skeys);(}.svalues);<skids
            child setnode childkeys;childvalues;<childkids
            page setnode keys;values;<kids
            Counters =: Counters+0 0 1
            step '3a-right page=',(number page),' child=',(number child),' from=',(number right),' keys=',notation child
        elseif. left>:0 do.
            Cases =: Cases,<'3b-left'
            child =. merge page;(position-1);'3b-left'
        else.
            Cases =: Cases,<'3b-right'
            child =. merge page;position;'3b-right'
        end.
    end.
    delete_at child,key
)
scan =: 3 : 0
    Visits =: Visits+1
    'keys values kids' =. y{::Nodes
    found =. 0$a:
    for_j. i.1+#keys do.
        if. #kids do.
            allowed =. 1
            if. j do. allowed =. ((j-1){keys)<High end.
            if. j<#keys do. allowed =. allowed*.(j{keys)>Low end.
            if. allowed do. found =. found,scan j{kids end.
        end.
        if. j<#keys do.
            key =. j{keys
            if. (Low<:key)*.key<:High do. found =. found,<key;j{::values end.
        end.
    end.
    found
)
dump_node =: 3 : 0
    'keys values kids' =. y{::Nodes
    tokens =. <'('
    for_j. i.1+#keys do.
        if. #kids do. tokens =. tokens,dump_node j{kids end.
        if. j<#keys do. tokens =. tokens,<entry_text (j{keys);j{::values end.
    end.
    tokens,<')'
)
renumber =: 3 : 0
    'keys values oldkids' =. y{::Built
    page =. allocate empty_node ''
    kids =. i.0
    for_child. oldkids do. kids =. kids,renumber child end.
    page setnode keys;values;<kids
    page
)
compact =: 3 : 0
    entries =. inorder Root
    children =. i.0
    Built =: 0$a:
    while. 1 do.
        groups =. <.((#entries)+2*Degree)%(2*Degree)
        total =. (#entries)-(groups-1)
        base =. <.total%groups
        extra =. groups|total
        at =. childat =. 0
        separators =. 0$a:
        level =. i.0
        for_j. i.groups do.
            count =. base+j<extra
            selected =. (at+i.count){entries
            keys =. i.0
            values =. 0$a:
            if. count do.
                keys =. 0&{::&>selected
                values =. 1&{::&.>selected
            end.
            kids =. i.0
            if. #children do.
                kids =. (childat+i.count+1){children
                childat =. childat+count+1
            end.
            level =. level,#Built
            Built =: Built,<keys;values;<kids
            at =. at+count
            if. j<groups-1 do.
                separators =. separators,at{entries
                at =. at+1
            end.
        end.
        if. groups=1 do. oldroot =. {.level break. end.
        entries =. separators
        children =. level
    end.
    Nodes =: 0$a:
    Root =: renumber oldroot
    Counters =: 3#0
)

execute =: 3 : 0
    Output =: 0$a:
    words =. <;._1 ' ',y
    command =. 0{::words
    if. command-:'TRACE' do.
        TraceMode =: 'ON'-:1{::words
        emit 'TRACE ',1{::words
        Output return.
    end.
    first =. second =. 0
    if. 1<#words do. first =. 0".1{::words end.
    ranged =. (<command)e.;:'DELRANGE RANGE COUNT'
    if. ranged do. second =. 0".2{::words end.
    if. (<command)e.;:'CREATE LOAD' do.
        if. -.first e.2 3 4 5 do. fail 'BAD DEGREE ',number first end.
        if. command-:'CREATE' do.
            create first
            emit 'CREATE t=',number Degree
        else.
            load_tree 2}.words
            Degree =: first
            emit 'LOAD t=',(number Degree),' ',summary ''
        end.
        Have =: 1
        Cursor =: 0
        Output return.
    end.
    if. -.Have do. fail 'NO INDEX' end.
    if. (<command)e.;:'INSERT BULKLOAD DELETE DELRANGE RANGE COUNT MIN MAX FLOOR CEIL RANK SELECT SEEK NEXT PREV HEIGHT COMPACT' do.
        if. #violation '' do. fail 'DAMAGED' end.
    end.
    entries =. inorder Root
    keys =. i.0
    if. #entries do. keys =. 0&{::&>entries end.
    if. ranged do. if. first>second do. fail 'BAD RANGE ',numbers first,second end. end.
    if. command-:'SELECT' do.
        if. (first<1)+.first>#entries do. fail 'BAD POSITION ',number first end.
    end.
    if. (<command)e.;:'NEXT PREV' do. if. Cursor=0 do. fail 'NO CURSOR' end. end.
    if. command-:'RESTORE' do. if. 0=#Saved do. fail 'NO SAVE' end. end.
    DoTrace =: TraceMode*.(<command)e.;:'INSERT DELETE'
    select. command
    case. 'INSERT' do.
        before =. Nodes
        counters =. Counters
        'updated old' =. upsert first;2{::words
        writes =. {.changes before
        if. updated do.
            emit 'INSERT ',(number first),' UPDATED old=',old,' writes=',number writes
        else.
            emit 'INSERT ',(number first),' NEW splits=',(number 0{Counters-counters),' height=',(number height ''),' writes=',number writes
        end.
    case. 'BULKLOAD' do.
        before =. Nodes
        counters =. Counters
        updated =. 0
        count =. <.(#words)%2
        for_i. 1+2*i.count do.
            result =. upsert (0".i{::words);(i+1){::words
            updated =. updated+0{::result
        end.
        emit 'BULKLOAD pairs=',(number count),' new=',(number count-updated),' updated=',(number updated),' splits=',(number 0{Counters-counters),' height=',(number height ''),' writes=',number {.changes before
    case. 'DELETE' do.
        'page position found path' =. search first
        if. -.found do. emit 'DELETE ',(number first),' NOT FOUND'
        else.
            old =. position{::nodevalues page
            before =. Nodes
            Cases =: 0$a:
            delete_at Root,first
            'writes frees' =. changes before
            emit 'DELETE ',(number first),' REMOVED value=',old,' cases=',(',' join Cases),' height=',(number height ''),' writes=',(number writes),' frees=',number frees
        end.
    case. 'DELRANGE' do.
        selected =. keys#~(first<:keys)*.keys<:second
        before =. Nodes
        counters =. Counters
        for_key. selected do.
            Cases =: 0$a:
            delete_at Root,key
        end.
        'writes frees' =. changes before
        delta =. Counters-counters
        emit 'DELRANGE ',(numbers first,second),' removed=',(number #selected),' merges=',(number 1{delta),' borrows=',(number 2{delta),' height=',(number height ''),' writes=',(number writes),' frees=',number frees
    case. 'GET' do.
        'page position found path' =. search first
        result =. 'NOT FOUND'
        if. found do. result =. 'FOUND value=',position{::nodevalues page end.
        emit 'GET ',(number first),' ',result,' path=',' -> ' join path
    case. 'RANGE';'COUNT' do.
        Low =: first
        High =: second
        Visits =: 0
        found =. scan Root
        text =. command,' ',(numbers first,second),' count=',(number #found),' visited=',number Visits
        if. command-:'RANGE' do.
            for_entry. found do. text =. text,' ',entry_text >entry end.
        end.
        emit text
    case. 'MIN';'MAX' do.
        text =. 'EMPTY'
        if. #entries do.
            at =. 0
            if. command-:'MAX' do. at =. _1 end.
            text =. entry_text at{::entries
        end.
        emit command,' ',text
    case. 'FLOOR';'CEIL';'SEEK' do.
        if. command-:'FLOOR' do. selected =. I.keys<:first
        else. selected =. I.keys>:first end.
        text =. 'NONE'
        if. command-:'SEEK' do. Cursor =: 3 [ text =. 'END' end.
        if. #selected do.
            at =. {.selected
            if. command-:'FLOOR' do. at =. {:selected end.
            text =. entry_text at{::entries
            if. command-:'SEEK' do. Cursor =: 1 [ CursorKey =: at{keys end.
        end.
        emit command,' ',(number first),' ',text
    case. 'RANK' do. emit 'RANK ',(number first),' ',number +/keys<first
    case. 'SELECT' do. emit 'SELECT ',(number first),' ',entry_text (first-1){::entries
    case. 'NEXT';'PREV' do.
        selected =. i.0
        if. command-:'NEXT' do.
            if. Cursor=2 do. selected =. i.#entries
            elseif. Cursor=1 do. selected =. I.keys>CursorKey end.
            Cursor =: 3
            text =. 'END'
            if. #selected do. selected =. ,{.selected end.
        else.
            if. Cursor=3 do. selected =. i.#entries
            elseif. Cursor=1 do. selected =. I.keys<CursorKey end.
            Cursor =: 2
            text =. 'BEGIN'
            if. #selected do. selected =. ,{:selected end.
        end.
        if. #selected do.
            at =. {.selected
            Cursor =: 1
            CursorKey =: at{keys
            text =. entry_text at{::entries
        end.
        emit command,' ',text
    case. 'PRINT' do.
        level =. ,Root
        depth =. 0
        while. #level do.
            next =. i.0
            text =. 'LEVEL ',number depth
            for_page. level do.
                text =. text,' ',notation page
                next =. next,nodekids page
            end.
            emit text
            level =. next
            depth =. depth+1
        end.
    case. 'PAGES' do.
        for_page. pages '' do.
            kids =. nodekids page
            text =. '-'
            if. #kids do. text =. ',' join number&.><"0 kids end.
            emit 'PAGE ',(number page),' ',(notation page),' kids=',text
        end.
    case. 'DUMP' do. emit 'DUMP ',(number Degree),' ',' ' join dump_node Root
    case. 'HEIGHT' do. emit 'HEIGHT ',number height ''
    case. 'STATS' do.
        live =. pages ''
        leaves =. +/0=#@nodekids"0 live
        fill =. <.(100*#entries)%((2*Degree)-1)*#live
        emit 'STATS t=',(number Degree),' nodes=',(number #live),' leaves=',(number leaves),' keys=',(number #entries),' fill=',(number fill),'% splits=',(number 0{Counters),' merges=',(number 1{Counters),' borrows=',number 2{Counters
    case. 'VERIFY' do.
        problem =. violation ''
        if. #problem do. emit 'VERIFY FAIL ',problem else. emit 'VERIFY OK' end.
    case. 'REBUILD' do.
        create Degree
        for_entry. entries do. upsert >entry end.
        emit 'REBUILD entries=',(number #entries),' keys=',(number #inorder Root),' nodes=',(number #pages ''),' splits=',(number 0{Counters),' height=',number height ''
    case. 'COMPACT' do.
        count =. #pages ''
        compact ''
        emit 'COMPACT nodes=',(number count),'->',(number #pages ''),' height=',number height ''
    case. 'SAVE' do.
        Saved =: snapshot ''
        emit 'SAVE ',summary ''
    case. 'RESTORE' do.
        restore Saved
        emit 'RESTORE ',summary ''
    end.
    Output
)

main =: 3 : 0
    count =. 0".1!:1[3
    for_command. i.count do.
        line =. 1!:1[3
        try. rows =. execute line
        catcht. rows =. <'ERROR ',Error end.
        for_row. rows do. ((>row),LF) 1!:2[4 end.
    end.
)
main ''
2!:55[0
