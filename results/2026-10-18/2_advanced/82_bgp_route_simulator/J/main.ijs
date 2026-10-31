load 'topology.ijs'
load 'policy.ijs'
load 'decision.ijs'
load 'simulator.ijs'
load 'report.ijs'

ForwardResults =: ;:'DELIVERED LOOP BLACKHOLE UNREACHABLE'
ConvergenceHeader =: 'event,time,kind,status,convergence_time,updates,withdrawals,drops,best_changes,routes_changed,max_exploration'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
)
parse_integer =: 3 : 0
    text =. '_'(I.y='-')}y
    ".text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
read_lines =: 3 : 0
    text =. 1!:1 <y
    if. 0=#text do.
        0$a:
    else.
        <;._2 text
    end.
)
split_words =: 3 : '<;._1 '' '',y'
log_update =: 3 : 'UpdateLog =: UpdateLog,<(integer Time),'' '',y'
initialize_state =: 3 : 0
    AllPrefixes =: /:~~.PrefixCandidates
    NumberPrefixes =: #AllPrefixes
    NumberAS =: #ASNumbers
    NumberSessions =: #SessionOwners
    Origination =: (NumberAS,NumberPrefixes)$<0$a:
    LocRib =: Origination
    Incoming =: (NumberSessions,NumberPrefixes)$<0$a:
    Outgoing =: Incoming
    Pending =: (NumberSessions,NumberPrefixes)$0
    Timers =: NumberSessions$_1
    SessionSent =: NumberSessions$0
    SessionReceived =: NumberSessions$0
    ASChanges =: NumberAS$0
    ChangedPrefixes =: NumberPrefixes$0
    initialize_messages ''
    UpdateLog =: 0$a:
    Convergence =: ,<ConvergenceHeader
    TraceRecords =: 0$a:
    CurrentTraces =: (#TraceSources)$_1
    RingRecords =: 0$a:
    CurrentRings =: i.0
    Divergences =: 0$a:
    Time =: 0
)
import_route =: 4 : 0
    session =. x
    'prefix attribute' =. y
    'path origin med communities' =. attribute
    owner =. session{SessionOwners
    link =. session{SessionLinks
    descriptor =. (<0),(<owner),(<link),(<prefix),(<path),<communities
    rule =. applied_rule descriptor
    local_pref =. (session{SessionRoles){DefaultPrefs
    if. rule~:_1 do.
        if. rule{RuleDeny do.
            (<0$a:),<rule return.
        end.
        value =. rule{RuleLocalPref
        if. value~:_1 do.
            local_pref =. value
        end.
        value =. rule{RuleMed
        if. value~:_1 do.
            med =. value
        end.
        communities =. rule edit_communities communities
    end.
    route =. (<path),(<origin),(<med),(<communities),(<local_pref),<link
    (<route),<rule
)
candidate_routes =: 4 : 0
    result =. 0$a:
    for_session. x{::SessionsByAS do.
        attribute =. >(<session,y){Incoming
        if. #attribute do.
            'route rule' =. session import_route(<y),<attribute
            if. #route do.
                result =. result,<route
            end.
        end.
    end.
    result
)
advertised =: 4 : 0
    session =. x
    prefix =. y
    owner =. session{SessionOwners
    link =. session{SessionLinks
    neighbor =. session{SessionOthers
    route =. >(<owner,prefix){LocRib
    absent =. (<0$a:),<_1
    if. 0=#route do.
        absent return.
    end.
    'path origin med communities local_pref learned_link' =. route
    if. learned_link~:_1 do.
        if. ({.path)=neighbor{ASNumbers do.
            absent return.
        end.
    end.
    if. NoExport community_member communities do.
        absent return.
    end.
    descriptor =. (<1),(<owner),(<link),(<prefix),(<path),<communities
    rule =. applied_rule descriptor
    allowed =. 0
    if. rule~:_1 do.
        if. rule{RuleDeny do.
            (<0$a:),<rule return.
        end.
        allowed =. rule{RuleAllow
    end.
    if. (-.allowed)*.learned_link~:_1 do.
        if. ((owner link_role learned_link)~:0)*.(session{SessionRoles)~:0 do.
            (<0$a:),<rule return.
        end.
    end.
    prepend =. 0
    med =. 0
    if. rule~:_1 do.
        if. _1~:rule{RulePrepend do.
            prepend =. rule{RulePrepend
        end.
        if. _1~:rule{RuleMed do.
            med =. rule{RuleMed
        end.
        communities =. rule edit_communities communities
    end.
    path =. ((1+prepend)$owner{ASNumbers),path
    attribute =. (<path),(<origin),(<med),<communities
    (<attribute),<rule
)
process_pending =: 3 : 0
    session =. y
    owner =. session{SessionOwners
    link =. session{SessionLinks
    sent =. 0
    for_prefix. I.session{Pending do.
        'content rule' =. session advertised prefix
        previous =. >(<session,prefix){Outgoing
        if. previous-:content do.
            continue.
        end.
        Outgoing =: (<content)(<session,prefix)}Outgoing
        descriptor =. (<owner),(<session{SessionOthers),(<link),(<prefix),<content
        message =. enqueue_message descriptor
        suffix =. 'WITHDRAW'
        if. #content do.
            suffix =. 'ANNOUNCE ',attribute_text content
        else.
            EventCounts =: (1+2{EventCounts)2}EventCounts
        end.
        log_update 'SEND ',(message_text message),' ',suffix
        SessionSent =: ((session{SessionSent)+1)session}SessionSent
        EventCounts =: (1+1{EventCounts)1}EventCounts
        sent =. sent+1
        if. rule~:_1 do.
            RuleHits =: ((rule{RuleHits)+1)rule}RuleHits
        end.
    end.
    Pending =: (NumberPrefixes$0)session}Pending
    timer =. _1
    if. (sent>0)*.(link{LinkMrai)>:1 do.
        timer =. Time+link{LinkMrai
    end.
    Timers =: timer session}Timers
)
redecide =: 4 : 0
    owner =. x
    prefix =. y
    route =. >(<owner,prefix){Origination
    if. 0=#route do.
        candidates =. owner candidate_routes prefix
        if. #candidates do.
            route =. 0{::best_route candidates
        end.
    end.
    previous =. >(<owner,prefix){LocRib
    if. route-:previous do.
        i.0 return.
    end.
    LocRib =: (<route)(<owner,prefix)}LocRib
    log_update 'BEST ',(integer owner{ASNumbers),' ',(prefix_text prefix{AllPrefixes),' ',route_text route
    ASChanges =: ((owner{ASChanges)+1)owner}ASChanges
    EventCounts =: (1+4{EventCounts)4}EventCounts
    position =. <owner,prefix
    Exploration =: (1+position{Exploration)position}Exploration
    EventBestLines =: EventBestLines,<(<Time),(<owner),(<prefix),<route
    ChangedPrefixes =: 1 prefix}ChangedPrefixes
    for_session. owner{::SessionsByAS do.
        if. (session{SessionLinks){LinkUp do.
            Pending =: 1(<session,prefix)}Pending
            if. _1=session{Timers do.
                process_pending session
            end.
        end.
    end.
)
receive_message =: 3 : 0
    message =. y
    MsgActive =: 0 message}MsgActive
    owner =. message{MsgReceiver
    link =. message{MsgLink
    prefix =. message{MsgPrefix
    content =. message{::MsgContent
    session =. (<owner,link){SessionIndex
    SessionReceived =: ((session{SessionReceived)+1)session}SessionReceived
    EventCounts =: (Time-PeriodStart)0}EventCounts
    if. 0=#content do.
        Incoming =: (<0$a:)(<session,prefix)}Incoming
        result =. 'WITHDRAW'
    elseif. (owner{ASNumbers)e.0{::content do.
        Incoming =: (<0$a:)(<session,prefix)}Incoming
        result =. 'ANNOUNCE loop'
    else.
        Incoming =: (<content)(<session,prefix)}Incoming
        'route rule' =. session import_route(<prefix),<content
        if. rule~:_1 do.
            RuleHits =: ((rule{RuleHits)+1)rule}RuleHits
        end.
        if. 0=#route do.
            result =. 'ANNOUNCE deny ',rule{::RuleNames
        elseif. rule~:_1 do.
            result =. 'ANNOUNCE accept ',rule{::RuleNames
        else.
            result =. 'ANNOUNCE accept'
        end.
    end.
    log_update 'RECV ',(message_text message),' ',result
    owner redecide prefix
)
originate =: 3 : 0
    'owner prefix origin communities' =. y
    index =. AllPrefixes i.prefix
    route =. originated_route(<origin),<communities
    Origination =: (<route)(<owner,index)}Origination
    owner redecide index
)
link_down =: 3 : 0
    link =. y
    LinkUp =: 0 link}LinkUp
    LinkDownCounts =: ((link{LinkDownCounts)+1)link}LinkDownCounts
    for_message. remove_link_messages link do.
        log_update 'DROP ',message_text message
        EventCounts =: (1+3{EventCounts)3}EventCounts
    end.
    endpoints =. /:~(link{LinkFirst),link{LinkSecond
    remembered =. 0$a:
    for_owner. endpoints do.
        session =. (<owner,link){SessionIndex
        prefixes =. I.0<#&>session{Incoming
        remembered =. remembered,<prefixes
        Incoming =: (NumberPrefixes$<0$a:)session}Incoming
        Outgoing =: (NumberPrefixes$<0$a:)session}Outgoing
        Pending =: (NumberPrefixes$0)session}Pending
        Timers =: _1 session}Timers
    end.
    for_i. i.#endpoints do.
        owner =. i{endpoints
        for_prefix. i{::remembered do.
            owner redecide prefix
        end.
    end.
)
link_up =: 3 : 0
    LinkUp =: 1 y}LinkUp
    for_owner. /:~(y{LinkFirst),y{LinkSecond do.
        session =. (<owner,y){SessionIndex
        pending =. 0<#&>owner{LocRib
        Pending =: pending session}Pending
        process_pending session
    end.
)
change_policy =: 4 : 0
    rule =. x
    RuleActive =: y rule}RuleActive
    owner =. rule{RuleOwners
    sessions =. owner{::SessionsByAS
    if. 0=rule{RuleDirections do.
        prefixes =. NumberPrefixes$0
        for_session. sessions do.
            prefixes =. prefixes+.0<#&>session{Incoming
        end.
        for_prefix. I.prefixes do.
            owner redecide prefix
        end.
    else.
        local_prefixes =. 0<#&>owner{LocRib
        for_session. sessions do.
            if. (session{SessionLinks){LinkUp do.
                pending =. (session{Pending)+.local_prefixes+.0<#&>session{Outgoing
                Pending =: pending session}Pending
                if. _1=session{Timers do.
                    process_pending session
                end.
            end.
        end.
    end.
)
execute_event =: 3 : 0
    event =. y
    log_update 'EVENT ',(integer event),' ',event{::EventTexts
    fields =. event{::EventFields
    kind =. event{::EventKinds
    select. kind
    case. 'INITIAL' do.
        for_initial. Initial do.
            originate >initial
        end.
    case. 'ANNOUNCE' do.
        owner =. ASNumbers i.parse_integer 1{::fields
        prefix =. parse_prefix 2{::fields
        origin =. Origins i.3{fields
        communities =. parse_communities 4}.fields
        originate (<owner),(<prefix),(<origin),<communities
    case. 'WITHDRAW' do.
        owner =. ASNumbers i.parse_integer 1{::fields
        prefix =. AllPrefixes i.parse_prefix 2{::fields
        Origination =: (<0$a:)(<owner,prefix)}Origination
        owner redecide prefix
    case. 'LINK_DOWN' do. link_down LinkNames i.2{fields
    case. 'LINK_UP' do. link_up LinkNames i.2{fields
    case. 'POLICY_ON';'POLICY_OFF' do.
        rule =. RuleNames i.2{fields
        rule change_policy kind-:'POLICY_ON'
    end.
)

collapse_runs =: 3 : 0
    result =. i.0
    for_value. y do.
        if. 0=#result do.
            result =. ,value
        elseif. value~:{:result do.
            result =. result,value
        end.
    end.
    result
)
valley_position =: 3 : 0
    position =. 0
    while. position<#y do.
        if. 'U'~:position{y do.
            break.
        end.
        position =. position+1
    end.
    if. position<#y do.
        if. 'P'=position{y do.
            position =. position+1
        end.
    end.
    while. position<#y do.
        if. 'D'~:position{y do.
            break.
        end.
        position =. position+1
    end.
    position
)
forward_path =: 4 : 0
    owner =. x
    visits =. ,x
    hops =. 0 3$0
    count =. 0
    arrival =. _1
    while. 1 do.
        chosen =. _1
        longest =. _1
        for_prefix. I.0<#&>owner{LocRib do.
            candidate =. prefix{AllPrefixes
            if. candidate contains_address y do.
                length =. 1{candidate
                if. length>longest do.
                    chosen =. prefix
                    longest =. length
                end.
            end.
        end.
        if. chosen=_1 do.
            result =. 3
            if. #hops do.
                result =. 2
            end.
            break.
        end.
        route =. >(<owner,chosen){LocRib
        link =. 5{::route
        hops =. hops,owner,chosen,link
        if. link=_1 do.
            result =. 0
            arrival =. owner
            break.
        end.
        count =. count+1
        owner =. owner other_end link
        repeated =. owner e.visits
        visits =. visits,owner
        if. repeated do.
            result =. 1
            break.
        end.
    end.
    (<result),(<visits),(<hops),(<count),<arrival
)
prefix_loops =: 3 : 0
    arrows =. NumberAS$_1
    for_owner. i.NumberAS do.
        route =. >(<owner,y){LocRib
        if. #route do.
            link =. 5{::route
            if. link~:_1 do.
                arrows =. (owner other_end link)owner}arrows
            end.
        end.
    end.
    loops =. 0$a:
    for_start. i.NumberAS do.
        path =. i.0
        current =. start
        while. current~:_1 do.
            if. current e.path do.
                cycle =. (path i.current)}.path
                cycle =. (cycle i.<./cycle)|.cycle
                if. -.(<cycle)e.loops do.
                    loops =. loops,<cycle
                end.
                break.
            end.
            path =. path,current
            current =. current{arrows
        end.
    end.
    keys =. i.0
    for_loop. loops do.
        keys =. keys,{.>loop
    end.
    (/:keys){loops
)
forwarding_checks =: 3 : 0
    for_prefix. I.ChangedPrefixes do.
        loops =. prefix_loops prefix
        for_id. CurrentRings do.
            record =. id{::RingRecords
            if. prefix=0{::record do.
                loop =. 1{::record
                if. -.(<loop)e.loops do.
                    record =. (<Time)3}record
                    RingRecords =: (<record)id}RingRecords
                    CurrentRings =: CurrentRings#~CurrentRings~:id
                end.
            end.
        end.
        for_loop. loops do.
            exists =. 0
            for_id. CurrentRings do.
                record =. id{::RingRecords
                if. (prefix=0{::record)*.(>loop)-:1{::record do.
                    exists =. 1
                    break.
                end.
            end.
            if. -.exists do.
                id =. #RingRecords
                record =. (<prefix),loop,(<Time),<_1
                RingRecords =: RingRecords,<record
                CurrentRings =: CurrentRings,id
            end.
        end.
    end.
    for_trace. i.#TraceSources do.
        path =. (trace{TraceSources)forward_path trace{TraceAddresses
        result =. 0{::path
        visits =. 1{::path
        bad =. result e.1 2
        id =. trace{CurrentTraces
        if. id~:_1 do.
            record =. id{::TraceRecords
            same =. bad*.(result=1{::record)*.visits-:2{::record
            if. -.same do.
                record =. (<Time)4}record
                TraceRecords =: (<record)id}TraceRecords
                CurrentTraces =: _1 trace}CurrentTraces
            end.
        end.
        if. bad*._1=trace{CurrentTraces do.
            id =. #TraceRecords
            record =. (<trace),(<result),(<visits),(<Time),<_1
            TraceRecords =: TraceRecords,<record
            CurrentTraces =: id trace}CurrentTraces
        end.
    end.
)
global_state =: 3 : 0
    remaining =. Timers
    running =. I.Timers~:_1
    remaining =. ((running{Timers)-Time)running}remaining
    messages =. 0$a:
    for_id. ordered_messages '' do.
        record =. (<(id{MsgArrival)-Time),(<id{MsgReceiver),(<id{MsgSender),(<id{MsgLink),(<id{MsgPrefix),<id{::MsgContent
        messages =. messages,<record
    end.
    (<Incoming),(<Outgoing),(<Pending),(<remaining),<messages
)
detect_divergence =: 3 : 0
    if. (DivergenceFirst~:_1)+.DeliveryTimes>StepCap do.
        i.0 return.
    end.
    state =. global_state ''
    index =. SeenStates i.<state
    if. index<#SeenStates do.
        DivergenceFirst =: index{SeenTimes
        DivergenceRepeat =: Time
        CycleLines =: 0$a:
        for_line. EventBestLines do.
            line =. >line
            if. ((0{::line)>DivergenceFirst)*.(0{::line)<:Time do.
                CycleLines =: CycleLines,<line
            end.
        end.
        i.0 return.
    end.
    SeenTimes =: SeenTimes,Time
    SeenStates =: SeenStates,<state
)
quiet =: 3 : '(-.+./MsgActive)*.-.+./,Pending'
next_moment =: 3 : 0
    candidates =. Timers#~Timers~:_1
    active =. I.MsgActive
    if. #active do.
        candidates =. candidates,<./active{MsgArrival
    end.
    if. y~:_1 do.
        candidates =. candidates,y
    end.
    <./candidates
)
run_period =: 3 : 0
    event =. y
    PeriodStart =: event{EventTimes
    Time =: PeriodStart
    BeforeRib =. LocRib
    EventCounts =: 7$0
    Exploration =: (NumberAS,NumberPrefixes)$0
    EventBestLines =: 0$a:
    SeenTimes =: i.0
    SeenStates =: 0$a:
    DivergenceFirst =: _1
    DivergenceRepeat =: _1
    CycleLines =: 0$a:
    DeliveryTimes =: 0
    ChangedPrefixes =: NumberPrefixes$0
    boundary =. _1
    if. (event+1)<#EventTimes do.
        boundary =. ((event+1){EventTimes)-1
    end.
    execute_event event
    while. 1 do.
        due =. due_messages ''
        for_message. due do.
            receive_message message
        end.
        for_session. I.Timers=Time do.
            Timers =: _1 session}Timers
            if. +./session{Pending do.
                process_pending session
            end.
        end.
        if. +./ChangedPrefixes do.
            forwarding_checks ''
        end.
        if. #due do.
            DeliveryTimes =: DeliveryTimes+1
            detect_divergence ''
        end.
        is_quiet =. quiet ''
        if. boundary=_1 do.
            if. is_quiet+.(DivergenceFirst~:_1)+.DeliveryTimes>:StepCap do.
                break.
            end.
        elseif. Time=boundary do.
            break.
        end.
        Time =: next_moment boundary
        ChangedPrefixes =: NumberPrefixes$0
    end.
    if. DivergenceFirst~:_1 do.
        status =. 'DIVERGENT'
        Divergences =: Divergences,<( <event),(<DivergenceFirst),(<DivergenceRepeat),<CycleLines
    elseif. is_quiet do.
        status =. 'CONVERGED'
    elseif. boundary=_1 do.
        status =. 'CAPPED'
    else.
        status =. 'UNSETTLED'
    end.
    changed =. 0
    for_owner. i.NumberAS do.
        for_prefix. i.NumberPrefixes do.
            position =. <owner,prefix
            changed =. changed+-. (>position{BeforeRib)-:>position{LocRib
        end.
    end.
    EventCounts =: changed 5}EventCounts
    maximum =. 0
    if. NumberPrefixes do.
        maximum =. >./,Exploration
    end.
    EventCounts =: maximum 6}EventCounts
    values =. (<integer event),(<integer PeriodStart),(event{EventKinds),(<status),integer&.>EventCounts
    Convergence =: Convergence,<','join values
    SeenStates =: 0$a:
)

rib_lines =: 3 : 0
    lines =. 0$a:
    for_owner. i.NumberAS do.
        prefixes =. I.0<#&>owner{LocRib
        local =. 0
        for_prefix. prefixes do.
            local =. local+local_route >(<owner,prefix){LocRib
        end.
        sessions =. owner{::SessionsByAS
        line =. 'AS ',(integer owner{ASNumbers),' routes ',(integer #prefixes),' local ',integer local
        line =. line,' sent ',(integer +/sessions{SessionSent),' received ',integer +/sessions{SessionReceived
        lines =. lines,<line,' changes ',integer owner{ASChanges
        for_session. sessions do.
            incoming =. I.0<#&>session{Incoming
            accepted =. 0
            for_prefix. incoming do.
                attribute =. >(<session,prefix){Incoming
                'route rule' =. session import_route(<prefix),<attribute
                accepted =. accepted+0<#route
            end.
            link =. session{SessionLinks
            state =. (link{LinkUp){::'DOWN';'UP'
            line =. 'SESSION ',(link{::LinkNames),' ',(integer (session{SessionOthers){ASNumbers),' ',(session{SessionRoles){::Roles
            line =. line,' ',state,' in ',(integer #incoming),' accepted ',(integer accepted),' out ',integer +/0<#&>session{Outgoing
            line =. line,' sent ',(integer session{SessionSent),' received ',integer session{SessionReceived
            lines =. lines,<line,' flaps ',integer link{LinkDownCounts
        end.
        for_prefix. prefixes do.
            route =. >(<owner,prefix){LocRib
            candidates =. owner candidate_routes prefix
            line =. (prefix_text prefix{AllPrefixes),' ',(route_text route),' candidates ',integer #candidates
            if. -.local_route route do.
                selected =. best_route candidates
                line =. line,' reason ',1{::selected
            end.
            lines =. lines,<line
            remaining =. 0$a:
            for_candidate. candidates do.
                if. -.route-:>candidate do.
                    remaining =. remaining,candidate
                end.
            end.
            while. #remaining do.
                alternate =. 0{::best_route remaining
                lines =. lines,<'ALT ',route_text alternate
                index =. remaining i.<alternate
                remaining =. remaining#~index~:i.#remaining
            end.
        end.
    end.
    lines
)
trace_lines =: 3 : 0
    trace =. y
    source =. trace{TraceSources
    'result visits hops count arrival' =. source forward_path trace{TraceAddresses
    line =. 'TRACE ',(integer source{ASNumbers),' ',(trace{::TraceTexts),' ',(result{::ForwardResults),' hops ',integer count
    lines =. ,<line
    for_hop. hops do.
        'owner prefix link' =. hop
        line =. 'HOP ',(integer owner{ASNumbers),' ',prefix_text prefix{AllPrefixes
        if. link=_1 do.
            line =. line,' LOCAL'
        else.
            line =. line,' next ',(integer (owner other_end link){ASNumbers),' link ',link{::LinkNames
        end.
        lines =. lines,<line
    end.
    if. result=1 do.
        lines =. lines,<'HOP ',(integer ({:visits){ASNumbers),' REVISIT'
    elseif. result e.2 3 do.
        lines =. lines,<'HOP ',(integer ({:visits){ASNumbers),' NOROUTE'
    end.
    if. 0=#hops do.
        lines =. lines,<'CONTROL NONE'
    else.
        prefix =. (<0,1){hops
        route =. >(<source,prefix){LocRib
        path =. 0{::route
        notation =. 'LOCAL'
        if. -.local_route route do.
            notation =. path_text path
        end.
        matching =. (result=0)*.(collapse_runs path)-:(}.visits){ASNumbers
        match =. matching{::'MISMATCH';'MATCH'
        lines =. lines,<'CONTROL ',notation,' ',match
    end.
    if. count do.
        pattern =. ''
        for_hop. hops do.
            'owner prefix link' =. hop
            if. link~:_1 do.
                pattern =. pattern,owner link_direction link
            end.
        end.
        judgment =. ((valley_position pattern)=#pattern){::'VALLEY';'VALLEYFREE'
        lines =. lines,<'PATTERN ',pattern,' ',judgment
    end.
    lines
)
path_lines =: 3 : 0
    lines =. 0$a:
    for_trace. i.#TraceSources do.
        lines =. lines,trace_lines trace
    end.
    prefixes =. I.+./0<#&>Origination
    names =. 0$a:
    for_prefix. prefixes do.
        names =. names,<prefix_text prefix{AllPrefixes
    end.
    line =. 'PREFIXES'
    if. #names do.
        line =. line,' ',','join names
    end.
    lines =. lines,<line
    for_source. i.NumberAS do.
        symbols =. ''
        for_prefix. prefixes do.
            path =. source forward_path(<prefix,0){AllPrefixes
            'result visits hops count arrival' =. path
            if. result=0 do.
                if. count=0 do.
                    symbol =. '*'
                elseif. #>(<arrival,prefix){Origination do.
                    symbol =. '+'
                else.
                    symbol =. 'X'
                end.
            else.
                symbol =. result{' LBU'
            end.
            symbols =. symbols,symbol
        end.
        line =. 'REACH ',integer source{ASNumbers
        if. #symbols do.
            line =. line,' ',symbols
        end.
        lines =. lines,<line
    end.
    lines
)
end_text =: 3 : 0
    if. y=_1 do.
        'END'
    else.
        integer y
    end.
)
audit_lines =: 3 : 0
    lines =. 0$a:
    keys =. 0 2$0
    for_record. TraceRecords do.
        record =. >record
        keys =. keys,(3{::record),0{::record
    end.
    loops =. 0
    blackholes =. 0
    for_id. /:keys do.
        'trace result visits start end' =. id{::TraceRecords
        if. result=1 do.
            loops =. loops+1
        else.
            blackholes =. blackholes+1
        end.
        line =. (result{::ForwardResults),' ',(integer (trace{TraceSources){ASNumbers),' ',trace{::TraceTexts
        line =. line,' from ',(integer start),' to ',end_text end
        if. result=2 do.
            line =. line,' at ',integer ({:visits){ASNumbers
        end.
        lines =. lines,<line,' path ',path_text visits{ASNumbers
    end.
    keys =. 0 3$0
    for_record. RingRecords do.
        'prefix path start end' =. >record
        keys =. keys,start,prefix,{.path
    end.
    for_id. /:keys do.
        'prefix path start end' =. id{::RingRecords
        line =. 'RING ',(prefix_text prefix{AllPrefixes),' from ',(integer start),' to ',end_text end
        lines =. lines,<line,' path ',path_text path{ASNumbers
    end.
    routes =. 0
    valleys =. 0
    for_owner. i.NumberAS do.
        for_prefix. I.0<#&>owner{LocRib do.
            route =. >(<owner,prefix){LocRib
            if. local_route route do.
                continue.
            end.
            routes =. routes+1
            path =. collapse_runs(owner{ASNumbers),0{::route
            pattern =. ''
            for_i. i.(#path)-1 do.
                first =. ASNumbers i.i{path
                second =. ASNumbers i.(i+1){path
                link =. first connecting_link second
                pattern =. pattern,first link_direction link
            end.
            violation =. valley_position pattern
            if. violation~:#pattern do.
                valleys =. valleys+1
                line =. 'VALLEY ',(integer owner{ASNumbers),' ',(prefix_text prefix{AllPrefixes),' path ',path_text 0{::route
                lines =. lines,<line,' pattern ',pattern,' leaker ',integer violation{path
            end.
        end.
    end.
    for_rule. i.#RuleNames do.
        direction =. (rule{RuleDirections){::'IMPORT';'EXPORT'
        state =. (rule{RuleActive){::'OFF';'ON'
        line =. 'RULE ',(rule{::RuleNames),' ',direction,' ',state,' hits ',integer rule{RuleHits
        lines =. lines,<line
    end.
    for_divergence. Divergences do.
        'event first repeat cycle' =. >divergence
        line =. 'DIVERGENT event ',(integer event),' first ',(integer first),' repeat ',integer repeat
        lines =. lines,<line,' period ',integer repeat-first
        oscillations =. (NumberAS,NumberPrefixes)$0
        for_entry. cycle do.
            'time owner prefix route' =. >entry
            line =. 'CYCLE ',(integer time),' ',(integer owner{ASNumbers),' ',prefix_text prefix{AllPrefixes
            lines =. lines,<line,' ',route_text route
            position =. <owner,prefix
            oscillations =. (1+position{oscillations)position}oscillations
        end.
        for_owner. i.NumberAS do.
            for_prefix. I.0<owner{oscillations do.
                line =. 'OSCILLATE ',(integer owner{ASNumbers),' ',(prefix_text prefix{AllPrefixes),' changes ',integer (<owner,prefix){oscillations
                lines =. lines,<line
            end.
        end.
    end.
    line =. 'SUMMARY loops ',(integer loops),' blackholes ',(integer blackholes),' rings ',integer #RingRecords
    line =. line,' routes ',(integer routes),' valleys ',(integer valleys),' divergent ',(integer #Divergences),' end ',integer Time
    lines,<line
)
run =: 3 : 0
    PrefixCandidates =: 0 2$0
    read_topology ''
    read_policies ''
    read_events_params ''
    initialize_state ''
    for_event. i.#EventTimes do.
        run_period event
    end.
    try.
        1!:5 <'output'
    catch.
    end.
    'updates.txt'write_lines UpdateLog
    'convergence.csv'write_lines Convergence
    'ribs.txt'write_lines rib_lines ''
    'paths.txt'write_lines path_lines ''
    'audit.txt'write_lines audit_lines ''
)
run ''
