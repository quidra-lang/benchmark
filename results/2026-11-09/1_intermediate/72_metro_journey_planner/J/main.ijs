LF =: 10{a.
Output =: 0$a:
num =: 3 : ',''0'' 8!:2 y'
emit =: 3 : 'Output=:Output,<y'
join =: 4 : '(#x)}.;(<x),&.>y'
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
parseTime =: 3 : '(60*0".2{.y)+0".3}.y'
clockText =: 3 : 0
    h=.num <.y%60
    m=.num 60|y
    (_2{.'0',h),':',_2{.'0',m
)
halfPrice =: 3 : '10*>.y%20'
station =: 3 : 0
    at=.Names i.<y
    ('unknown station ',y)check at<#Names
    at
)
service =: 3 : 0
    at=.LineNames i.<y
    ('unknown line ',y)check at<#LineNames
    at{::Lines
)
checkOpen =: 3 : '(''station '',(y{::Names),'' is closed'')check -.y{Closed'
endpoints =: 3 : 0
    'origin destination'=.y
    s=.station origin
    t=.station destination
    'origin and destination are the same'check s~:t
    checkOpen s
    checkOpen t
    s,t
)
segmentKey =: 3 : '/:~y'
blocked =: 3 : '(<segmentKey y)e.ClosedSegments'
trips =: 3 : '1+<.((2{::y)-1{::y)%3{::y'
directions =: 3 : 0
    stops=.4{::y
    offsets=.5{::y
    forward=.(<y),(<stops),(<offsets),<0
    backward=.(<y),(<|.stops),(<({:offsets)-|.offsets),<1
    (<forward),<backward
)
trainTime =: 4 : 0
    'q j'=.y
    line=.0{::x
    (1{::line)+(6{::line)+(q*3{::line)+j{2{::x
)
firstTrain =: 4 : 0
    'j ready'=.y
    line=.0{::x
    q=.0>.>.(ready-x trainTime 0,j)%3{::line
    if. q<trips line do. q else. _1 end.
)
upcoming =: 4 : 0
    'j ready count'=.y
    q=.x firstTrain j,ready
    if. q<0 do. i.0 else. q+i.count<.(trips 0{::x)-q end.
)
toward =: 4 : 0
    stops=.4{::x
    ((y{::Names),' is not a terminal of line ',0{::x)check y e.({.stops),{:stops
    (y~:{:stops){::directions x
)
orderedLines =: 3 : 0
    result=.0$a:
    for_at. /:LineNames do.
        value=.at{::Lines
        if. (-.y)+.-.7{::value do. result=.result,<value end.
    end.
    result
)
emptyLabels =: 3 : '(< (#Names)$_1),<(#Names)$<0$a:'
labelAt =: 4 : '(<y{0{::x),<y{::1{::x'
putLabel =: 4 : 0
    'at time journey'=.y
    times=.time at}0{::x
    journeys=.(<journey)at}1{::x
    (<times),<journeys
)
improves =: 4 : 0
    'at time'=.y
    old=.at{0{::x
    (old<0)+.time<old
)
makeRide =: 4 : 0
    'q i j'=.y
    line=.0{::x
    stops=.1{::x
    (<'ride'),(<0{::line),(<{:stops),(<i{stops),(<x trainTime q,i),(<j{stops),(<x trainTime q,j),<j-i
)
walkFrom =: 4 : 0
    'name source'=.y
    'time journey'=.source
    result=.x
    changed=.i.0
    row=.name{::Walks
    for_neighbor. /:Names do.
        minutes=.neighbor{row
        if. minutes<0 do. continue. end.
        arrival=.time+minutes
        if. (-.neighbor{Closed)*.(arrival<:1440)*.result improves neighbor,arrival do.
            leg=.(<'walk'),(<''),(<_1),(<name),(<time),(<neighbor),(<arrival),<0
            result=.result putLabel (<neighbor),(<arrival),<journey,<leg
            changed=.changed,neighbor
        end.
    end.
    (<result),<changed
)
rideFrom =: 4 : 0
    'route name ready journey'=.y
    result=.x
    stops=.1{::route
    i=.stops i.name
    if. i>:(#stops)-1 do. result return. end.
    q=.route firstTrain i,ready
    if. q<0 do. result return. end.
    for_j. (i+1)+i.(#stops)-i+1 do.
        name=.j{stops
        if. blocked ((j-1){stops),name do. break. end.
        if. name{Closed do. continue. end.
        arrival=.route trainTime q,j
        if. result improves name,arrival do. result=.result putLabel (<name),(<arrival),<journey,<route makeRide q,i,j end.
    end.
    result
)
earliest =: 3 : 0
    'origin departure'=.y
    result=.emptyLabels''
    result=.result putLabel (<origin),(<departure),<0$a:
    settled=.(#Names)$0
    active=.orderedLines 1
    while. 1 do.
        selected=._1
        time=._1
        for_name. /:Names do.
            candidate=.name{0{::result
            if. (-.name{settled)*.candidate>:0 do.
                if. (time<0)+.candidate<time do. selected=.name
                    time=.candidate end.
            end.
        end.
        if. selected<0 do. result return. end.
        settled=.1 selected}settled
        source=.result labelAt selected
        journey=.1{::source
        ready=.time+(selected~:origin)*selected{Transfers
        for_line. active do. for_route. directions >line do.
            result=.result rideFrom (< >route),(<selected),(<ready),<journey
        end. end.
        result=.0{::result walkFrom (<selected),<source
    end.
)
walkStep =: 4 : 0
    'starts marked'=.y
    result=.x
    changed=.marked
    starts=.~.starts
    for_name. starts{~/:starts{Names do.
        step=.result walkFrom (<name),<x labelAt name
        result=.0{::step
        changed=.changed,1{::step
    end.
    (<result),<~.changed
)
rideRound =: 4 : 0
    'origin route previous marked ridden'=.y
    result=.x
    changed=.ridden
    stops=.1{::route
    q=._1
    board=.0
    journey=.0$a:
    for_j. i.#stops do.
        name=.j{stops
        if. j>0 do.
            if. blocked ((j-1){stops),name do. q=._1 end.
        end.
        if. name{Closed do. continue. end.
        if. q>:0 do.
            arrival=.route trainTime q,j
            if. result improves name,arrival do.
                result=.result putLabel (<name),(<arrival),<journey,<route makeRide q,board,j
                changed=.changed,name
            end.
        end.
        if. (j<(#stops)-1)*.name e.marked do.
            source=.previous labelAt name
            ready=.(0{::source)+(name~:origin)*name{Transfers
            next=.route firstTrain j,ready
            if. (next>:0)*.(q<0)+.next<q do. q=.next
                board=.j
                journey=.1{::source end.
        end.
    end.
    (<result),<~.changed
)
roundSearch =: 3 : 0
    'origin departure'=.y
    result=.emptyLabels''
    result=.result putLabel (<origin),(<departure),<0$a:
    step=.result walkStep (<,origin),<,origin
    result=.0{::step
    marked=.1{::step
    rounds=.,<result
    active=.orderedLines 1
    while. #marked do.
        previous=.result
        previousmarked=.marked
        ridden=.i.0
        for_line. active do. for_route. directions >line do.
            step=.result rideRound (<origin),(< >route),(<previous),(<previousmarked),<ridden
            result=.0{::step
            ridden=.1{::step
        end. end.
        step=.result walkStep (<ridden),<ridden
        result=.0{::step
        marked=.1{::step
        rounds=.rounds,<result
    end.
    rounds
)
rideCount =: 3 : 0
    total=.0
    for_leg. y do. total=.total+'ride'-:0{::>leg end.
    total
)
journeyReport =: 3 : 0
    'heading departure value'=.y
    'arrival journey'=.value
    rides=.0
    walks=.0
    for_leg. journey do.
        kind=.0{::>leg
        rides=.rides+kind-:'ride'
        walks=.walks+kind-:'walk'
    end.
    emit heading,' ',(clockText departure),' -> ',(clockText arrival),' total ',(num arrival-departure),' rides ',(num rides),' walks ',num walks
    previous=.departure
    for_leg. journey do.
        'kind id terminal origin start destination finish stops'=.>leg
        if. kind-:'ride' do.
            emit 'RIDE ',id,' toward ',(terminal{::Names),' ',(origin{::Names),' ',(clockText start),' -> ',(destination{::Names),' ',(clockText finish),' wait ',(num start-previous),' stops ',num stops
        elseif. kind-:'walk' do. emit 'WALK ',(origin{::Names),' ',(clockText start),' -> ',(destination{::Names),' ',clockText finish
        else. emit 'STAY ',(origin{::Names),' ',(clockText start),' -> ',clockText finish end.
        previous=.finish
    end.
)
stopFlags =: 4 : 0
    result=.''
    if. (y{x){Closed do. result=.' closed' end.
    if. y>0 do. if. blocked ((y-1){x),y{x do. result=.result,' blocked' end. end.
    result
)
fareItems =: 4 : 0
    cap=.Discount
    if. x do. cap=.halfPrice cap end.
    previous=._1
    result=.0$a:
    for_leg. y do.
        leg=.>leg
        if. -. (0{::leg)-:'ride' do. continue. end.
        line=.service 1{::leg
        route=.line toward 2{::leg
        stops=.1{::route
        at=.stops i.3{::leg
        zones=.#~.((at+i.1+7{::leg){stops){Zones
        price=.((#Prices)<.zones)-1
        price=.price{Prices
        if. x do. price=.halfPrice price end.
        discount=.0
        if. (previous>:0)*.((4{::leg)-previous)<:Window do. discount=.cap<.price end.
        result=.result,<(<leg),(<zones),(<price),<discount
        previous=.6{::leg
    end.
    result
)
passing =: 3 : 0
    'name time count arriving'=.y
    result=.0$a:
    for_line. orderedLines 1 do.
        line=.>line
        if. -.name e.4{::line do. continue. end.
        for_route. directions line do.
            route=.>route
            stops=.1{::route
            at=.stops i.name
            if. (arriving*.at=0)+.((-.arriving)*.at=(#stops)-1) do. continue. end.
            for_q. route upcoming at,time,count do.
                result=.result,<(<route trainTime q,at),(<0{::line),(<3{::route),<route
            end.
        end.
    end.
    if. 0=#result do. result return. end.
    result=.result{~/:0&{::&>result
    (count<.#result){.result
)
execute =: 3 : 0
    words=.' 'split y
    command=.0{::words
    args=.}.words
    select. command
    case. 'STATION' do.
        id=.0{::args
        ('station ',id,' already exists')check -.(<id)e.Names
        old=.#Names
        Names=:Names,<id
        Zones=:Zones,0".1{::args
        StationNames=:StationNames,2{args
        Transfers=:Transfers,0
        Closed=:Closed,0
        Walks=:(,&_1)&.>Walks
        Walks=:Walks,<(#Names)$_1
        emit 'STATION ',id,' zone ',(1{::args),' ',2{::args
    case. 'LINE' do.
        id=.0{::args
        ('line ',id,' already exists')check -.(<id)e.LineNames
        names=.(4+2*i.>.((#args)-4)%2){args
        stops=.i.0
        for_name. names do. stops=.stops,station >name end.
        seen=.i.0
        for_s. stops do.
            ('station ',(s{::Names),' appears twice on line ',id)check -.s e.seen
            seen=.seen,s
        end.
        first=.parseTime 1{::args
        last=.parseTime 2{::args
        ('line ',id,' first departure is after last departure')check first<:last
        durations=.0".&>(5+2*i.<.((#args)-5)%2){args
        offsets=.0,+/\durations
        ('line ',id,' runs past 24:00')check (last+{:offsets)<:1440
        line=.(<id),(<first),(<last),(<0".3{::args),(<stops),(<offsets),(<0),<0
        LineNames=:LineNames,<id
        Lines=:Lines,<line
        emit 'LINE ',id,' stops ',(num #stops),' time ',(num {:offsets),' trips ',num trips line
    case. 'TRANSFER' do.
        at=.station 0{::args
        Transfers=:(0".1{::args)at}Transfers
        emit 'TRANSFER ',(0{::args),' ',1{::args
    case. 'WALK' do.
        a=.station 0{::args
        b=.station 1{::args
        ('walk from ',(0{::args),' to itself')check a~:b
        minutes=.0".2{::args
        old=.b{a{::Walks
        ar=.minutes b}a{::Walks
        br=.minutes a}b{::Walks
        Walks=:(<ar)a}Walks
        Walks=:(<br)b}Walks
        text=.'WALK ',(0{::args),' ',(1{::args),' ',num minutes
        if. old>:0 do. text=.text,' was ',num old end.
        emit text
    case. 'TARIFF' do.
        prices=.0".&>2}.args
        'tariff prices must not decrease'check *./(}:prices)<:}.prices
        Discount=:0".0{::args
        Window=:0".1{::args
        Prices=:prices
        emit 'TARIFF zones ',(num #Prices),' discount ',(num Discount),' window ',num Window
    case. 'CLOSE';'OPEN' do.
        a=.station 0{::args
        closing=.command-:'CLOSE'
        if. 1=#args do.
            suffix=.'not closed'
            if. closing do. suffix=.'already closed' end.
            ('station ',(a{::Names),' is ',suffix)check closing~:a{Closed
            Closed=:closing a}Closed
            emit command,' ',a{::Names
        else.
            b=.station 1{::args
            key=.segmentKey a,b
            label=.(a{::Names),'-',b{::Names
            if. closing do.
                affected=.0$a:
                for_line. orderedLines 0 do.
                    line=.>line
                    stops=.4{::line
                    for_i. i.(#stops)-1 do.
                        if. key-:segmentKey 2{.i}.stops do. affected=.affected,<0{::line break. end.
                    end.
                end.
                ('no segment ',label)check 0<#affected
                ('segment ',label,' is already closed')check -.(<key)e.ClosedSegments
                ClosedSegments=:ClosedSegments,<key
                emit 'CLOSE ',label,' lines ',' 'join affected
            else.
                ('segment ',label,' is not closed')check (<key)e.ClosedSegments
                ClosedSegments=:ClosedSegments#~ClosedSegments~:<key
                emit 'OPEN ',label
            end.
        end.
    case. 'DELAY';'SUSPEND';'RESUME' do.
        id=.0{::args
        value=.service id
        if. command-:'DELAY' do.
            minutes=.0".1{::args
            ('line ',id,' runs past 24:00')check ((2{::value)+minutes+{:5{::value)<:1440
            value=.(<minutes)6}value
            emit 'DELAY ',id,' ',num minutes
        else.
            suspend=.command-:'SUSPEND'
            suffix=.'not suspended'
            if. suspend do. suffix=.'already suspended' end.
            ('line ',id,' is ',suffix)check suspend~:7{::value
            value=.(<suspend)7}value
            emit command,' ',id
        end.
        Lines=:(<value)(LineNames i.<id)}Lines
    case. 'VIA' do.
        origin=.station 0{::args
        via=.station 1{::args
        destination=.station 2{::args
        'origin and destination are the same'check origin~:destination
        ('via station ',(via{::Names),' must differ from origin and destination')check -.via e.origin,destination
        checkOpen origin
        checkOpen via
        checkOpen destination
        departure=.parseTime 3{::args
        heading=.'VIA ',(origin{::Names),' ',(via{::Names),' ',destination{::Names
        firstlabels=.earliest origin,departure
        first=.firstlabels labelAt via
        if. (0{::first)>:0 do.
            resume=.(0{::first)+via{Transfers
            secondlabels=.earliest via,resume
            second=.secondlabels labelAt destination
            if. (0{::second)>:0 do.
                stay=.(<'stay'),(<''),(<_1),(<via),(<0{::first),(<via),(<resume),<0
                journey=.(1{::first),(<stay),1{::second
                journeyReport (<heading),(<departure),<(<0{::second),<journey return.
            end.
        end.
        emit heading,' ',(3{::args),' unreachable'
    case. 'ROUTE';'FEWEST';'PARETO';'FARE';'LASTTRAIN';'ARRIVEBY';'PROFILE' do.
        'origin destination'=.endpoints 2{.args
        if. command-:'FARE' do.
            ('unknown fare class ',3{::args)check (<3{::args)e.;:'ADULT CHILD'
            'no tariff'check 0<#Prices
        end.
        if. (<command)e.;:'LASTTRAIN ARRIVEBY' do.
            deadline=.1440
            heading=.command,' ',(origin{::Names),' ',destination{::Names
            if. command-:'ARRIVEBY' do. deadline=.parseTime 2{::args
                heading=.heading,' by ',2{::args end.
            for_departure. |.i.deadline do.
                labels=.earliest origin,departure
                value=.labels labelAt destination
                if. ((0{::value)>:0)*.(0{::value)<:deadline do. journeyReport (<heading),(<departure),<value return. end.
            end.
            emit heading,' none' return.
        end.
        departure=.parseTime 2{::args
        heading=.command,' ',(origin{::Names),' ',destination{::Names
        select. command
        case. 'PROFILE' do.
            finish=.parseTime 3{::args
            ('empty interval ',(2{::args),' ',3{::args)check departure<:finish
            arrivals=.i.0
            for_time. departure+i.1+finish-departure do.
                labels=.earliest origin,time
                arrivals=.arrivals,destination{0{::labels
            end.
            chosen=.i.0
            for_i. i.#arrivals do.
                if. (i{arrivals)<0 do. continue. end.
                if. i=(#arrivals)-1 do. chosen=.chosen,i
                elseif. (((i+1){arrivals)<0)+.(i{arrivals)<(i+1){arrivals do. chosen=.chosen,i end.
            end.
            emit heading,' ',(2{::args),' ',(3{::args),' count ',num #chosen
            for_i. chosen do. time=.departure+i
                arrival=.i{arrivals
                emit (clockText time),' -> ',(clockText arrival),' total ',num arrival-time end.
        case. 'FEWEST';'PARETO' do.
            rounds=.roundSearch origin,departure
            options=.0$a:
            previous=._1
            for_k. i.#rounds do.
                value=.(k{::rounds)labelAt destination
                arrival=.0{::value
                if. arrival>:0 do.
                    if. (previous<0)+.arrival<previous do. options=.options,<(<k),<value end.
                    previous=.arrival
                end.
            end.
            if. command-:'PARETO' do.
                emit heading,' ',(2{::args),' options ',num #options
                for_option. options do. 'k value'=.>option
                    journeyReport (<'OPTION trips ',num k),(<departure),<value end.
            elseif. 0=#options do. emit heading,' ',(2{::args),' unreachable'
            else. 'k value'=.0{::options
                journeyReport (<heading,' trips ',num k),(<departure),<value end.
        case. do.
            labels=.earliest origin,departure
            value=.labels labelAt destination
            if. (0{::value)<0 do.
                text=.heading,' ',2{::args
                if. command-:'FARE' do. text=.text,' ',3{::args end.
                emit text,' unreachable'
            elseif. command-:'ROUTE' do. journeyReport (<heading),(<departure),<value
            else.
                tickets=.((3{::args)-:'CHILD')fareItems 1{::value
                total=.0
                for_ticket. tickets do. total=.total+(2{::>ticket)-3{::>ticket end.
                emit heading,' ',(2{::args),' ',(3{::args),' rides ',(num #tickets),' total ',num total
                for_ticket. tickets do.
                    'leg zones price discount'=.>ticket
                    emit 'TICKET ',(1{::leg),' ',((3{::leg){::Names),' ',((5{::leg){::Names),' zones ',(num zones),' price ',(num price),' discount ',(num discount),' pay ',num price-discount
                end.
            end.
        end.
    case. 'REACH' do.
        name=.station 0{::args
        checkOpen name
        departure=.parseTime 1{::args
        labels=.earliest name,departure
        times=.0{::labels
        selected=./:Names
        selected=.selected#~((selected{times)>:0)*.(selected{times)<:departure+0".2{::args
        selected=.selected{~/:selected{times
        emit 'REACH ',(0{::args),' ',(1{::args),' ',(2{::args),' count ',num #selected
        for_at. selected do.
            emit (at{::Names),' ',(at{::StationNames),' ',(clockText at{times),' ',(num (at{times)-departure),' rides ',num rideCount at{::1{::labels
        end.
    case. 'TIMETABLE' do.
        name=.station 0{::args
        line=.service 1{::args
        ('station ',(0{::args),' is not on line ',1{::args)check name e.4{::line
        terminal=.Names i.<2{::args
        if. terminal=#Names do. fail (2{::args),' is not a terminal of line ',1{::args end.
        route=.line toward terminal
        ('no departures from ',(0{::args),' toward ',2{::args)check name~:terminal
        ('line ',(1{::args),' is suspended')check -.7{::line
        checkOpen name
        at=.(1{::route)i.name
        trains=.route upcoming at,(parseTime 3{::args),0".4{::args
        times=.0$a:
        for_q. trains do. times=.times,<clockText route trainTime q,at end.
        text=.'TIMETABLE ',(0{::args),' ',(1{::args),' toward ',(2{::args),' ',(3{::args),' next ',num #times
        if. #times do. text=.text,' ',' 'join times end.
        emit text
    case. 'DEPARTURES';'ARRIVALS' do.
        name=.station 0{::args
        checkOpen name
        arriving=.command-:'ARRIVALS'
        selected=.passing name,(parseTime 1{::args),(0".2{::args),arriving
        emit command,' ',(0{::args),' ',(1{::args),' count ',num #selected
        for_item. selected do.
            'time id order route'=.>item
            stops=.1{::route
            if. arriving do. text=.'from ',({.stops){::Names else. text=.'toward ',({:stops){::Names end.
            emit (clockText time),' ',id,' ',text
        end.
    case. 'TRIP';'SHOWLINE' do.
        line=.service 0{::args
        if. command-:'SHOWLINE' do.
            state=.'running'
            if. 7{::line do. state=.'suspended' end.
            emit 'SHOWLINE ',(0{::line),' ',state,' first ',(clockText 1{::line),' last ',(clockText 2{::line),' headway ',(num 3{::line),' delay ',(num 6{::line),' trips ',num trips line
            stops=.4{::line
            for_j. i.#stops do. name=.j{stops
                emit (num j{5{::line),' ',(name{::Names),' zone ',(num name{Zones),stops stopFlags j end.
        else.
            terminal=.Names i.<1{::args
            if. terminal=#Names do. fail (1{::args),' is not a terminal of line ',0{::args end.
            route=.line toward terminal
            ('line ',(0{::line),' is suspended')check -.7{::line
            q=.route firstTrain 0,parseTime 2{::args
            heading=.'TRIP ',(0{::line),' toward ',(1{::args),' ',2{::args
            if. q<0 do. emit heading,' none'
            else.
                emit heading,' trip ',(num q+1),' departs ',clockText route trainTime q,0
                stops=.1{::route
                for_j. i.#stops do. emit (clockText route trainTime q,j),' ',((j{stops){::Names),stops stopFlags j end.
            end.
        end.
    case. 'INFO' do.
        at=.station 0{::args
        state=.'open'
        if. at{Closed do. state=.'closed' end.
        emit 'INFO ',(at{::Names),' ',(at{::StationNames),' zone ',(num at{Zones),' transfer ',(num at{Transfers),' ',state
        lines=.0$a:
        for_line. orderedLines 0 do. line=.>line
            if. at e.4{::line do. lines=.lines,<0{::line end. end.
        if. #lines do. emit 'LINES ',' 'join lines else. emit 'LINES none' end.
        words=.0$a:
        for_neighbor. /:Names do.
            minutes=.neighbor{at{::Walks
            if. minutes>:0 do. words=.words,<(neighbor{::Names),' ',num minutes end.
        end.
        if. #words do. emit 'WALKS ',' 'join words else. emit 'WALKS none' end.
    case. 'STATUS' do.
        walks=.0
        for_row. Walks do. walks=.walks++/(>row)>:0 end.
        walks=.-:walks
        emit 'STATUS stations ',(num #Names),' lines ',(num #Lines),' walks ',num walks
        for_at. /:Names do. if. at{Closed do. emit 'CLOSED ',at{::Names end. end.
        order=./:Names
        for_i. i.#Names do.
            for_j. (i+1)+i.(#Names)-i+1 do.
                a=.i{order
                b=.j{order
                if. blocked a,b do. emit 'CLOSED ',(a{::Names),'-',b{::Names end.
            end.
        end.
        for_line. orderedLines 0 do. line=.>line
            if. 7{::line do. emit 'SUSPENDED ',0{::line end. end.
        for_line. orderedLines 0 do. line=.>line
            if. 6{::line do. emit 'DELAYED ',(0{::line),' ',num 6{::line end. end.
    end.
)
main =: 3 : 0
    Names=:StationNames=:LineNames=:Lines=:Walks=:ClosedSegments=:0$a:
    Zones=:Transfers=:Closed=:Prices=:i.0
    Discount=:Window=:0
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
