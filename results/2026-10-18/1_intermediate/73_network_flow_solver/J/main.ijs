LF =: 10{a.
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
yesno =: 3 : 'if. y do. ''yes'' else. ''no'' end.'
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
split =: 4 : 0
    result=.0$a:
    start=.0
    for_i. i.#y do.
        if. x=i{y do. result=.result,<(i-start){.start}.y
            start=.i+1 end.
    end.
    result,<start}.y
)
arcIndex =: 3 : '<:|y'
arcStart =: 4 : 'if. y>0 do. 0{(arcIndex y){x else. 1{(arcIndex y){x end.'
arcEnd =: 4 : 'if. y>0 do. 1{(arcIndex y){x else. 0{(arcIndex y){x end.'
residual =: 4 : 0
    edge=.(arcIndex y){x
    if. y>0 do. (2{edge)-5{edge else. 5{edge end.
)
arcCost =: 4 : '(*y)*3{(arcIndex y){x'
fresh =: 3 : '(4{."1 y),.((#y),2)$0'
outflow =: 4 : '+/ (5{"1 x)#~y=0{"1 x'
inflow =: 4 : '+/ (5{"1 x)#~y=1{"1 x'
flowValue =: 4 : '(x outflow y)-x inflow y'
totalCost =: 3 : '+/(3{"1 y)*5{"1 y'
makeGraph =: 4 : 0
    all=.(1+i.#y),-1+i.#y
    adjacency=.0$a:
    for_v. i.x do.
        list=.i.0
        for_a. all do. if. v=y arcStart a do. list=.list,a end. end.
        adjacency=.adjacency,<list
    end.
    (<x),(<y),(<adjacency),<all
)
bfs =: 4 : 0
    'source threshold'=.y
    'n edges arcs all'=.x
    levels=.n$_1
    parents=.n$0
    levels=.0 source}levels
    queue=.,source
    at=.0
    while. at<#queue do.
        u=.at{queue
        at=.at+1
        for_a. u{::arcs do.
            v=.edges arcEnd a
            if. ((edges residual a)>:threshold)*.0>v{levels do.
                levels=.(1+u{levels)v}levels
                parents=.a v}parents
                queue=.queue,v
            end.
        end.
    end.
    (<levels),<parents
)
tracePath =: 4 : 0
    'parents source sink'=.y
    edges=.1{::x
    path=.i.0
    v=.sink
    while. v~:source do. a=.v{parents
        path=.path,a
        v=.edges arcStart a end.
    |.path
)
bottleneck =: 4 : 0
    result=.x residual {.y
    for_a. y do. result=.result<.x residual a end.
    result
)
pushPath =: 4 : 0
    'path amount'=.y
    edges=.1{::x
    for_a. path do.
        at=.arcIndex a
        value=.(<at,5){edges
        edges=.(value+amount*(*a))(<at,5)}edges
    end.
    (<edges)1}x
)
augment =: 4 : 0
    'source sink threshold'=.y
    result=.x bfs source,threshold
    if. 0>sink{0{::result do. (<x),<(<0),(<0),(<i.0),(<threshold),<0 return. end.
    path=.x tracePath (<1{::result),(<source),<sink
    amount=.(1{::x)bottleneck path
    graph=.x pushPath (<path),<amount
    (<graph),<(<1),(<amount),(<path),(<threshold),<0
)
edmondsKarp =: 4 : 0
    graph=.x
    pushes=.0$a:
    while. 1 do.
        result=.graph augment y,1
        if. -.0{::1{::result do. (<graph),<pushes return. end.
        graph=.0{::result
        pushes=.pushes,<1{::result
    end.
)
dinic =: 4 : 0
    'source sink'=.y
    graph=.x
    phases=.0
    pushes=.0$a:
    while. 1 do.
        levels=.0{::graph bfs source,1
        if. 0>sink{levels do. (<graph),(<phases),<pushes return. end.
        phases=.phases+1
        'n edges arcs all'=.graph
        pointers=.n$0
        path=.i.0
        u=.source
        while. 1 do.
            if. u=sink do.
                amount=.(1{::graph)bottleneck path
                graph=.graph pushPath (<path),<amount
                item=.(<1),(<amount),(<path),(<phases),<0
                pushes=.pushes,<item
                path=.i.0
                u=.source
            elseif. (u{pointers)>:#u{::arcs do.
                if. u=source do. break. end.
                a=.{:path
                path=.}:path
                u=.(1{::graph)arcStart a
                pointers=.(1+u{pointers)u}pointers
            else.
                a=.(u{pointers){u{::arcs
                v=.(1{::graph)arcEnd a
                if. (((1{::graph)residual a)>0)*.(v{levels)=1+u{levels do. path=.path,a
                    u=.v
                else. pointers=.(1+u{pointers)u}pointers end.
            end.
        end.
    end.
)
scaling =: 4 : 0
    largest=.0
    for_edge. 1{::x do. largest=.largest>.2{edge end.
    threshold=.1
    while. (2*threshold)<:largest do. threshold=.2*threshold end.
    graph=.x
    pushes=.0$a:
    while. threshold>:1 do.
        while. 1 do.
            result=.graph augment y,threshold
            if. -.0{::1{::result do. break. end.
            graph=.0{::result
            pushes=.pushes,<1{::result
        end.
        threshold=.<.threshold%2
    end.
    (<graph),<pushes
)
negativeCycle =: 4 : 0
    distance=.x$0
    for_round. i.x do.
        changed=.0
        for_edge. y do.
            'u v capacity cost lower flow'=.edge
            candidate=.(u{distance)+cost
            if. candidate<v{distance do. distance=.candidate v}distance
                changed=.1 end.
        end.
        if. -.changed do. 0 return. end.
        if. (round+1)=x do. 1 return. end.
    end.
    0
)
cheapest =: 4 : 0
    'source sink'=.y
    'n edges arcs all'=.x
    usable=.i.0
    for_a. all do. if. (edges residual a)>0 do. usable=.usable,a end. end.
    distance=.n$0
    known=.n$0
    known=.1 source}known
    parents=.n$0
    while. 1 do.
        changed=.0
        for_a. usable do.
            u=.edges arcStart a
            v=.edges arcEnd a
            if. -.u{known do. continue. end.
            candidate=.(u{distance)+edges arcCost a
            if. (-.v{known)+.candidate<v{distance do.
                distance=.candidate v}distance
                known=.1 v}known
                parents=.a v}parents
                changed=.1
            end.
        end.
        if. -.changed do. break. end.
    end.
    path=.i.0
    if. sink{known do. path=.x tracePath (<parents),(<source),<sink end.
    (<sink{known),(<sink{distance),<path
)
minimumCost =: 4 : 0
    'source sink target'=.y
    graph=.x
    flow=.cost=.0
    pushes=.0$a:
    while. (target<0)+.flow<target do.
        result=.graph cheapest source,sink
        if. -.0{::result do. break. end.
        unit=.1{::result
        path=.2{::result
        amount=.(1{::graph)bottleneck path
        if. target>:0 do. amount=.amount<.target-flow end.
        graph=.graph pushPath (<path),<amount
        flow=.flow+amount
        cost=.cost+amount*unit
        pushes=.pushes,<(<1),(<amount),(<path),(<0),<unit
    end.
    (<graph),(<flow),(<cost),<pushes
)
maximumAmount =: 3 : 0
    'n edges source sink'=.y
    result=.(n makeGraph edges)edmondsKarp source,sink
    (1{::0{::result)flowValue source
)
decompose =: 4 : 0
    remaining=.5{"1 y
    balance=.i.0
    for_v. i.x do. balance=.balance,y flowValue v end.
    pieces=.0$a:
    while. +./remaining>0 do.
        positive=.I.balance>0
        if. #positive do. origin=.{.positive else. origin=.0{({.I.remaining>0){y end.
        walk=.,origin
        used=.i.0
        while. 1 do.
            u=.{:walk
            at=.{.I.((0{"1 y)=u)*.remaining>0
            v=.1{at{y
            used=.used,at
            repeated=.walk i.v
            if. repeated<#walk do.
                selected=.repeated}.used
                amount=.<./selected{remaining
                remaining=.(amount-~selected{remaining)selected}remaining
                pieces=.pieces,<(<1),(<v),(<selected),<amount
                break.
            end.
            walk=.walk,v
            if. 0>v{balance do.
                amount=.(<./used{remaining)<.(origin{balance)<.-v{balance
                remaining=.(amount-~used{remaining)used}remaining
                balance=.((origin{balance)-amount)origin}balance
                balance=.((v{balance)+amount)v}balance
                pieces=.pieces,<(<0),(<origin),(<used),<amount
                break.
            end.
        end.
    end.
    pieces
)
notation =: 3 : 0
    'names edges origin path'=.y
    words=.,<origin{::names
    for_a. path do.
        sign=.'+'
        if. a<0 do. sign=.'-' end.
        words=.words,<(sign,num 1+arcIndex a)
        words=.words,<(edges arcEnd a){::names
    end.
    ' 'join words
)
nodeIndex =: 3 : 0
    at=.Names i.<y
    ('UNKNOWN NODE ',y)check at<#Names
    at
)
edgeIndex =: 3 : 0
    at=.0".y
    ('UNKNOWN EDGE ',y)check (at>:1)*.at<:#Edges
    at-1
)
endpoints =: 3 : 0
    source=.nodeIndex 0{::y
    sink=.nodeIndex 1{::y
    'SAME NODE'check source~:sink
    source,sink
)
startFlow =: 3 : 0
    'source sink'=.y
    if. (-.Owner-:'flow')+.(Source~:source)+.Sink~:sink do.
        for_i. i.#Edges do. Edges=:0 (<i,5)}Edges end.
    end.
    Owner=:'flow'
    Source=:source
    Sink=:sink
    Edges flowValue source
)
flowList =: 3 : 0
    for_i. i.#Edges do.
        'u v capacity cost lower flow'=.i{Edges
        emit 'FLOW ',(num i+1),' ',(u{::Names),' ',(v{::Names),' ',(num flow),'/',num capacity
    end.
)
tryLeft =: 3 : 0
    for_link. MatchLinks do.
        'a b'=.link
        if. (a~:y)+.b{Examined do. continue. end.
        Examined=:1 b}Examined
        partner=.b{RightPartner
        success=.partner<0
        if. -.success do. success=.tryLeft partner end.
        if. success do. RightPartner=:y b}RightPartner
            LeftPartner=:b y}LeftPartner
            1 return. end.
    end.
    0
)
matchingReport =: 3 : 0
    left=.','split 0{::y
    right=.','split 1{::y
    seen=.0$a:
    for_name. left,right do.
        ('DUPLICATE VERTEX ',>name)check -.name e.seen
        seen=.seen,name
    end.
    links=.0 2$0
    if. '-'-:2{::y do. pairs=.0$a: else. pairs=.','split 2{::y end.
    for_pair. pairs do.
        names=.'-'split >pair
        a=.left i.0{names
        b=.right i.1{names
        ('UNKNOWN VERTEX ',0{::names)check a<#left
        ('UNKNOWN VERTEX ',1{::names)check b<#right
        ('DUPLICATE PAIR ',>pair)check -.(<a,b)e.<"1 links
        links=.links,a,b
    end.
    MatchLinks=:links
    LeftPartner=:(#left)$_1
    RightPartner=:(#right)$_1
    for_a. i.#left do. Examined=:(#right)$0
        found=.tryLeft a end.
    lin=.LeftPartner<0
    rin=.(#right)$0
    while. 1 do.
        changed=.0
        for_link. links do. 'a b'=.link
            if. (a{lin)*.(-.b{rin)*.b~:a{LeftPartner do. rin=.1 b}rin
                changed=.1 end.
        end.
        for_b. i.#right do.
            partner=.b{RightPartner
            if. (b{rin)*.partner>:0 do.
                if. -.partner{lin do. lin=.1 partner}lin
                    changed=.1 end.
            end.
        end.
        if. -.changed do. break. end.
    end.
    freeleft=.left#~LeftPartner<0
    freeright=.right#~RightPartner<0
    cover=.(left#~-.lin),right#~rin
    emit 'MATCH size=',(num +/LeftPartner>:0),' left=',(num #left),' right=',num #right
    for_a. i.#left do.
        if. (a{LeftPartner)>:0 do. emit 'PAIR ',(a{::left),' ',(a{LeftPartner){::right end.
    end.
    ltext=.','join freeleft
    rtext=.','join freeright
    if. 0=#freeleft do. ltext=.'-' end.
    if. 0=#freeright do. rtext=.'-' end.
    emit 'FREE ',ltext,' ',rtext
    text=.'COVER size=',num #cover
    if. #cover do. text=.text,' ',' 'join cover end.
    emit text
    if. #freeleft do.
        rtext=.','join right#~rin
        if. -. +./rin do. rtext=.'-' end.
        emit 'HALL ',(','join left#~lin),' ',rtext
    end.
)
assignmentSearch =: 3 : 0
    'columns total'=.y
    row=.#columns
    if. row=AssignSize do.
        better=.total<AssignBest
        if. AssignMax do. better=.total>AssignBest end.
        if. (-.AssignFound)+.better do. AssignFound=:1
            AssignBest=:total
            AssignWays=:1
            AssignChosen=:columns
        elseif. total=AssignBest do. AssignWays=:AssignWays+1 end.
        return.
    end.
    for_col. i.AssignSize do.
        if. col e.columns do. continue. end.
        value=.((row*AssignSize)+col){::AssignValues
        if. value-:'x' do. continue. end.
        assignmentSearch (<columns,col),<total+0".value
    end.
)
assignmentReport =: 3 : 0
    mode=.0{::y
    n=.0".1{::y
    'BAD SIZE'check (n>:1)*.n<:8
    'BAD LENGTH'check (n*n)=#2}.y
    AssignSize=:n
    AssignValues=:2}.y
    AssignMax=:mode-:'MAX'
    AssignFound=:AssignBest=:AssignWays=:0
    AssignChosen=:i.0
    assignmentSearch (<i.0),<0
    if. -.AssignFound do. emit 'ASSIGN ',mode,' n=',(num n),' infeasible' return. end.
    emit 'ASSIGN ',mode,' n=',(num n),' total=',(num AssignBest),' optimal=',num AssignWays
    for_row. i.n do. col=.row{AssignChosen
        emit 'MATE ',(num row+1),' ',(num col+1),' ',((n*row)+col){::AssignValues end.
)
execute =: 3 : 0
    words=.' 'split y
    command=.0{::words
    args=.}.words
    select. command
    case. 'NODE' do.
        seen=.Names
        for_name. args do. ('DUPLICATE NODE ',>name)check -.name e.seen
            seen=.seen,name end.
        'TOO MANY NODES'check (#seen)<:20
        Names=:seen
        Demands=:Demands,(#args)$0
        emit 'NODE added=',(num #args),' total=',num #Names
    case. 'EDGE' do.
        u=.nodeIndex 0{::args
        v=.nodeIndex 1{::args
        'SELF LOOP'check u~:v
        'TOO MANY EDGES'check (#Edges)<60
        capacity=.0".2{::args
        cost=.0
        if. 4=#args do. cost=.0".3{::args end.
        Edges=:Edges,u,v,capacity,cost,0 0
        emit 'EDGE ',(num #Edges),' ',(0{::args),' ',(1{::args),' cap=',(num capacity),' cost=',num cost
    case. 'LOWER';'CAP';'COST' do.
        at=.edgeIndex 0{::args
        value=.0".1{::args
        edge=.at{Edges
        if. command-:'LOWER' do.
            'BAD BOUND'check value<:2{edge
            Edges=:value (<at,4)}Edges
            emit 'LOWER ',(num at+1),' low=',(num value),' cap=',num 2{edge
        elseif. command-:'CAP' do.
            'BAD BOUND'check value>:4{edge
            'BELOW FLOW'check value>:5{edge
            Edges=:value (<at,2)}Edges
            emit 'CAP ',(num at+1),' low=',(num 4{edge),' cap=',num value
        else. Edges=:value (<at,3)}Edges
            emit 'COST ',(num at+1),' cost=',num value end.
    case. 'DEMAND' do.
        at=.nodeIndex 0{::args
        value=.0".1{::args
        Demands=:value at}Demands
        emit 'DEMAND ',(0{::args),' ',(num value),' total=',num +/Demands
    case. 'RESET' do.
        emit 'RESET edges=',num +/0~:5{"1 Edges
        for_i. i.#Edges do. Edges=:0 (<i,5)}Edges end.
        Owner=:'none'
    case. 'CLEAR' do.
        emit 'CLEAR nodes=',(num #Names),' edges=',num #Edges
        Names=:0$a:
        Demands=:i.0
        Edges=:0 6$0
        Owner=:'none'
        Source=:Sink=:0
    case. 'SHOW' do.
        emit 'NETWORK nodes=',(num #Names),' edges=',num #Edges
        if. Owner-:'none' do. emit 'STATE none'
        elseif. Owner-:'circulation' do. emit 'STATE circulation cost=',num totalCost Edges
        else. emit 'STATE flow ',(Source{::Names),' ',(Sink{::Names),' value=',(num Edges flowValue Source),' cost=',num totalCost Edges end.
        for_v. i.#Names do. emit 'NODE ',(v{::Names),' demand=',(num v{Demands),' out=',(num Edges outflow v),' in=',num Edges inflow v end.
        for_i. i.#Edges do. 'u v capacity cost lower flow'=.i{Edges
            emit 'EDGE ',(num i+1),' ',(u{::Names),' ',(v{::Names),' cap=',(num capacity),' cost=',(num cost),' low=',(num lower),' flow=',num flow end.
    case. 'AUGMENT';'MAXFLOW';'DINIC';'SCALING';'MINCUT' do.
        'source sink'=.endpoints args
        start=.startFlow source,sink
        graph=.(#Names)makeGraph Edges
        heading=.command,' ',(0{::args),' ',1{::args
        if. command-:'AUGMENT' do.
            result=.graph augment source,sink,1
            Edges=:1{::0{::result
            item=.1{::result
            text=.heading,' value=',num Edges flowValue source
            if. 0{::item do. text=.text,' amount=',(num 1{::item),' ',notation (<Names),(<Edges),(<source),<2{::item
            else. text=.text,' none' end.
            emit text return.
        end.
        phases=.0
        if. command-:'DINIC' do. result=.graph dinic source,sink
            phases=.1{::result
            pushes=.2{::result
        elseif. command-:'SCALING' do. result=.graph scaling source,sink
            pushes=.1{::result
        else. result=.graph edmondsKarp source,sink
            pushes=.1{::result end.
        graph=.0{::result
        Edges=:1{::graph
        if. command-:'MINCUT' do.
            levels=.0{::graph bfs source,1
            inside=.levels>:0
            cut=.I.((0{"1 Edges){inside)*.-.(1{"1 Edges){inside
            emit heading,' value=',(num Edges flowValue source),' edges=',num #cut
            emit 'SOURCE ',' 'join inside#Names
            emit 'SINK ',' 'join (-.inside)#Names
            for_i. cut do. edge=.i{Edges
                emit 'CUT ',(num i+1),' ',((0{edge){::Names),' ',((1{edge){::Names),' ',num 2{edge end.
        else.
            text=.heading,' value=',(num Edges flowValue source),' start=',num start
            if. command-:'DINIC' do. text=.text,' phases=',num phases end.
            emit text,' paths=',num #pushes
            for_i. i.#pushes do.
                item=.i{::pushes
                detail=.''
                if. command-:'DINIC' do. detail=.' phase=',num 3{::item
                elseif. command-:'SCALING' do. detail=.' delta=',num 3{::item end.
                emit 'AUG ',(num i+1),detail,' amount=',(num 1{::item),' ',notation (<Names),(<Edges),(<source),<2{::item
            end.
            flowList''
        end.
    case. 'SENSITIVITY' do.
        'source sink'=.endpoints args
        value=.maximumAmount (<#Names),(<fresh Edges),(<source),<sink
        ups=.downs=.i.0
        for_i. i.#Edges do.
            work=.fresh Edges
            work=.(1+(<i,2){work)(<i,2)}work
            up=.(maximumAmount (<#Names),(<work),(<source),<sink)>value
            down=.0
            if. (<i,2){Edges do.
                work=.fresh Edges
                work=.(<:(<i,2){work)(<i,2)}work
                down=.(maximumAmount (<#Names),(<work),(<source),<sink)<value
            end.
            ups=.ups,up
            downs=.downs,down
        end.
        emit 'SENSITIVITY ',(0{::args),' ',(1{::args),' value=',(num value),' up=',(num +/ups),' down=',num +/downs
        for_i. I.ups+.downs do. edge=.i{Edges
            emit 'CRITICAL ',(num i+1),' ',((0{edge){::Names),' ',((1{edge){::Names),' up=',(yesno i{ups),' down=',yesno i{downs end.
    case. 'MINCOST' do.
        'source sink'=.endpoints args
        'NEGATIVE CYCLE'check -. (#Names)negativeCycle Edges#~0<2{"1 Edges
        target=._1
        if. -. 'MAX'-:2{::args do. target=.0".2{::args end.
        result=.((#Names)makeGraph fresh Edges)minimumCost source,sink,target
        flow=.1{::result
        cost=.2{::result
        heading=.'MINCOST ',(0{::args),' ',(1{::args),' k=',2{::args
        if. (target>:0)*.flow<target do. emit heading,' infeasible max=',num flow return. end.
        work=.1{::0{::result
        for_i. i.#Edges do. Edges=:((<i,5){work)(<i,5)}Edges end.
        Owner=:'flow'
        Source=:source
        Sink=:sink
        emit heading,' flow=',(num flow),' cost=',num cost
        pushes=.3{::result
        for_i. i.#pushes do. item=.i{::pushes
            emit 'AUG ',(num i+1),' amount=',(num 1{::item),' cost=',(num 4{::item),' ',notation (<Names),(<Edges),(<source),<2{::item end.
        flowList''
    case. 'DISJOINT' do.
        'source sink'=.endpoints args
        exits=.i.#Names
        n=.#Names
        vertex=.'VERTEX'-:2{::args
        if. vertex do.
            n=.2*n
            for_v. i.#Names do. if. (v~:source)*.v~:sink do. exits=.((#Names)+v)v}exits end. end.
        end.
        work=.0 6$0
        for_edge. Edges do. 'u v capacity cost lower flow'=.edge
            work=.work,(u{exits),v,(capacity>0),0 0 0 end.
        if. vertex do. for_v. i.#Names do.
            if. (v~:source)*.v~:sink do. work=.work,v,(v{exits),1 0 0 0 end.
        end. end.
        result=.(n makeGraph work)edmondsKarp source,sink
        work=.1{::0{::result
        pieces=.n decompose work
        paths=.0$a:
        for_piece. pieces do. if. -.0{::>piece do. paths=.paths,piece end. end.
        emit 'DISJOINT ',(0{::args),' ',(1{::args),' ',(2{::args),' count=',num #paths
        for_i. i.#paths do.
            piece=.i{::paths
            selected=.2{::piece
            selected=.selected#~selected<#Edges
            emit 'PATH ',(num i+1),' ',notation (<Names),(<Edges),(<1{::piece),<1+selected
        end.
    case. 'DECOMPOSE' do.
        pieces=.(#Names)decompose Edges
        cycles=.0
        for_piece. pieces do. cycles=.cycles+0{::>piece end.
        emit 'DECOMPOSE paths=',(num (#pieces)-cycles),' cycles=',num cycles
        p=.c=.0
        for_piece. pieces do.
            piece=.>piece
            if. 0{::piece do. c=.c+1
                title=.'CYCLE ',num c
            else. p=.p+1
                title=.'PATH ',num p end.
            emit title,' amount=',(num 3{::piece),' ',notation (<Names),(<Edges),(<1{::piece),<1+2{::piece
        end.
    case. 'VERIFY' do.
        violations=.0$a:
        for_i. i.#Edges do. 'u v capacity cost lower flow'=.i{Edges
            if. flow<lower do. violations=.violations,<'LOW ',(num i+1),' flow=',(num flow),' low=',num lower end.
        end.
        for_v. i.#Names do.
            if. (Owner-:'flow')*.v e.Source,Sink do. continue. end.
            need=.v{Demands
            if. Owner-:'flow' do. need=.0 end.
            net=.(Edges inflow v)-Edges outflow v
            if. net~:need do. violations=.violations,<'BALANCE ',(v{::Names),' net=',(num net),' need=',num need end.
        end.
        if. #violations do. emit 'VERIFY violations=',num #violations
            emit&>violations
        else. emit 'VERIFY ok' end.
    case. 'CIRCULATION' do.
        mode=.0{::args
        n=.#Names
        if. mode-:'MINCOST' do. 'NEGATIVE CYCLE'check -.n negativeCycle Edges#~(2{"1 Edges)>4{"1 Edges end.
        imbalance=.+/Demands
        if. imbalance~:0 do. emit 'CIRCULATION infeasible unbalanced=',num imbalance return. end.
        required=.Demands
        work=.0 6$0
        for_edge. Edges do.
            'u v capacity cost lower flow'=.edge
            required=.((v{required)-lower)v}required
            required=.((u{required)+lower)u}required
            work=.work,u,v,(capacity-lower),cost,0 0
        end.
        for_v. i.n do. if. (v{required)<0 do. work=.work,n,v,(-v{required),0 0 0 end. end.
        sinkedges=.i.0
        for_v. i.n do.
            if. (v{required)>0 do. sinkedges=.sinkedges,#work
                work=.work,v,(n+1),(v{required),0 0 0 end.
        end.
        graph=.(n+2)makeGraph work
        if. mode-:'ANY' do. result=.graph edmondsKarp n,n+1 else. result=.graph minimumCost n,(n+1),_1 end.
        graph=.0{::result
        work=.1{::graph
        total=.+/sinkedges{2{"1 work
        achieved=.+/sinkedges{5{"1 work
        if. achieved<total do.
            emit 'CIRCULATION infeasible required=',(num total),' achieved=',num achieved
            levels=.0{::graph bfs n,1
            emit 'CUT ',' 'join Names#~(i.n){levels>:0 return.
        end.
        for_i. i.#Edges do. value=.((<i,4){Edges)+(<i,5){work
            Edges=:value (<i,5)}Edges end.
        Owner=:'circulation'
        emit 'CIRCULATION feasible required=',(num total),' cost=',num totalCost Edges
        flowList''
    case. 'MATCH' do. matchingReport args
    case. 'ASSIGN' do. assignmentReport args
    end.
)
main =: 3 : 0
    Names=:0$a:
    Demands=:i.0
    Edges=:0 6$0
    Owner=:'none'
    Source=:Sink=:0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        Output=:0$a:
        try. execute (i+1){::lines
        catcht. Output=:,<'ERROR ',Reason end.
        if. #Output do. 1!:2&2 ;Output,&.><LF end.
    end.
)
main''
