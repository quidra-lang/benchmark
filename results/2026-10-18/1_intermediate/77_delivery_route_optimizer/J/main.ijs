LF =: 10{a.
num =: 3 : ',''0'' 8!:2 y'
say =: 3 : '1!:2&2 y,LF'
join =: 4 : '(#x)}.;(<x),&.>y'
fail =: 3 : 0
    Reason=:y
    throw.
)
check =: 4 : 'if. -.y do. fail x end.'
lpad =: 4 : '((0>.x-#y)#'' ''),y'
zpad =: 4 : '(-x){.(x#''0''),num y'
parseTime =: 3 : '(60*0".2{.y)+0".3}.y'
timeText =: 3 : 0
    hours=.num <.y%60
    if. 1=#hours do. hours=.'0',hours end.
    hours,':',2 zpad 60|y
)
placeName =: 3 : 'if. y=0 do. ''D'' else. num y end.'
notation =: 3 : 0
    '-'join (<'D'),(num&.>y),<'D'
)
words =: 3 : '(<;._1 '' '',y)-.<'''''

boundary =: 4 : 'if. (y=0)+.y>#x do. 0 else. (y-1){x end.'
tenths =: 3 : '(num <.y%10),''.'',num 10|y'
stopIds =: 3 : '/:~IDs'
getStop =: 3 : '(IDs i.y){Stops'
coordinates =: 3 : 'if. y=0 do. Depot else. 2{.getStop y end.'
distance =: 4 : '+/|(coordinates x)-coordinates y'
pathLength =: 3 : 0
    around=.0,y,0
    result=.0
    for_i. i.<:#around do. result=.result+(i{around)distance (i+1){around end.
    result
)
pathLoad =: 3 : 0
    result=.0
    for_id. y do. result=.result+2{getStop id end.
    result
)
planLength =: 3 : '+/pathLength&>Routes'
normalize =: 3 : 0
    result=.0$a:
    smallest=.i.0
    for_path. Routes do.
        path=.>path
        if. 0=#path do. continue. end.
        if. ({.path)>{:path do. path=.|.path end.
        result=.result,<path
        smallest=.smallest,<./path
    end.
    Routes=:result{~/:smallest
)
requireDepot =: 3 : '''no depot''check DepotSet'
requireStops =: 3 : '''no stops''check 0<#IDs'
requireTour =: 3 : '''no tour''check TourSet'
requirePlan =: 3 : '''no plan''check PlanSet'
requireCapacity =: 3 : 0
    for_id. stopIds'' do.
        demand=.2{getStop id
        ('stop ',(num id),' demand ',(num demand),' exceeds capacity ',num y)check demand<:y
    end.
)
installTour =: 4 : 0
    Tour=:y
    TourSet=:1
    say x,': ',(notation y),' length ',num pathLength y
)
planReport =: 3 : 0
    say y,', routes ',(num #Routes),', length ',num planLength''
    for_r. i.#Routes do.
        path=.r{::Routes
        say 'route ',(num r+1),': ',(notation path),' load ',(num pathLoad path),' length ',num pathLength path
    end.
)
simulate =: 3 : 0
    visits=.0 6$0
    timestamp=.Start
    previous=.0
    waiting=.service=.violations=.lateness=.0
    for_id. y do.
        'sx sy demand work opening closing'=.getStop id
        arrival=.timestamp+previous distance id
        wait=.0>.opening-arrival
        late=.0
        if. closing>:0 do. late=.0>.arrival-closing end.
        beginning=.arrival+wait
        timestamp=.beginning+work
        visits=.visits,id,arrival,wait,beginning,timestamp,late
        waiting=.waiting+wait
        service=.service+work
        violations=.violations+late>0
        lateness=.lateness+late
        previous=.id
    end.
    (<visits),<(timestamp+previous distance 0),(pathLength y),waiting,service,violations,lateness
)
firstReversal =: 3 : 0
    for_i. i.#y do.
        for_j. (i+1)+i.(#y)-i+1 do.
            gain=.((y boundary i)distance i{y)+((j{y)distance y boundary j+2)-((y boundary i)distance j{y)+(i{y)distance y boundary j+2
            if. gain>0 do. i,j,gain return. end.
        end.
    end.
    i.0
)
twoOpt =: 4 : 0
    path=.y
    moves=.0
    while. 1 do.
        change=.firstReversal path
        if. 0=#change do. break. end.
        'i j gain'=.change
        if. x do. say 'reverse ',(num i{path),'..',(num j{path),' gain ',num gain end.
        path=.(i{.path),(|.(1+j-i){.i}.path),(j+1)}.path
        moves=.moves+1
    end.
    (<path),<moves
)
firstSegment =: 3 : 0
    n=.#y
    for_size. 1 2 3 do.
        if. size>n do. continue. end.
        for_i. i.1+n-size do.
            rest=.(i{.y),(i+size)}.y
            first=.i{y
            last=.(i+size-1){y
            before=.y boundary i
            after=.y boundary i+size+1
            removal=.(before distance first)+(last distance after)-before distance after
            for_j. i.1+#rest do.
                if. j=i do. continue. end.
                a=.rest boundary j
                b=.rest boundary j+1
                gain=.removal-(a distance first)+(last distance b)-a distance b
                if. gain>0 do. i,size,j,gain return. end.
            end.
        end.
    end.
    i.0
)
firstSwap =: 3 : 0
    before=.pathLength y
    for_i. i.#y do.
        for_j. (i+1)+i.(#y)-i+1 do.
            changed=.(j{y)i}y
            changed=.(i{y)j}changed
            gain=.before-pathLength changed
            if. gain>0 do. i,j,gain return. end.
        end.
    end.
    i.0
)
exactTour =: 3 : 0
    ids=.stopIds''
    n=.#ids
    powers=.2^i.n
    states=.2^n
    full=.states-1
    costs=.(states*n)$0
    for_i. i.n do. costs=.((i{ids)distance 0)i}costs end.
    for_mask. 1+i.full-1 do.
        for_i. i.n do.
            if. 2|<.mask%i{powers do. continue. end.
            found=.0
            best=.0
            for_j. i.n do.
                if. 2|<.mask%j{powers do.
                    value=.((i{ids)distance j{ids)+((n*mask-j{powers)+j){costs
                    if. (-.found)+.value<best do. best=.value
                        found=.1 end.
                end.
            end.
            costs=.best((n*mask)+i)}costs
        end.
    end.
    values=.i.0
    for_i. i.n do. values=.values,(0 distance i{ids)+((n*full-i{powers)+i){costs end.
    cost=.<./values
    current=.0
    mask=.full
    path=.i.0
    while. mask>0 do.
        for_i. i.n do.
            if. 2|<.mask%i{powers do.
                rest=.mask-i{powers
                if. cost=(current distance i{ids)+((n*rest)+i){costs do.
                    mask=.rest
                    cost=.((n*mask)+i){costs
                    current=.i{ids
                    path=.path,current
                    break.
                end.
            end.
        end.
    end.
    path
)
spanningTree =: 3 : 0
    tree=.1{.y
    remaining=.}.y
    edges=.0$a:
    while. #remaining do.
        best=.i.0
        for_child. remaining do.
            for_parent. tree do.
                weight=.parent distance child
                if. 0=#best do. best=.parent,child,weight
                elseif. weight<2{best do. best=.parent,child,weight end.
            end.
        end.
        edges=.edges,<best
        tree=.tree,1{best
        remaining=.remaining-.1{best
    end.
    edges
)
sweepLess =: 4 : 0
    'a b'=.(coordinates x)-Depot
    'c d'=.(coordinates y)-Depot
    az=.(a=0)*.b=0
    bz=.(c=0)*.d=0
    if. az~:bz do. az return. end.
    if. az do. x<y return. end.
    ah=.(b>0)+.(b=0)*.a>0
    bh=.(d>0)+.(d=0)*.c>0
    if. ah~:bh do. ah return. end.
    cross=.(a*d)-b*c
    if. cross~:0 do. cross>0 return. end.
    da=.(|a)+|b
    db=.(|c)+|d
    if. da~:db do. da<db else. x<y end.
)
sweepOrder =: 3 : 0
    result=.i.0
    for_id. stopIds'' do.
        at=.0
        while. at<#result do.
            if. id sweepLess at{result do. break. end.
            at=.at+1
        end.
        result=.(at{.result),id,at}.result
    end.
    result
)
savings =: 4 : 0
    q=.x
    limit=.y
    ids=.stopIds''
    if. limit>:0 do.
        for_id. ids do. ('stop ',(num id),' too far for limit ',num limit)check (2*0 distance id)<:limit end.
    end.
    pairs=.0 3$0
    for_i. i.#ids do.
        a=.i{ids
        for_b. (i+1)}.ids do.
            value=.(0 distance a)+(0 distance b)-a distance b
            if. value>0 do. pairs=.pairs,(-value),a,b end.
        end.
    end.
    pairs=./:~pairs
    paths=.0$a:
    for_id. ids do. paths=.paths,<,id end.
    merges=.0
    for_pair. pairs do.
        'negative a b'=.pair
        r=.t=.0
        for_i. i.#paths do.
            if. a e.i{::paths do. r=.i end.
            if. b e.i{::paths do. t=.i end.
        end.
        if. r=t do. continue. end.
        first=.r{::paths
        second=.t{::paths
        if. (-.a e.({.first),{:first)+.-.b e.({.second),{:second do. continue. end.
        if. q<(pathLoad first)+pathLoad second do. continue. end.
        if. a={.first do. first=.|.first end.
        if. b={:second do. second=.|.second end.
        merged=.first,second
        if. limit>:0 do. if. (pathLength merged)>limit do. continue. end. end.
        mask=.((i.#paths)~:r)*.(i.#paths)~:t
        paths=.(mask#paths),<merged
        merges=.merges+1
    end.
    Capacity=:q
    Routes=:paths
    PlanSet=:1
    normalize''
    planReport 'vrp: capacity ',(num q),', merges ',num merges
)
splitPlan =: 3 : 0
    n=.#Tour
    best=.(n+1)$0
    previous=.(n+1)$0
    for_j. 1+i.n do.
        found=.0
        for_i. i.j do.
            segment=.(j-i){.i}.Tour
            if. (pathLoad segment)>y do. continue. end.
            value=.(i{best)+pathLength segment
            if. (-.found)+.value<j{best do.
                best=.value j}best
                previous=.i j}previous
                found=.1
            end.
        end.
    end.
    paths=.0$a:
    at=.n
    while. at>0 do.
        start=.at{previous
        paths=.paths,<(at-start){.start}.Tour
        at=.start
    end.
    Capacity=:y
    Routes=:paths
    PlanSet=:1
    normalize''
    planReport 'split: capacity ',num y
)
firstRelocation =: 3 : 0
    for_r. i.#Routes do.
        source=.r{::Routes
        for_p. i.#source do.
            id=.p{source
            a=.source boundary p
            b=.source boundary p+2
            removal=.(a distance id)+(id distance b)-a distance b
            for_t. i.#Routes do.
                if. t=r do. continue. end.
                target=.t{::Routes
                if. Capacity<(pathLoad target)+2{getStop id do. continue. end.
                for_j. i.1+#target do.
                    a=.target boundary j
                    b=.target boundary j+1
                    gain=.removal-(a distance id)+(id distance b)-a distance b
                    if. gain>0 do. r,p,t,j,gain return. end.
                end.
            end.
        end.
    end.
    i.0
)
firstExchange =: 3 : 0
    for_r. i.#Routes do.
        a=.r{::Routes
        for_t. (r+1)+i.(#Routes)-r+1 do.
            b=.t{::Routes
            total=.(pathLength a)+pathLength b
            for_p. i.#a do.
                for_j. i.#b do.
                    shift=.(2{getStop j{b)-2{getStop p{a
                    if. (((pathLoad a)+shift)>Capacity)+.((pathLoad b)-shift)>Capacity do. continue. end.
                    first=.(j{b)p}a
                    second=.(p{a)j}b
                    gain=.total-(pathLength first)+pathLength second
                    if. gain>0 do. r,p,t,j,gain return. end.
                end.
            end.
        end.
    end.
    i.0
)
firstCross =: 3 : 0
    for_r. i.#Routes do.
        a=.r{::Routes
        for_t. (r+1)+i.(#Routes)-r+1 do.
            b=.t{::Routes
            for_i. i.1+#a do.
                for_j. i.1+#b do.
                    first=.(i{.a),j}.b
                    second=.(j{.b),i}.a
                    if. ((pathLoad first)>Capacity)+.(pathLoad second)>Capacity do. continue. end.
                    aa=.a boundary i
                    ab=.a boundary i+1
                    ba=.b boundary j
                    bb=.b boundary j+1
                    gain=.(aa distance ab)+(ba distance bb)-(aa distance bb)+ba distance ab
                    if. gain>0 do. r,i,t,j,gain return. end.
                end.
            end.
        end.
    end.
    i.0
)
improvePlan =: 3 : 0
    before=.planLength''
    countbefore=.#Routes
    moves=.0
    while. 1 do.
        if. y-:'RELOCATE' do. change=.firstRelocation''
        elseif. y-:'EXCHANGE' do. change=.firstExchange''
        else. change=.firstCross'' end.
        if. 0=#change do. break. end.
        'r p t j gain'=.change
        a=.r{::Routes
        b=.t{::Routes
        if. y-:'RELOCATE' do.
            id=.p{a
            say 'relocate ',(num id),' from route ',(num r+1),' to route ',(num t+1),' after ',(placeName b boundary j),' gain ',num gain
            first=.(p{.a),(p+1)}.a
            second=.(j{.b),id,j}.b
        elseif. y-:'EXCHANGE' do.
            say 'exchange ',(num p{a),' (route ',(num r+1),') with ',(num j{b),' (route ',(num t+1),') gain ',num gain
            first=.(j{b)p}a
            second=.(p{a)j}b
        else.
            say 'cross route ',(num r+1),' after ',(placeName a boundary p),' with route ',(num t+1),' after ',(placeName b boundary j),' gain ',num gain
            first=.(p{.a),j}.b
            second=.(j{.b),p}.a
        end.
        Routes=:(<first)r}Routes
        Routes=:(<second)t}Routes
        normalize''
        moves=.moves+1
    end.
    counts=.''
    if. -.y-:'EXCHANGE' do. counts=.'routes ',(num countbefore),' -> ',(num #Routes),', ' end.
    heading=.('relocate';'exchange';'cross'){::~(;:'RELOCATE EXCHANGE CROSS')i.<y
    say heading,': moves ',(num moves),', ',counts,'length ',(num before),' -> ',num planLength''
)
execute =: 3 : 0
    parts=.words y
    command=.0{::parts
    args=.}.parts
    select. command
    case. 'DEPOT' do. Depot=:0".&>args
        DepotSet=:1
        say 'depot at (',(num 0{Depot),',',(num 1{Depot),')'
    case. 'START' do. Start=:parseTime 0{::args
        say 'start ',timeText Start
    case. 'STOP' do.
        id=.0".0{::args
        ('stop ',(num id),' already exists')check -.id e.IDs
        values=.0".&>5{.args
        opening=.closing=._1
        if. 7=#args do.
            opening=.parseTime 5{::args
            closing=.parseTime 6{::args
            'invalid window'check opening<:closing
        end.
        IDs=:IDs,id
        Stops=:Stops,(}.values),opening,closing
        TourSet=:PlanSet=:0
        say 'stop ',(num id),' added'
    case. 'REMOVE' do.
        id=.0".0{::args
        ('unknown stop ',num id)check id e.IDs
        mask=.IDs~:id
        IDs=:mask#IDs
        Stops=:mask#Stops
        if. TourSet do. Tour=:Tour-.id end.
        if. PlanSet do.
            paths=.0$a:
            for_path. Routes do. paths=.paths,< (>path)-.id end.
            Routes=:paths
            normalize''
        end.
        if. 0=#IDs do. TourSet=:PlanSet=:0 end.
        say 'stop ',(num id),' removed'
    case. 'LIST' do.
        if. DepotSet do. say 'depot (',(num 0{Depot),',',(num 1{Depot),')' else. say 'depot none' end.
        say 'start ',timeText Start
        say 'stops ',num #IDs
        for_id. stopIds'' do.
            'x y demand service opening closing'=.getStop id
            window=.'none'
            if. opening>:0 do. window=.(timeText opening),'-',timeText closing end.
            say (num id),' at (',(num x),',',(num y),') demand ',(num demand),' service ',(num service),' window ',window
        end.
    case. 'MATRIX' do.
        requireDepot''
        ids=.0,stopIds''
        header=.placeName&.>ids
        table=.,<( <''),header
        for_id. ids do.
            row=.,<placeName id
            for_other. ids do. row=.row,<num id distance other end.
            table=.table,<row
        end.
        width=.0
        for_row. table do. width=.width>.>./#&> >row end.
        for_row. table do.
            cells=.0$a:
            for_cell. >row do. cells=.cells,<width lpad >cell end.
            say ' 'join cells
        end.
    case. 'ORDER';'NEAREST';'INSERTION';'EXACT';'BOUND';'VRP';'SWEEP' do.
        requireDepot''
        requireStops''
        ids=.stopIds''
        select. command
        case. 'ORDER' do.
            path=.0".&>args
            for_id. path do. ('unknown stop ',num id)check id e.IDs end.
            seen=.i.0
            for_id. path do. ('duplicate stop ',num id)check -.id e.seen
                seen=.seen,id end.
            ('order has ',(num #path),' stops, expected ',num #IDs)check (#path)=#IDs
            'order'installTour path
        case. 'NEAREST' do.
            remaining=.ids
            path=.i.0
            current=.0
            while. #remaining do.
                chosen=.{.remaining
                for_id. remaining do. if. (current distance id)<current distance chosen do. chosen=.id end. end.
                path=.path,chosen
                remaining=.remaining-.chosen
                current=.chosen
            end.
            'nearest'installTour path
        case. 'INSERTION' do.
            remaining=.ids
            path=.i.0
            while. #remaining do.
                best=.i.0
                for_id. remaining do.
                    for_j. i.1+#path do.
                        a=.path boundary j
                        b=.path boundary j+1
                        value=.(a distance id)+(id distance b)-a distance b
                        if. 0=#best do. best=.value,id,j
                        elseif. value<{.best do. best=.value,id,j end.
                    end.
                end.
                'value chosen slot'=.best
                path=.(slot{.path),chosen,slot}.path
                remaining=.remaining-.chosen
            end.
            'insertion'installTour path
        case. 'EXACT' do.
            ('too many stops for exact (',(num #IDs),')')check (#IDs)<:10
            'exact'installTour exactTour''
        case. 'BOUND' do.
            edges=.spanningTree 0,ids
            mst=.0
            listing=.0$a:
            for_edge. edges do.
                'a b weight'=.>edge
                mst=.mst+weight
                listing=.listing,<(placeName a),'-',num b
            end.
            say 'mst: ',(' 'join listing),' (length ',(num mst),')'
            distances=.i.0
            for_id. ids do. distances=.distances,0 distance id end.
            distances=./:~distances
            one=.2*{.distances
            if. 1<#ids do.
                one=.+/2{.distances
                for_edge. spanningTree ids do. one=.one+2{>edge end.
            end.
            best=.mst>.one
            say 'bound: mst ',(num mst),', one-tree ',(num one),', best ',num best
            if. -.TourSet do. say 'gap: no tour'
            else.
                total=.pathLength Tour
                gap=.0
                if. best>0 do. gap=.<.((2000x*total-best)+best)%2*best end.
                say 'gap: tour ',(num total),', ',(tenths gap),'%'
            end.
        case. 'VRP';'SWEEP' do.
            q=.0".0{::args
            requireCapacity q
            if. command-:'VRP' do.
                limit=._1
                if. 2=#args do. limit=.0".1{::args end.
                q savings limit
            else.
                paths=.0$a:
                current=.i.0
                used=.0
                for_id. sweepOrder'' do.
                    demand=.2{getStop id
                    if. (used+demand)>q do. paths=.paths,<current
                        current=.i.0
                        used=.0 end.
                    current=.current,id
                    used=.used+demand
                end.
                Routes=:paths,<current
                Capacity=:q
                PlanSet=:1
                normalize''
                planReport 'sweep: capacity ',num q
            end.
        end.
    case. 'TOUR' do. requireTour''
        say 'tour: ',(notation Tour),' length ',num pathLength Tour
    case. 'TWOOPT';'OROPT';'SWAP' do.
        requireTour''
        before=.pathLength Tour
        moves=.0
        if. command-:'TWOOPT' do. 'path moves'=.1 twoOpt Tour
            Tour=:path
        else.
            while. 1 do.
                if. command-:'OROPT' do. change=.firstSegment Tour else. change=.firstSwap Tour end.
                if. 0=#change do. break. end.
                if. command-:'OROPT' do.
                    'i size j gain'=.change
                    segment=.size{.i}.Tour
                    rest=.(i{.Tour),(i+size)}.Tour
                    say 'move ',('-'join num&.>segment),' after ',(placeName rest boundary j),' gain ',num gain
                    Tour=:(j{.rest),segment,j}.rest
                else.
                    'i j gain'=.change
                    say 'swap ',(num i{Tour),' and ',(num j{Tour),' gain ',num gain
                    first=.i{Tour
                    Tour=:(j{Tour)i}Tour
                    Tour=:first j}Tour
                end.
                moves=.moves+1
            end.
        end.
        heading=.('twoopt';'oropt';'swap'){::~(;:'TWOOPT OROPT SWAP')i.<command
        say heading,': moves ',(num moves),', length ',(num before),' -> ',num pathLength Tour
    case. 'TIMECHECK' do.
        if. 0=#args do. requireTour''
            path=.Tour
            say 'timecheck tour depart ',timeText Start
        else.
            requirePlan''
            r=.0".0{::args
            ('no route ',num r)check r<:#Routes
            path=.(r-1){::Routes
            say 'timecheck route ',(num r),' depart ',timeText Start
        end.
        'visits stats'=.simulate path
        for_visit. visits do.
            'id arrival wait beginning leave late'=.visit
            status=.'ok'
            if. late>0 do. status=.'late ',num late end.
            say (num id),' arrive ',(timeText arrival),' wait ',(num wait),' begin ',(timeText beginning),' leave ',(timeText leave),' ',status
        end.
        'finish travel wait service violations lateness'=.stats
        say 'return ',(timeText finish),', travel ',(num travel),', wait ',(num wait),', service ',(num service),', violations ',(num violations),', lateness ',num lateness
    case. 'SPLIT' do. requireTour''
        q=.0".0{::args
        requireCapacity q
        splitPlan q
    case. 'ROUTES' do. requirePlan''
        planReport 'plan: capacity ',num Capacity
    case. 'RELOCATE';'EXCHANGE';'CROSS' do. requirePlan''
        improvePlan command
    case. 'ROUTEOPT' do.
        requirePlan''
        before=.planLength''
        for_r. i.#Routes do.
            path=.r{::Routes
            old=.pathLength path
            'changed moves'=.0 twoOpt path
            Routes=:(<changed)r}Routes
            say 'route ',(num r+1),': moves ',(num moves),', length ',(num old),' -> ',num pathLength changed
        end.
        normalize''
        say 'routeopt: length ',(num before),' -> ',num planLength''
    case. 'REPORT' do.
        say 'report: stops ',(num #IDs),', demand ',(num +/2{"1 Stops),', service ',(num +/3{"1 Stops),', windows ',num +/0<:4{"1 Stops
        if. -.TourSet do. say 'tour: none'
        else.
            stats=.1{::simulate Tour
            say 'tour: length ',(num 1{stats),', return ',(timeText 0{stats),', violations ',(num 4{stats),', lateness ',num 5{stats
        end.
        if. -.PlanSet do. say 'plan: none'
        else.
            total=.0
            latest=.0
            violations=.lateness=.0
            for_path. Routes do.
                path=.>path
                total=.total+pathLoad path
                stats=.1{::simulate path
                latest=.latest>.0{stats
                violations=.violations+4{stats
                lateness=.lateness+5{stats
            end.
            k=.#Routes
            utilization=.<.((2000x*total)+k*Capacity)%2*k*Capacity
            say 'plan: capacity ',(num Capacity),', routes ',(num k),', length ',(num planLength''),', utilization ',(tenths utilization),'%, return ',(timeText latest),', violations ',(num violations),', lateness ',num lateness
        end.
    end.
)
main =: 3 : 0
    DepotSet=:TourSet=:PlanSet=:0
    Depot=:0 0
    Start=:480
    IDs=:Tour=:i.0
    Stops=:0 6$0
    Routes=:0$a:
    Capacity=:0
    lines=.<;._2 (1!:1 <'/dev/stdin'),LF
    count=.0".0{::lines
    for_i. i.count do.
        try. execute (i+1){::lines
        catcht. say 'error: ',Reason end.
    end.
)
main''
