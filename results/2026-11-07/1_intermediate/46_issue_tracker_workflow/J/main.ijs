LF =: 10{a.
Day =: 1
Users =: Titles =: Histories =: SprintNames =: 0$a:
IssueIds =: Types =: Priorities =: States =: Assignees =: Reviewers =: i.0
Estimates =: IssueSprints =: Comments =: Duplicates =: i.0
Blocks =: 0 0$0
Phases =: Starts =: Ends =: Velocities =: i.0
Daily =: 0 366$0
TypeNames =: ;:'BUG TASK STORY'
PriorityNames =: ;:'LOW MEDIUM HIGH CRITICAL'
StateNames =: ;:'OPEN TRIAGED IN_PROGRESS REVIEW RESOLVED CLOSED REOPENED DONE BACKLOG READY'
PhaseNames =: ;:'PLANNED ACTIVE ENDED'
Workflows =: (<0 1 2 3 4 5 6),(<0 2 7),<8 9 2 3 7
Transitions =: (<9 2$0 1 1 2 2 3 3 2 3 4 4 5 4 6 5 6 6 2),(<3 2$0 2 2 0 2 7),<6 2$8 9 9 8 9 2 2 3 3 2 3 7
FieldNames =: ;:'id type status priority assignee reviewer estimate sprint comments blocked done title'
ComparisonOps =: ,&.> '=';'!=';'<' ;'<=';'>';'>='
OperatorNames =: ,&.> '>=';'<=';'!=';'=';'<' ;'>';'~'
Lower =: 'abcdefghijklmnopqrstuvwxyz'
Upper =: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
Error =: ''

split =: 4 : '<;._1 x,y'
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : 0
    fields =. 0$a:
    for_item. y do.
        item =. >item
        if. 2~:3!:0 item do. item =. number item end.
        fields =. fields,<item
    end.
    ' ' join fields
)
emit =: 3 : 'Output =: Output,<y'
say =: 3 : 'emit words y'
fail =: 3 : 0
    Error =: y
    throw.
)
prefix =: 4 : '(,x)-:(#x){.y'
text_equal =: 4 : '(,x)-:,y'
lowercase =: 3 : 'a.{~(a.i.y)+32*y e.Upper'
yes_no =: 3 : 'y{::''no'';''yes'''
issue_order =: 3 : '(/:y{IssueIds){y'
user_order =: 3 : '(/:s:Users){i.#Users'
issue =: 3 : 0
    index =. IssueIds i.0".y
    if. index=#IssueIds do. fail 'unknown issue' end.
    index
)
user =: 3 : 0
    if. y text_equal '-' do. _1 return. end.
    index =. Users i.<y
    if. index=#Users do. fail 'unknown user' end.
    index
)
sprint =: 3 : 0
    index =. SprintNames i.<y
    if. index=#SprintNames do. fail 'unknown sprint' end.
    index
)
display_index =: 4 : 0
    if. y<0 do. '-' else. y{::x end.
)
display_num =: 3 : 0
    if. y<0 do. '-' else. number y end.
)
issue_reference =: 3 : 0
    if. y<0 do. '-' else. number y{IssueIds end.
)
number_list =: 3 : 0
    if. 0=#y do. '-' else. ',' join number&.><"0 (issue_order y){IssueIds end.
)
is_done =: 3 : '(y{States)e.4 5 7'
not_done =: 3 : 0
    if. is_done y do. fail 'issue done' end.
)
points =: 3 : '0>.y{Estimates'
unfinished_blockers =: 3 : 0
    selected =. I.y{"1 Blocks
    issue_order selected#~-.is_done selected
)
is_blocked =: 3 : '(-.is_done y)*.0<#unfinished_blockers y'
blocked_flags =: 3 : 0
    flags =. i.0
    for_index. y do. flags =. flags,is_blocked index end.
    flags
)
notify =: 4 : 0
    for_index. issue_order x do.
        before =. (x i.index){y
        after =. is_blocked index
        if. after~:before do.
            if. after do. kind =. 'BLOCKED' else. kind =. 'UNBLOCKED' end.
            say kind;index{IssueIds
        end.
    end.
)
wip_count =: 3 : '+/(Assignees=y)*.States=2'
active_sprint =: 3 : 0
    active =. I.Phases=1
    if. #active do. {.active else. _1 end.
)
members =: 3 : 'issue_order I.IssueSprints=y'
remaining =: 3 : 0
    selected =. members y
    +/points selected#~-.is_done selected
)
sprint_summary =: 3 : 0
    selected =. members y
    'issues ',(number #selected),' points ',number +/points selected
)
record_sprint =: 3 : 'Daily =: (remaining y) (<y,Day)}Daily'
record =: 4 : 0
    history =. x{::Histories
    history =. history,<'day ',(number Day),' ',y
    Histories =: (<history) x}Histories
)
change_state =: 4 : 0
    affected =. I.x{Blocks
    before =. blocked_flags affected
    old =. (x{States){::StateNames
    target =. y{::StateNames
    say 'MOVE';(x{IssueIds);old;target
    x record 'MOVE ',old,' ',target
    States =: y x}States
    affected notify before
)
reaches =: 4 : 0
    pending =. ,x
    visited =. (#IssueIds)#0
    while. #pending do.
        node =. {.pending
        pending =. }.pending
        if. node=y do. 1 return. end.
        if. node{visited do. continue. end.
        visited =. 1 node}visited
        pending =. pending,I.node{Blocks
    end.
    0
)

query_tokens =: 3 : 0
    result =. 0$a:
    current =. ''
    for_c. y do.
        if. c e.' ()' do.
            if. #current do.
                result =. result,<current
                current =. ''
            end.
            if. c~:' ' do. result =. result,<,c end.
        else.
            current =. current,c
        end.
    end.
    if. #current do. result =. result,<current end.
    result
)
is_number =: 3 : '(0<#y)*.(6>:#y)*.*./y e.''0123456789'''
condition =: 3 : 0
    token =. y
    length =. 0
    while. length<#token do.
        if. -.(length{token)e.Lower do. break. end.
        length =. length+1
    end.
    field =. length{.token
    rest =. length}.token
    operator =. ''
    for_op. OperatorNames do.
        if. (>op)prefix rest do. operator =. >op break. end.
    end.
    value =. (#operator)}.rest
    if. (0=#field)+.(0=#operator)+.0=#value do. fail 'syntax near ',token end.
    f =. FieldNames i.<field
    if. f=#FieldNames do. fail 'unknown field ',field end.
    opindex =. (ComparisonOps,<,'~')i.<operator
    allowed =. 0 1
    if. f e.0 3 6 8 do. allowed =. i.6 end.
    if. f=11 do. allowed =. ,6 end.
    if. -.opindex e.allowed do. fail 'bad operator ',token end.
    valid =. 0
    expected =. _1
    if. (value text_equal '-')*.(f e.4 5 6 7)*.opindex e.0 1 do.
        valid =. 1
    elseif. f e.0 6 8 do.
        if. is_number value do. valid =. 1 [ expected =. 0".value end.
    elseif. f=1 do.
        expected =. TypeNames i.<value
        valid =. expected<#TypeNames
    elseif. f=2 do.
        expected =. StateNames i.<value
        valid =. expected<#StateNames
    elseif. f=3 do.
        expected =. PriorityNames i.<value
        valid =. expected<#PriorityNames
    elseif. f e.4 5 do.
        expected =. Users i.<value
        valid =. expected<#Users
    elseif. f=7 do.
        expected =. SprintNames i.<value
        valid =. expected<#SprintNames
    elseif. f e.9 10 do.
        expected =. ('no';'yes')i.<value
        valid =. expected<2
    elseif. f=11 do.
        valid =. 1
        expected =. lowercase value
    end.
    if. -.valid do. fail 'bad value ',token end.
    (<f),(<opindex),<expected
)
validate_query =: 3 : 0
    QueryTokens =: query_tokens y
    QueryConditions =: (#QueryTokens)$<i.0
    expecting =. 1
    depth =. 0
    for_i. i.#QueryTokens do.
        token =. i{::QueryTokens
        if. expecting do.
            if. token-:'NOT' do. expecting =. 1
            elseif. token text_equal '(' do. depth =. depth+1
            elseif. ((<token)e.;:'AND OR')+.token text_equal ')' do. fail 'syntax near ',token
            else.
                QueryConditions =: (<condition token) i}QueryConditions
                expecting =. 0
            end.
        elseif. (<token)e.'AND';'OR' do.
            expecting =. 1
        elseif. (token text_equal ')')*.depth>0 do.
            depth =. depth-1
        else.
            fail 'syntax near ',token
        end.
    end.
    if. expecting+.depth~:0 do. fail 'syntax at end' end.
)
condition_truth =: 3 : 0
    'field operator expected' =. y
    select. field
    case. 0 do. actual =. IssueIds
    case. 1 do. actual =. Types
    case. 2 do. actual =. States
    case. 3 do. actual =. Priorities
    case. 4 do. actual =. Assignees
    case. 5 do. actual =. Reviewers
    case. 6 do. actual =. Estimates
    case. 7 do. actual =. IssueSprints
    case. 8 do. actual =. Comments
    case. 9 do. actual =. blocked_flags i.#IssueIds
    case. 10 do. actual =. is_done i.#IssueIds
    case. 11 do.
        result =. i.0
        for_title. Titles do. result =. result,+./expected E.lowercase >title end.
        result return.
    end.
    select. operator
    case. 0 do. actual=expected
    case. 1 do. actual~:expected
    case. 2 do. (actual>:0)*.actual<expected
    case. 3 do. (actual>:0)*.actual<:expected
    case. 4 do. (actual>:0)*.actual>expected
    case. 5 do. (actual>:0)*.actual>:expected
    end.
)
query_peek =: 3 : 0
    if. QueryPosition<#QueryTokens do. QueryPosition{::QueryTokens else. '' end.
)
query_factor =: 3 : 0
    token =. query_peek ''
    QueryPosition =: QueryPosition+1
    if. token-:'NOT' do. -.query_factor '' return. end.
    if. token text_equal '(' do.
        result =. query_expression ''
        QueryPosition =: QueryPosition+1
        result return.
    end.
    condition_truth (QueryPosition-1){::QueryConditions
)
query_term =: 3 : 0
    result =. query_factor ''
    while. 'AND'-:query_peek '' do.
        QueryPosition =: QueryPosition+1
        right =. query_factor ''
        result =. result*.right
    end.
    result
)
query_expression =: 3 : 0
    result =. query_term ''
    while. 'OR'-:query_peek '' do.
        QueryPosition =: QueryPosition+1
        right =. query_term ''
        result =. result+.right
    end.
    result
)

edit_command =: 4 : 0
    index =. issue 0{::y
    id =. index{IssueIds
    select. x
    case. 'PRIORITY' do.
        priority =. PriorityNames i.1{y
        if. priority=#PriorityNames do. fail 'bad priority' end.
        not_done index
        old =. index{Priorities
        if. priority=old do. fail 'no change' end.
        Priorities =: priority index}Priorities
        content =. 'PRIORITY ',(old{::PriorityNames),' ',priority{::PriorityNames
        index record content
        say 'PRIORITY';id;(old{::PriorityNames);priority{::PriorityNames
    case. 'ASSIGN';'REVIEWER' do.
        spec =. 1{::y
        target =. user spec
        not_done index
        state =. index{States
        if. x-:'ASSIGN' do.
            if. target=index{Assignees do. fail 'no change' end.
            if. (target<0)*.state e.2 3 do. fail 'assignee required' end.
            if. (state=2)*.(wip_count target)>:3 do. fail 'wip limit ',spec end.
            if. (state=3)*.target=index{Reviewers do. fail 'reviewer is assignee' end.
            Assignees =: target index}Assignees
        else.
            if. target=index{Reviewers do. fail 'no change' end.
            if. (target<0)*.state=3 do. fail 'reviewer required' end.
            if. (state=3)*.target=index{Assignees do. fail 'reviewer is assignee' end.
            Reviewers =: target index}Reviewers
        end.
        index record x,' ',spec
        say x;id;spec
    case. 'ESTIMATE' do.
        value =. 0".1{::y
        if. -.value e.0 1 2 3 5 8 13 21 do. fail 'bad estimate' end.
        not_done index
        old =. index{Estimates
        if. value=old do. fail 'no change' end.
        Estimates =: value index}Estimates
        index record 'ESTIMATE ',(display_num old),' ',number value
        say 'ESTIMATE';id;(display_num old);value
    case. 'COMMENT' do.
        writer =. user 1{::y
        text =. ' ' join 2}.y
        count =. 1+index{Comments
        Comments =: count index}Comments
        index record 'COMMENT ',(writer{::Users),' ',text
        say 'COMMENT';id;count
    end.
)
move_command =: 3 : 0
    index =. issue 0{::y
    duplicate =. index{Duplicates
    if. duplicate>:0 do. fail 'duplicate of ',number duplicate{IssueIds end.
    target =. StateNames i.1{y
    kind =. index{Types
    if. -.target e.kind{::Workflows do. fail 'bad state' end.
    old =. index{States
    if. -.(<old,target)e.<"1 kind{::Transitions do.
        fail 'cannot move ',(old{::StateNames),' to ',target{::StateNames
    end.
    if. target=2 do.
        active =. active_sprint ''
        if. (kind=2)*.((active<0)+.active~:index{IssueSprints) do. fail 'not in active sprint' end.
        assigned =. index{Assignees
        if. assigned<0 do. fail 'no assignee' end.
        if. (wip_count assigned)>:3 do. fail 'wip limit ',assigned{::Users end.
    end.
    if. target=3 do.
        reviewer =. index{Reviewers
        if. reviewer<0 do. fail 'no reviewer' end.
        if. reviewer=index{Assignees do. fail 'reviewer is assignee' end.
    end.
    if. target e.4 7 do.
        blockers =. unfinished_blockers index
        if. #blockers do. fail 'blocked by ',number ({.blockers){IssueIds end.
    end.
    if. (target=9)*.(index{Estimates)<0 do. fail 'no estimate' end.
    index change_state target
)
link_command =: 4 : 0
    relation =. 1{::y
    if. x-:'UNLINK' do.
        if. -.relation-:'BLOCKS' do. fail 'bad link' end.
    elseif. -.(<relation)e.'BLOCKS';'DUPLICATES' do.
        fail 'bad link'
    end.
    a =. issue 0{::y
    b =. issue 2{::y
    ida =. a{IssueIds
    idb =. b{IssueIds
    if. x-:'UNLINK' do.
        if. -. (<a,b){Blocks do. fail 'no link' end.
        before =. is_blocked b
        Blocks =: 0 (<a,b)}Blocks
        a record 'UNLINK BLOCKS ',number idb
        b record 'UNLINK BLOCKED_BY ',number ida
        say 'UNLINK';ida;'BLOCKS';idb
        (,b) notify ,before
        return.
    end.
    if. a=b do. fail 'self link' end.
    if. relation-:'BLOCKS' do.
        if. (<a,b){Blocks do. fail 'link exists' end.
        if. b reaches a do. fail 'cycle' end.
        not_done b
        before =. is_blocked b
        Blocks =: 1 (<a,b)}Blocks
        a record 'LINK BLOCKS ',number idb
        b record 'LINK BLOCKED_BY ',number ida
        say 'LINK';ida;'BLOCKS';idb
        (,b) notify ,before
    else.
        if. (a{Types)~:b{Types do. fail 'type mismatch' end.
        not_done a
        if. (b{Duplicates)>:0 do. fail 'target is duplicate' end.
        Duplicates =: b a}Duplicates
        a record 'LINK DUPLICATES ',number idb
        b record 'LINK DUPLICATED_BY ',number ida
        say 'LINK';ida;'DUPLICATES';idb
        if. (a{Types)=0 do. terminal =. 5 else. terminal =. 7 end.
        a change_state terminal
        previous =. a{IssueSprints
        if. previous>:0 do.
            if. (previous{Phases)~:2 do.
                IssueSprints =: _1 a}IssueSprints
                a record 'SPRINT REMOVE ',previous{::SprintNames
            end.
        end.
    end.
)
sprint_command =: 3 : 0
    action =. 0{::y
    name =. 1{::y
    if. action-:'NEW' do.
        if. (<name)e.SprintNames do. fail 'sprint exists' end.
        SprintNames =: SprintNames,<name
        Phases =: Phases,0
        Starts =: Starts,_1
        Ends =: Ends,_1
        Velocities =: Velocities,0
        Daily =: Daily,1 366$_1
        emit 'SPRINT NEW ',name
        return.
    end.
    s =. sprint name
    select. action
    case. 'ADD';'REMOVE' do.
        index =. issue 2{::y
        if. (s{Phases)=2 do. fail 'sprint ended' end.
        if. action-:'ADD' do.
            not_done index
            previous =. index{IssueSprints
            if. previous>:0 do.
                if. (previous{Phases)~:2 do. fail 'in sprint ',previous{::SprintNames end.
            end.
            if. (index{States)=8 do. fail 'not ready' end.
            IssueSprints =: s index}IssueSprints
        else.
            if. s~:index{IssueSprints do. fail 'not in sprint' end.
            not_done index
            IssueSprints =: _1 index}IssueSprints
        end.
        index record 'SPRINT ',action,' ',name
        say 'SPRINT';action;name;(index{IssueIds);sprint_summary s
    case. 'START' do.
        if. (s{Phases)~:0 do. fail 'sprint not planned' end.
        active =. active_sprint ''
        if. active>:0 do. fail 'sprint active ',active{::SprintNames end.
        if. 0=#members s do. fail 'sprint empty' end.
        Phases =: 1 s}Phases
        Starts =: Day s}Starts
        record_sprint s
        say 'SPRINT';'START';name;'day';Day;(sprint_summary s);'remaining';remaining s
    case. 'END' do.
        if. (s{Phases)~:1 do. fail 'sprint not active' end.
        record_sprint s
        selected =. members s
        finished =. selected#~is_done selected
        returned =. selected#~-.is_done selected
        velocity =. +/points finished
        Velocities =: velocity s}Velocities
        Phases =: 2 s}Phases
        Ends =: Day s}Ends
        say 'SPRINT';'END';name;'day';Day;'velocity';velocity;'done';(#finished);'returned';#returned
        for_index. returned do.
            IssueSprints =: _1 index}IssueSprints
            index record 'SPRINT RETURN ',name
            say 'RETURNED';index{IssueIds
        end.
    end.
)

display_command =: 4 : 0
    select. x
    case. 'QUERY' do.
        validate_query ' ' join y
        QueryPosition =: 0
        flags =. query_expression ''
        selected =. I.flags
        keys =. (-(selected{Priorities)),.selected{IssueIds
        selected =. (/:keys){selected
        say 'QUERY';#selected
        for_index. selected do.
            say (index{IssueIds);((index{Types){::TypeNames);((index{Priorities){::PriorityNames);((index{States){::StateNames);(Users display_index index{Assignees);(display_num index{Estimates);index{::Titles
        end.
    case. 'SHOW' do.
        index =. issue 0{::y
        say 'ISSUE';(index{IssueIds);((index{Types){::TypeNames);((index{Priorities){::PriorityNames);((index{States){::StateNames);'blocked';yes_no is_blocked index
        emit 'TITLE ',index{::Titles
        say 'PEOPLE';'assignee';(Users display_index index{Assignees);'reviewer';Users display_index index{Reviewers
        say 'PLAN';'estimate';(display_num index{Estimates);'sprint';(SprintNames display_index index{IssueSprints);'comments';index{Comments
        say 'LINKS';'blocks';(number_list I.index{Blocks);'blocked_by';(number_list I.index{"1 Blocks);'duplicate_of';(issue_reference index{Duplicates);'duplicated_by';number_list I.Duplicates=index
    case. 'HISTORY' do.
        index =. issue 0{::y
        history =. index{::Histories
        say 'HISTORY';(index{IssueIds);#history
        for_line. history do. emit >line end.
    case. 'BOARD' do.
        emit 'BOARD'
        for_kind. i.#TypeNames do.
            text =. kind{::TypeNames
            for_state. kind{::Workflows do.
                count =. +/(Types=kind)*.States=state
                text =. text,' ',(state{::StateNames),' ',number count
            end.
            emit text
        end.
        done =. +/is_done i.#IssueIds
        say 'TOTAL';(#IssueIds);'open';((#IssueIds)-done);'done';done
    case. 'WORKLOAD' do.
        say 'WORKLOAD';#Users
        for_person. user_order '' do.
            selected =. I.(Assignees=person)*.-.is_done i.#IssueIds
            progress =. +/2=selected{States
            review =. +/3=selected{States
            reviewing =. +/(Reviewers=person)*.States=3
            total =. +/points selected
            say (person{::Users);'assigned';(#selected);'in_progress';progress;'review';review;'reviewing';reviewing;'points';total
        end.
    case. 'SPRINTS' do.
        say 'SPRINTS';#SprintNames
        for_s. i.#SprintNames do.
            name =. s{::SprintNames
            select. s{Phases
            case. 0 do. say name;'PLANNED';sprint_summary s
            case. 1 do. say name;'ACTIVE';'start';(s{Starts);(sprint_summary s);'remaining';remaining s
            case. 2 do. say name;'ENDED';'start';(s{Starts);'end';(s{Ends);'velocity';s{Velocities
            end.
        end.
    case. 'BURNDOWN' do.
        s =. sprint 0{::y
        phase =. s{Phases
        if. phase=0 do. fail 'sprint not started' end.
        start =. s{Starts
        if. phase=1 do. last =. Day else. last =. s{Ends end.
        say 'BURNDOWN';(s{::SprintNames);(phase{::PhaseNames);'days';1+last-start
        value =. 0
        for_day. start+i.1+last-start do.
            stored =. (<s,day){Daily
            if. stored>:0 do. value =. stored end.
            say 'day';day;value
        end.
    end.
)
handle =: 4 : 0
    select. x
    case. 'DAY' do.
        day =. 0".0{::y
        if. day<Day do. fail 'day backwards' end.
        Day =: day
        say 'DAY';Day
    case. 'USER' do.
        name =. 0{::y
        if. (<name)e.Users do. fail 'user exists' end.
        Users =: Users,<name
        emit 'USER ',name
    case. 'CREATE' do.
        id =. 0".0{::y
        if. id e.IssueIds do. fail 'issue exists' end.
        kind =. TypeNames i.1{y
        if. kind=#TypeNames do. fail 'bad type' end.
        priority =. PriorityNames i.2{y
        if. priority=#PriorityNames do. fail 'bad priority' end.
        index =. #IssueIds
        state =. {.kind{::Workflows
        IssueIds =: IssueIds,id
        Types =: Types,kind
        Priorities =: Priorities,priority
        States =: States,state
        Assignees =: Assignees,_1
        Reviewers =: Reviewers,_1
        Estimates =: Estimates,_1
        IssueSprints =: IssueSprints,_1
        Comments =: Comments,0
        Duplicates =: Duplicates,_1
        Titles =: Titles,<' ' join 3}.y
        Histories =: Histories,<0$a:
        Blocks =: ((#IssueIds),#IssueIds){.Blocks
        index record 'CREATE ',(kind{::TypeNames),' ',priority{::PriorityNames
        say 'CREATE';id;(kind{::TypeNames);(priority{::PriorityNames);state{::StateNames
    case. 'PRIORITY';'ASSIGN';'REVIEWER';'ESTIMATE';'COMMENT' do. x edit_command y
    case. 'MOVE' do. move_command y
    case. 'LINK';'UNLINK' do. x link_command y
    case. 'SPRINT' do. sprint_command y
    case. do. x display_command y
    end.
)
execute =: 3 : 0
    fields =. ' ' split y
    cmd =. 0{::fields
    Output =: 0$a:
    try.
        cmd handle }.fields
    catcht.
        Output =: <'ERROR ',Error
    end.
    active =. active_sprint ''
    if. active>:0 do. record_sprint active end.
    Output
)
main =: 3 : 0
    count =. 0".1!:1 3
    for_i. i.count do.
        output =. execute 1!:1 3
        for_line. output do. ((>line),LF) 1!:2 4 end.
    end.
    i.0
)
main ''
