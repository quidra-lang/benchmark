LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
words =: 3 : '(<;._1 '' '',y)-.<'''''
split =: 4 : '<;._1 x,y'
join =: 4 : 0
    if. 0=#y do. '' return. end.
    (#x)}.;(<x),&.>y
)
yes =: 3 : 'y{::''no'';''yes'''
listed =: 3 : 0
    if. #y do. ' 'join y else. 'none' end.
)
fail =: 3 : 0
    Reason=:y
    throw.
)
number =: 4 : 0
    'low high'=.x
    if. (0=#y)+.(10<#y) do. _1 return. end.
    if. (1<#y)*.'0'={.y do. _1 return. end.
    if. -. *./y e.'0123456789' do. _1 return. end.
    value=.0".y
    if. (value<low)+.value>high do. _1 else. value end.
)
mark =: 3 : 0
    entries=.0$a:
    for_value. y do.
        if. value<0 do. entries=.entries,<'w' else. entries=.entries,<num value end.
    end.
    '(',(','join entries),')'
)
rankOmega =: 3 : 'y+(y<0)*1000000000001'
pIndex =: 3 : 'PNames i.<y'
tIndex =: 3 : 'TNames i.<y'
resetNet =: 3 : 0
    NetName=:y
    PNames=:TNames=:0$a:
    Initial=:Capacity=:Priority=:i.0
    Pre=:Post=:Inhibitor=:16 16$0
    ArcCount=:InhibitorCount=:0
    Current=:i.0
    History=:0$a:
)
define =: 3 : 0
    w=.words y
    keyword=.0{::w
    count=.<:#w
    tag=.(words 'place transition arc inhibit')i.<keyword
    if. tag=4 do. fail 'unknown definition ',keyword end.
    if. tag=0 do. valid=.count e.2 3 elseif. tag=1 do. valid=.count e.1 2 else. valid=.count=3 end.
    if. -.valid do. fail 'wrong number of arguments' end.
    a=.1{::w
    if. tag e.0 1 do.
        if. (<a)e.PNames,TNames do. fail 'duplicate name ',a end.
        if. tag=0 do.
            tokens=.0".2{::w
            capacity=.0
            if. count=3 do. capacity=.0".3{::w end.
            if. (count=3)*.tokens>capacity do. fail 'tokens exceed capacity of ',a end.
            PNames=:PNames,<a
            Initial=:Initial,tokens
            Capacity=:Capacity,capacity
        else.
            priority=.0
            if. count=2 do. priority=.0".2{::w end.
            TNames=:TNames,<a
            Priority=:Priority,priority
        end.
    elseif. tag=2 do.
        b=.2{::w
        for_node. a;b do.
            if. -.node e.PNames,TNames do. fail 'unknown node ',>node end.
        end.
        pa=.pIndex a
        pb=.pIndex b
        if. (pa<#PNames)=(pb<#PNames) do. fail 'arc must connect a place and a transition' end.
        if. pa<#PNames do.
            p=.pa
            t=.tIndex b
            if. 0<(<p,t){Pre do. fail 'duplicate arc ',a,' ',b end.
            Pre=:(0".3{::w)(<p,t)}Pre
        else.
            p=.pb
            t=.tIndex a
            if. 0<(<p,t){Post do. fail 'duplicate arc ',a,' ',b end.
            Post=:(0".3{::w)(<p,t)}Post
        end.
        ArcCount=:>:ArcCount
    else.
        p=.pIndex a
        t=.tIndex 2{::w
        if. p=#PNames do. fail 'unknown place ',a end.
        if. t=#TNames do. fail 'unknown transition ',2{::w end.
        if. 0<(<p,t){Inhibitor do. fail 'duplicate inhibitor ',a,' ',2{::w end.
        Inhibitor=:(0".3{::w)(<p,t)}Inhibitor
        InhibitorCount=:>:InhibitorCount
    end.
)
reason =: 4 : 0
    m=.x
    t=.y
    pre=.(#PNames){.t{"1 Pre
    post=.(#PNames){.t{"1 Post
    inhibit=.(#PNames){.t{"1 Inhibitor
    positions=.I.(m>:0)*.m<pre
    if. #positions do. 'insufficient tokens in ',({.positions){::PNames return. end.
    positions=.I.(inhibit>0)*.(m<0)+.m>:inhibit
    if. #positions do. 'inhibited by ',({.positions){::PNames return. end.
    positions=.I.(Capacity>0)*.((m<0)+.((m-pre)+post)>Capacity)
    if. #positions do. 'capacity of ',(({.positions){::PNames),' exceeded' return. end.
    ''
)
enabled =: 3 : 0
    result=.i.0
    for_t. i.#TNames do. if. 0=#y reason t do. result=.result,t end. end.
    result
)
fire =: 4 : 0
    delta=.(#PNames){.y{"1 Post-Pre
    result=.x+delta
    _1(I.x<0)}result
)
commit =: 3 : 0
    History=:History,<Current
    Current=:Current fire y
)
visit =: 4 : 0
    seen=.(#x)$0
    pending=.,y
    seen=.1 y}seen
    cursor=.0
    while. cursor<#pending do.
        for_v. (cursor{pending){::x do.
            if. -.v{seen do. seen=.1 v}seen [ pending=.pending,v end.
        end.
        cursor=.>:cursor
    end.
    seen
)
matchTarget =: 4 : 0
    if. 0=#x do. 0 return. end.
    low=.0{"1 x
    high=.1{"1 x
    *./(y>:low)*.(high<0)+.y=high
)
graph =: 4 : 0
    'limit target'=.y
    states=.,<x
    parent=.,_1
    via=.,_1
    edges=.,<0 2$0
    if. target matchTarget x do. states;parent;via;edges;0;0 return. end.
    cursor=.0
    while. cursor<#states do.
        for_t. enabled cursor{::states do.
            m=.(cursor{::states)fire t
            k=.states i.<m
            if. k=#states do.
                if. limit=#states do. states;parent;via;edges;_1;1 return. end.
                states=.states,<m
                parent=.parent,cursor
                via=.via,t
                edges=.edges,<0 2$0
                if. target matchTarget m do. states;parent;via;edges;k;0 return. end.
            end.
            row=.cursor{::edges
            row=.row,t,k
            edges=.(<row)cursor}edges
        end.
        cursor=.>:cursor
    end.
    states;parent;via;edges;_1;0
)
path =: 4 : 0
    parent=.1{::x
    via=.2{::x
    k=.y
    result=.i.0
    while. 0<:k{parent do.
        result=.result,k{via
        k=.k{parent
    end.
    |.result
)
reach =: 4 : 0
    limit=.x
    display=.y
    g=.Current graph limit;0 2$0
    'states parent via edges found aborted'=.g
    if. aborted do. say 'reachability graph limit ',(num limit),' exceeded' return. end.
    N=.#states
    if. display do.
        for_i. i.N do.
            entries=.0$a:
            for_edge. i{::edges do.
                't k'=.edge
                entries=.entries,<(t{::TNames),'->M',num k
            end.
            text=.'dead'
            if. #entries do. text=.' 'join entries end.
            say 'M',(num i),' ',(mark i{::states),': ',text
        end.
        return.
    end.
    adj=.0$a:
    for_row. edges do. adj=.adj,<1{"1 >row end.
    closure=.0 N$0
    for_i. i.N do. closure=.closure,adj visit i end.
    comp=.N$_1
    components=.0
    for_i. i.N do.
        if. 0<:i{comp do. continue. end.
        for_j. i.N do.
            if. ((<i,j){closure)*.(<j,i){closure do. comp=.components j}comp end.
        end.
        components=.>:components
    end.
    terminal=.components$1
    home=.N$1
    maximum=.(#PNames)$0
    dead=.i.0
    edgeCount=.0
    persistent=.1
    for_i. i.N do.
        row=.i{::edges
        if. 0=#row do. dead=.dead,i end.
        edgeCount=.edgeCount+#row
        maximum=.maximum>.i{::states
        home=.home*.i{closure
        for_edge. row do.
            't k'=.edge
            if. (i{comp)~:k{comp do. terminal=.0(i{comp)}terminal end.
            for_other. row do.
                u=.{.other
                if. (u~:t)*.0<#(k{::states)reason u do. persistent=.0 end.
            end.
        end.
    end.
    say 'reachable markings: ',num N
    say 'edges: ',num edgeCount
    say 'components: ',(num components),' (terminal ',(num +/terminal),')'
    say 'dead markings: ',num #dead
    for_i. dead do.
        sequence=.g path i
        text=.'empty'
        if. #sequence do. text=.' 'join sequence{TNames end.
        say '  M',(num i),' ',(mark i{::states),' path ',text
    end.
    bound=.>./maximum
    say 'max tokens: ',mark maximum
    say 'bound: ',num bound
    say 'safe: ',yes bound<:1
    say 'home markings: ',num +/home
    say 'reversible: ',yes 0{home
    say 'persistent: ',yes persistent
    levels=.0$a:
    for_t. i.#TNames do.
        present=.components$0
        used=.cycle=.0
        for_i. i.N do.
            for_edge. i{::edges do.
                'u k'=.edge
                if. u=t do.
                    used=.1
                    present=.1(i{comp)}present
                    if. (i{comp)=k{comp do. cycle=.1 end.
                end.
            end.
        end.
        live=.*./(-.terminal)+.present
        level=.'L0'
        if. live do. level=.'L4' elseif. cycle do. level=.'L3' elseif. used do. level=.'L1' end.
        levels=.levels,<(t{::TNames),'=',level
    end.
    say 'liveness: ',' 'join levels
)
cover =: 3 : 0
    limit=.y
    states=.,<Current
    parent=.,_1
    via=.,_1
    old=.dead=.,0
    cursor=.0
    while. cursor<#states do.
        if. cursor{old do. cursor=.>:cursor continue. end.
        es=.enabled cursor{::states
        dead=.(0=#es)cursor}dead
        ancestors=.i.0
        a=.cursor
        while. a>:0 do. ancestors=.a,ancestors [ a=.a{parent end.
        for_t. es do.
            m=.(cursor{::states)fire t
            for_a. ancestors do.
                previous=.a{::states
                if. (*./(rankOmega m)>:rankOmega previous)*.+./(rankOmega m)>rankOmega previous do.
                    m=._1(I.(Capacity=0)*.(rankOmega m)>rankOmega previous)}m
                end.
            end.
            if. limit=#states do. say 'coverability tree limit ',(num limit),' exceeded' return. end.
            old=.old,(<m)e.states
            states=.states,<m
            parent=.parent,cursor
            via=.via,t
            dead=.dead,0
        end.
        cursor=.>:cursor
    end.
    say 'coverability tree nodes: ',num #states
    maximum=.(#PNames)$0
    for_i. i.#states do.
        suffix=.'root'
        if. i do. suffix=.'<- ',(num i{parent),' ',(i{via){::TNames end.
        text=.'  ',(num i),' ',(mark i{::states),' ',suffix
        if. i{old do. text=.text,' old' end.
        if. i{dead do. text=.text,' dead' end.
        say text
        mask=.(rankOmega i{::states)>rankOmega maximum
        maximum=.((I.mask){i{::states)(I.mask)}maximum
    end.
    say 'bounds: ',mark maximum
    say 'unbounded: ',listed (I.maximum<0){PNames
)
bits =: 3 : 'I.(#PNames){.|.#:y'
setText =: 3 : '''{'',('',''join (bits y){PNames),''}'''
minimalSets =: 3 : 0
    trap=.y
    valid=.i.0
    for_mask. >:i.<:2^#PNames do.
        ps=.bits mask
        ok=.1
        for_t. i.#TNames do.
            input=.+./0<ps{t{"1 Post
            output=.+./0<ps{t{"1 Pre
            if. (trap*.output*.-.input)+.(-.trap)*.input*.-.output do. ok=.0 break. end.
        end.
        if. ok do. valid=.valid,mask end.
    end.
    result=.i.0
    keys=.0,(>:#PNames)$0
    for_mask. valid do.
        ps=.(#PNames){.|.#:mask
        minimal=.1
        for_smaller. valid do.
            if. smaller=mask do. continue. end.
            qs=.(#PNames){.|.#:smaller
            if. *./qs<:ps do. minimal=.0 break. end.
        end.
        if. minimal do.
            result=.result,mask
            keys=.keys,(+/ps),-.ps
        end.
    end.
    (/:keys){result
)
farkas =: 3 : 0
    'n m'=.$y
    rows=.y,.=i.n
    for_j. i.m do.
        collected=.(0=j{"1 rows)#rows
        positives=.(0<j{"1 rows)#rows
        negatives=.(0>j{"1 rows)#rows
        for_r. positives do.
            for_s. negatives do.
                combined=.(-j{s)*r
                combined=.combined+(j{r)*s
                divisor=.+./|combined
                collected=.collected,<.combined%divisor
            end.
        end.
        collected=.~.collected
        supports=.0<m}."1 collected
        rows=.0,(m+n)$0
        for_i. i.#collected do.
            support=.i{supports
            minimal=.1
            for_other. supports do.
                if. (*./other<:support)*.+./other<support do. minimal=.0 break. end.
            end.
            if. minimal do. rows=.rows,i{collected end.
        end.
    end.
    result=.m}."1 rows
    (\:result){result
)
realize =: 3 : 0
    counts=.y
    used=.(#TNames)$0
    stack=.,<Current
    choices=.,0
    sequence=.i.0
    seen=.0$a:
    total=.+/counts
    while. #stack do.
        depth=.#sequence
        if. depth=total do. <sequence return. end.
        chosen=._1
        for_t. (depth{choices)+i.(#TNames)-depth{choices do.
            choices=.(>:t)depth}choices
            if. ((t{used)>:t{counts)+.0<#(depth{::stack)reason t do. continue. end.
            nextUsed=.(>:(t{used))t}used
            if. (<nextUsed)e.seen do. continue. end.
            seen=.seen,<nextUsed
            chosen=.t
            break.
        end.
        if. chosen>:0 do.
            used=.(>:(chosen{used))chosen}used
            sequence=.sequence,chosen
            stack=.stack,<(depth{::stack)fire chosen
            choices=.choices,0
        else.
            stack=.}:stack
            choices=.}:choices
            if. #sequence do.
                t=.{:sequence
                used=.(<:(t{used))t}used
                sequence=.}:sequence
            end.
        end.
    end.
    0$a:
)
invariants =: 3 : 0
    transpose=.y
    matrix=.((i.#PNames){Post-Pre){"1~i.#TNames
    ns=.PNames
    if. transpose do. matrix=.|:matrix [ ns=.TNames end.
    f=.farkas matrix
    covered=.(#ns)$0
    bounds=.(#ns)$_1
    say (transpose{::'P';'T'),'-semiflows: ',num #f
    for_c. f do.
        terms=.0$a:
        for_i. I.c>0 do.
            text=.i{::ns
            if. 1~:i{c do. text=.(num i{c),'*',text end.
            terms=.terms,<text
        end.
        text=.'  ',' + 'join terms
        covered=.covered+.c>0
        if. transpose do.
            sequence=.realize c
            if. #sequence do. say text,': realizable ',' 'join (>sequence){TNames else. say text,': not realizable' end.
        else.
            value=.+/c*Current
            say text,' = ',num value
            for_p. I.c>0 do.
                b=.<.value%p{c
                if. ((p{bounds)<0)+.b<p{bounds do. bounds=.b p}bounds end.
            end.
        end.
    end.
    if. -.transpose do.
        b=.0$a:
        for_value. bounds do.
            if. value<0 do. b=.b,<'-' else. b=.b,<num value end.
        end.
        say 'bounds: (',(','join b),')'
    end.
    say (transpose{::'conservative';'consistent'),': ',yes *./covered
)
classify =: 3 : 0
    ordinary=.*./,((Pre<:1)*.Post<:1)
    pure=.-.+./,(Pre>0)*.Post>0
    inputs=.+/0<((i.#PNames){Pre){"1~i.#TNames
    outputs=.+/"1 0<((i.#PNames){Pre){"1~i.#TNames
    sm=.ordinary
    mg=.ordinary
    fc=.ordinary
    efc=.ordinary
    for_t. i.#TNames do.
        sm=.sm*.(1=t{inputs)*.1=+/0<(i.#PNames){t{"1 Post
    end.
    for_p. i.#PNames do.
        mg=.mg*.(1=p{outputs)*.1=+/0<(i.#TNames){p{Post
        a=.I.0<(i.#TNames){p{Pre
        for_t. a do. if. ((p{outputs)~:1)*.(t{inputs)~:1 do. fc=.0 end. end.
        for_q. i.#PNames do.
            b=.I.0<(i.#TNames){q{Pre
            if. (+./a e.b)*.-.a-:b do. efc=.0 end.
        end.
    end.
    labels=.'ordinary';'pure';'state machine';'marked graph';'free choice';'extended free choice'
    values=.ordinary,pure,sm,mg,fc,efc
    for_i. i.#labels do. say (i{::labels),': ',yes i{values end.
    verdict=.'holds'
    if. -.fc do. verdict=.'not applicable'
    elseif. 12<#PNames do. verdict=.'too many places'
    else.
        traps=.minimalSets 1
        for_s. minimalSets 0 do.
            ps=.bits s
            holds=.0
            for_q. traps do.
                qs=.bits q
                if. (*./qs e.ps)*.0<+/qs{Current do. holds=.1 end.
            end.
            if. -.holds do. verdict=.'fails at ',setText s break. end.
        end.
    end.
    say 'commoner: ',verdict
)
workflow =: 3 : 0
    limit=.y
    sources=.i.0
    sinks=.i.0
    for_p. i.#PNames do.
        if. 0=+/0<(i.#TNames){p{Post do. sources=.sources,p end.
        if. 0=+/0<(i.#TNames){p{Pre do. sinks=.sinks,p end.
    end.
    if. 1~:#sources do. say 'workflow: no (',(num #sources),' source places)' return. end.
    if. 1~:#sinks do. say 'workflow: no (',(num #sinks),' sink places)' return. end.
    i=.{.sources
    o=.{.sinks
    P=.#PNames
    ns=.PNames,TNames
    adj=.rev=.(#ns)#<i.0
    for_p. i.P do.
        for_t. i.#TNames do.
            if. 0<(<p,t){Pre do.
                adj=.(<(p{::adj),P+t)p}adj
                rev=.(<((P+t){::rev),p)(P+t)}rev
            end.
            if. 0<(<p,t){Post do.
                adj=.(<((P+t){::adj),p)(P+t)}adj
                rev=.(<(p{::rev),P+t)p}rev
            end.
        end.
    end.
    forward=.adj visit i
    back=.rev visit o
    for_v. i.#ns do.
        if. -.(v{forward)*.v{back do.
            say 'workflow: no (',(v{::ns),' is not on a path from ',(i{::PNames),' to ',(o{::PNames),')'
            return.
        end.
    end.
    say 'workflow: source ',(i{::PNames),' sink ',o{::PNames
    start=.1 i}P$0
    goal=.1 o}P$0
    g=.start graph limit;0 2$0
    'states parent via edges found aborted'=.g
    if. aborted do. say 'reachability graph limit ',(num limit),' exceeded' return. end.
    finish=.states i.<goal
    rev=.(#states)#<i.0
    used=.(#TNames)$0
    proper=.1
    for_u. i.#states do.
        m=.u{::states
        if. (0<o{m)*.-.m-:goal do. proper=.0 end.
        for_edge. u{::edges do.
            't v'=.edge
            rev=.(<(v{::rev),u)v}rev
            used=.1 t}used
        end.
    end.
    option=.0
    if. finish<#states do. option=.*./rev visit finish end.
    live=.*./used
    say 'option to complete: ',yes option
    say 'proper completion: ',yes proper
    say 'no dead transitions: ',yes live
    say 'sound: ',yes option*.proper*.live
)
Commands =: words 'MARKING RESET SET ENABLED FIRE UNDO SIMULATE CONFLICTS REACH GRAPH COVER PATH INCIDENCE PINV TINV SIPHONS TRAPS CLASSIFY WORKFLOW SHOW'
Arity =: 0 0 2 0 _1 1 3 0 1 1 1 2 0 0 0 0 0 0 1 0
command =: 3 : 0
    w=.words y
    name=.0{::w
    cmd=.Commands i.<name
    if. cmd=#Commands do. fail 'unknown command ',name end.
    expected=.cmd{Arity
    if. expected<0 do. valid=.1<#w else. valid=.(>:expected)=#w end.
    if. -.valid do. fail 'wrong number of arguments' end.
    limit=.0
    if. cmd e.8 9 10 11 18 do.
        limit=.1 2000 number 1{::w
        if. limit<0 do. fail 'invalid limit ',1{::w end.
    end.
    select. cmd
    case. 0;1 do.
        if. cmd=1 do. Current=:Initial [ History=:0$a: end.
        say 'marking ',mark Current
    case. 2 do.
        p=.pIndex 1{::w
        if. p=#PNames do. fail 'unknown place ',1{::w end.
        value=.0 999 number 2{::w
        if. value<0 do. fail 'invalid tokens ',2{::w end.
        if. (0<p{Capacity)*.value>p{Capacity do. fail 'tokens exceed capacity of ',1{::w end.
        Current=:value p}Current
        History=:0$a:
        say 'marking ',mark Current
    case. 3 do. say 'enabled: ',listed (enabled Current){TNames
    case. 4 do.
        ts=.i.0
        for_a. }.w do.
            t=.tIndex >a
            if. t=#TNames do. fail 'unknown transition ',>a end.
            ts=.ts,t
        end.
        for_i. i.#ts do.
            t=.i{ts
            r=.Current reason t
            if. #r do. say 'step ',(num >:i),': ',(t{::TNames),' not enabled (',r,') at ',mark Current return. end.
            commit t
        end.
        say 'fired ',(num #ts),' -> ',mark Current
    case. 5 do.
        k=.1 1000 number 1{::w
        if. k<0 do. fail 'invalid count ',1{::w end.
        h=.#History
        if. k>h do. fail 'cannot undo ',(num k),': history size ',num h end.
        Current=:(h-k){::History
        History=:(h-k){.History
        say 'marking ',mark Current
    case. 6 do.
        steps=.1 1000 number 1{::w
        seed=.1 2147483646 number 2{::w
        if. steps<0 do. fail 'invalid steps ',1{::w end.
        if. seed<0 do. fail 'invalid seed ',2{::w end.
        mode=.3{::w
        if. -.(<mode)e.'PRIORITY';'RANDOM' do. fail 'invalid mode ',mode end.
        counts=.(#TNames)$0
        done=.0
        while. done<steps do.
            es=.enabled Current
            if. 0=#es do. say 'dead (steps=',(num done),')' break. end.
            if. mode-:'RANDOM' do.
                seed=.2147483647|48271*seed
                t=.((#es)|seed){es
            else.
                priorities=.es{Priority
                t=.(priorities i.>./priorities){es
            end.
            commit t
            counts=.(>:(t{counts))t}counts
            done=.>:done
            say 'step ',(num done),': ',(t{::TNames),' -> ',mark Current
        end.
        if. done=steps do. say 'completed (steps=',(num steps),')' end.
        text=.0$a:
        for_t. i.#TNames do. text=.text,<(t{::TNames),'=',num t{counts end.
        say 'counts: ',' 'join text
    case. 7 do.
        structural=.effective=.0$a:
        for_u. i.#TNames do.
            for_v. (>:u)+i.(#TNames)->:u do.
                pair=.(u{::TNames),'/',v{::TNames
                if. +./(0<u{"1 Pre)*.0<v{"1 Pre do. structural=.structural,<pair end.
                if. (0=#Current reason u)*.0=#Current reason v do.
                    if. (0<#(Current fire u)reason v)+.0<#(Current fire v)reason u do. effective=.effective,<pair end.
                end.
            end.
        end.
        say 'structural: ',listed structural
        say 'effective: ',listed effective
    case. 8;9 do. limit reach cmd=9
    case. 10 do. cover limit
    case. 11 do.
        entries=.','split 2{::w
        if. (#entries)~:#PNames do. fail 'target needs ',(num #PNames),' entries' end.
        target=.0 2$0
        for_a. entries do.
            s=.>a
            if. s-:'*' do. target=.target,0 _1 continue. end.
            plus=.'+'={:s
            literal=.s
            if. plus do. literal=.}:s end.
            value=.0 9999999999 number literal
            if. value<0 do. fail 'invalid target entry ',s end.
            high=.value
            if. plus do. high=._1 end.
            target=.target,value,high
        end.
        g=.Current graph limit;target
        'states parent via edges found aborted'=.g
        if. found>:0 do.
            sequence=.g path found
            text=.'reached ',(mark found{::states),' length=',num #sequence
            if. #sequence do. text=.text,': ',' 'join sequence{TNames end.
            say text
        elseif. aborted do. say 'search limit ',(num limit),' exceeded'
        else. say 'unreachable (markings explored: ',(num #states),')' end.
    case. 12 do.
        rows=.,<(<''),TNames
        for_p. i.#PNames do.
            r=.,p{PNames
            for_t. i.#TNames do. r=.r,<num (<p,t){Post-Pre end.
            rows=.rows,<r
        end.
        widths=.(>:#TNames)$0
        for_r. rows do. widths=.widths>.#&> >r end.
        for_r. rows do.
            cells=.0$a:
            row=.>r
            for_i. i.#row do.
                s=.i{::row
                padding=.((i{widths)-#s)#' '
                if. i=0 do. cells=.cells,<s,padding else. cells=.cells,<padding,s end.
            end.
            say '  'join cells
        end.
    case. 13;14 do. invariants cmd=14
    case. 15;16 do.
        if. 12<#PNames do. fail 'more than 12 places' end.
        ss=.minimalSets cmd=16
        label=.'siphons'
        if. cmd=16 do. label=.'traps' end.
        say 'minimal ',label,': ',num #ss
        for_s. ss do. say '  ',(setText s),' tokens=',num +/(bits s){Current end.
    case. 17 do. classify 0
    case. 18 do. workflow limit
    case. 19 do.
        for_p. i.#PNames do.
            capacity=.'none'
            if. p{Capacity do. capacity=.num p{Capacity end.
            say 'place ',(p{::PNames),' tokens=',(num p{Initial),' capacity=',capacity
        end.
        for_t. i.#TNames do.
            lists=.0$a:
            for_matrix. Pre;Post;Inhibitor do.
                mat=.>matrix
                entries=.0$a:
                for_p. i.#PNames do.
                    weight=.(<p,t){mat
                    if. weight do. entries=.entries,<(p{::PNames),':',num weight end.
                end.
                text=.'-'
                if. #entries do. text=.','join entries end.
                lists=.lists,<text
            end.
            say 'transition ',(t{::TNames),' priority=',(num t{Priority),' pre=',(0{::lists),' post=',(1{::lists),' inhibit=',2{::lists
        end.
    end.
)
lines =: <;._2 (1!:1 <'/dev/stdin'),LF
cursor =: 0
blocks =: 0".cursor{::lines
cursor =: >:cursor
for_block. i.blocks do.
    resetNet 1{::words cursor{::lines
    cursor=:>:cursor
    while. -.('END NET')-:cursor{::lines do.
        try. define cursor{::lines catcht. say 'error: ',Reason end.
        cursor=:>:cursor
    end.
    cursor=:>:cursor
    Current=:Initial
    say 'net ',NetName,': places=',(num #PNames),' transitions=',(num #TNames),' arcs=',(num ArcCount),' inhibitors=',num InhibitorCount
    count=.0".cursor{::lines
    cursor=:>:cursor
    for_command. i.count do.
        try. command cursor{::lines catcht. say 'error: ',Reason end.
        cursor=:>:cursor
    end.
end.
