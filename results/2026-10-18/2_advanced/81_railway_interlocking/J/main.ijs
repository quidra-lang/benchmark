load 'layout.ijs'
load 'interlocking.ijs'
load 'signals.ijs'
load 'trains.ijs'
load 'safety.ijs'

AspectNames =: ;:'RED YELLOW GREEN'
StateNames =: ;:'WAITING RUNNING EXITED'
RouteStateNames =: (<'none'),;:'LOCKED USED APPROACH'
DirectionNames =: ;:'UP DOWN'
intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ,":y
    '-'(I.text='_')}text
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
split_commas =: 3 : '<;._1 '','',y'
log_event =: 3 : 'EventLog =: EventLog,<(integer Time),'' '',y'
occupied =: 3 : '(y{SectionFailed)+.0<#y{::Occupants'
route_stat_add =: 4 : 0
    'column amount' =. y
    position =. <x,column
    RouteStats =: (amount+position{RouteStats)position}RouteStats
)
read_settings =: 3 : 0
    for_line. read_lines 'input/params.txt' do.
        fields =. split_words >line
        values =. ".' 'join }.fields
        select. 0{::fields
        case. 'END' do. EndTime =: {.values
        case. 'THROW' do. ThrowTime =: {.values
        case. 'OVERLAP' do. OverlapTime =: {.values
        case. 'SNAPSHOTS' do. SnapshotTimes =: ,values
        end.
    end.
    Events =: 0$a:
    for_line. read_lines 'input/events.txt' do.
        fields =. split_words >line
        Events =: Events,<(<".0{::fields),(1{fields),<2}.fields
    end.
    Time =: 0
    QRoutes =: i.0
    QTimes =: i.0
    QReasons =: 0$a:
    QActive =: i.0
    Dropped =: 0
    EventLog =: 0$a:
    Snapshots =: 0$a:
    initialize_safety ''
)
start_throw =: 4 : 0
    PointMoving =: 1 x}PointMoving
    PointTargets =: y x}PointTargets
    completion =. Time+ThrowTime
    PointCompletions =: completion x}PointCompletions
    log_event 'MOVE ',(x{::PointNames),' ',(y{'NR'),' until ',integer completion
)
complete_throws =: 3 : 0
    for_point. I.PointMoving*.PointCompletions=Time do.
        position =. point{PointTargets
        PointPositions =: position point}PointPositions
        PointMoving =: 0 point}PointMoving
        PointCompletions =: _1 point}PointCompletions
        PointThrows =: ((point{PointThrows)+1)point}PointThrows
        log_event 'POINT ',(point{::PointNames),' ',position{'NR'
    end.
)
release_approaches =: 3 : 0
    for_route. I.(RouteStates=3)*.RouteReleaseTimes=Time do.
        release_route route
        log_event 'TIMEOUT ',route{::RouteNames
    end.
)
add_request =: 4 : 0
    number =. 1+#QRoutes
    QRoutes =: QRoutes,x
    QTimes =: QTimes,Time
    QReasons =: QReasons,<''
    QActive =: QActive,1
    x route_stat_add 0 1
    log_event 'REQUEST q',(integer number),' ',(x{::RouteNames),' ',y
)
cancel_route =: 3 : 0
    pending =. I.QActive*.QRoutes=y
    if. #pending do.
        for_request. pending do.
            log_event 'DROP q',(integer request+1),' ',y{::RouteNames
            QActive =: 0 request}QActive
            Dropped =: Dropped+1
        end.
        i.0 return.
    end.
    state =. y{RouteStates
    if. state=1 do.
        y route_stat_add 3 1
        signal =. y{RouteStarts
        if. (0~:signal{SignalAspects)*.occupied signal{SignalSections do.
            release =. Time+y{RouteApproachTimes
            RouteStates =: 3 y}RouteStates
            RouteReleaseTimes =: release y}RouteReleaseTimes
            log_event 'CANCEL ',(y{::RouteNames),' approach until ',integer release
        else.
            release_route y
            log_event 'CANCEL ',(y{::RouteNames),' released'
        end.
    else.
        detail =. 'refused'
        if. state=0 do.
            detail =. 'none'
        end.
        log_event 'CANCEL ',(y{::RouteNames),' ',detail
    end.
)
individual_throw =: 4 : 0
    if. #x{::PointLocks do.
        result =. 'locked'
    elseif. x{PointFailed do.
        result =. 'failed'
    elseif. x{PointMoving do.
        result =. 'moving'
    elseif. occupied x{PointCommon do.
        result =. 'occupied'
    elseif. y=x{PointPositions do.
        result =. 'none'
    else.
        result =. 'start'
    end.
    log_event 'THROW ',(x{::PointNames),' ',(y{'NR'),' ',result
    if. result-:'start' do.
        x start_throw y
    end.
)
execute_events =: 3 : 0
    for_event. Events do.
        'time command arguments' =. >event
        if. time~:Time do.
            continue.
        end.
        name =. 0{::arguments
        select. command
        case. 'REQUEST' do.
            (RouteNames i.<name)add_request 'OPERATOR'
        case. 'CANCEL' do.
            cancel_route RouteNames i.<name
        case. 'THROW' do.
            point =. PointNames i.<name
            point individual_throw 'R'={.1{::arguments
        case. 'TCFAIL';'TCFIX' do.
            section =. SectionNames i.<name
            SectionFailed =: (command-:'TCFAIL')section}SectionFailed
            log_event command,' ',name
        case. 'POINTFAIL';'POINTFIX' do.
            point =. PointNames i.<name
            failed =. command-:'POINTFAIL'
            PointFailed =: failed point}PointFailed
            if. failed*.point{PointMoving do.
                PointCompletions =: _1 point}PointCompletions
            end.
            log_event command,' ',name
            if. (-.failed)*.point{PointMoving do.
                point start_throw point{PointTargets
            end.
        end.
    end.
)
opposite_lock =: 4 : 0
    +./(y{RouteDirections)~:x{RouteDirections
)
request_reason =: 3 : 0
    route =. y
    if. route{RouteStates do.
        'busy' return.
    end.
    for_other. route{::RouteConflicts do.
        if. (other{RouteStates)e.1 3 do.
            'conflict ',other{::RouteNames return.
        end.
    end.
    for_section. route{::RouteSections do.
        if. occupied section do.
            'occupied ',section{::SectionNames return.
        end.
        overlaps =. I.section{SectionOverlapLocks
        if. (_1~:section{SectionRouteLocks)+.(overlaps opposite_lock route) do.
            'locked ',section{::SectionNames return.
        end.
    end.
    for_section. route{::RouteOverlap do.
        if. occupied section do.
            'occupied ',section{::SectionNames return.
        end.
        locks =. I.section{SectionOverlapLocks
        owner =. section{SectionRouteLocks
        if. owner~:_1 do.
            locks =. locks,owner
        end.
        if. locks opposite_lock route do.
            'locked ',section{::SectionNames return.
        end.
    end.
    for_requirement. route{::RouteRequirements do.
        'point position' =. requirement
        locks =. point{::PointLocks
        if. +./position~:1{"1 locks do.
            'point ',(point{::PointNames),' locked' return.
        end.
        if. ((-.point{PointMoving)*.position=point{PointPositions)+.((point{PointMoving)*.position=point{PointTargets) do.
            continue.
        end.
        if. point{PointFailed do.
            'point ',(point{::PointNames),' failed' return.
        elseif. point{PointMoving do.
            'point ',(point{::PointNames),' moving' return.
        elseif. occupied point{PointCommon do.
            'point ',(point{::PointNames),' occupied' return.
        end.
    end.
    ''
)
judge_requests =: 3 : 0
    for_request. I.QActive do.
        route =. request{QRoutes
        reason =. request_reason route
        if. #reason do.
            if. -.reason-:request{::QReasons do.
                log_event 'WAIT q',(integer request+1),' ',(route{::RouteNames),' ',reason
                QReasons =: (<reason)request}QReasons
            end.
            continue.
        end.
        QActive =: 0 request}QActive
        lock_route route
        wait =. Time-request{QTimes
        log_event 'GRANT q',(integer request+1),' ',(route{::RouteNames),' wait ',integer wait
        route route_stat_add 1 1
        route route_stat_add 4,wait
        position =. <route,5
        RouteStats =: (wait>.position{RouteStats)position}RouteStats
        for_requirement. route{::RouteRequirements do.
            'point target' =. requirement
            if. (-.point{PointMoving)*.target~:point{PointPositions do.
                point start_throw target
            end.
        end.
    end.
)
decide_signals =: 3 : 0
    decided =. decide_aspects ''
    for_signal. I.decided~:SignalAspects do.
        log_event 'SIGNAL ',(signal{::SignalNames),' ',(signal{decided){::AspectNames
    end.
    SignalAspects =: decided
)

occupied_parts =: 3 : 0
    result =. 0 4$0
    if. 1~:y{TrainStates do.
        result return.
    end.
    head =. y{TrainHeads
    tail =. head-y{TrainLengths
    for_part. y{::TrainPaths do.
        'section start' =. part
        end =. start+section{SectionLengths
        if. (start<head)*.end>tail do.
            result =. result,section,start,(tail>.start),head<.end
        end.
    end.
    result
)
head_section =: 3 : 0
    path =. y{::TrainPaths
    head =. y{TrainHeads
    for_i. |.i.#path do.
        part =. i{path
        if. (1{part)<head do.
            part return.
        end.
    end.
    0{path
)
enter_train =: 3 : 0
    state =. y{TrainStates
    if. state=2 do.
        0 return.
    elseif. state=1 do.
        1 return.
    end.
    boundary =. y{TrainEntry
    section =. boundary{BoundarySections
    if. (Time<y{TrainEntryTimes)+.(occupied section)+.boundary{EnteredBoundaries do.
        0 return.
    end.
    TrainStates =: 1 y}TrainStates
    TrainDirections =: (boundary{BoundaryEnds)y}TrainDirections
    TrainPaths =: (<,:section,0)y}TrainPaths
    TrainHeads =: 0 y}TrainHeads
    TrainSpeeds =: (y{TrainEntrySpeed)y}TrainSpeeds
    TrainEntered =: Time y}TrainEntered
    EnteredBoundaries =: 1 boundary}EnteredBoundaries
    log_event 'ENTER ',(y{::TrainNames),' ',boundary{::BoundaryNames
    1
)
reverse_train =: 4 : 0
    'section start' =. head_section x
    end =. start+section{SectionLengths
    parts =. occupied_parts x
    path =. 0 2$0
    for_part. |.parts do.
        'section origin low high' =. part
        coordinate =. end-(origin+section{SectionLengths)
        path =. path,section,coordinate
    end.
    TrainPaths =: (<path)x}TrainPaths
    TrainHeads =: (end-((x{TrainHeads)-x{TrainLengths))x}TrainHeads
    TrainDirections =: (1-x{TrainDirections)x}TrainDirections
    log_event 'REVERSE ',(x{::TrainNames),' ',y{::SectionNames
)
finish_dwell =: 3 : 0
    if. -.y{TrainDwelling do.
        1 return.
    end.
    index =. y{TrainStopIndices
    stops =. y{::TrainStops
    stop =. index{stops
    if. (Time<(5{stop)+2{stop)+.Time<4{stop do.
        0 return.
    end.
    TrainDwelling =: 0 y}TrainDwelling
    TrainAwaitingDeparture =: index y}TrainAwaitingDeparture
    TrainStopIndices =: (index+1)y}TrainStopIndices
    if. 0{stop do.
        y reverse_train 1{stop
    end.
    1
)
limit_distance =: 3 : 0
    if. _1~:y{TrainBoundary do.
        _1 return.
    end.
    'section start' =. head_section y
    direction =. y{TrainDirections
    distance =. (start+section{SectionLengths)-y{TrainHeads
    index =. y{TrainStopIndices
    stops =. y{::TrainStops
    while. 1 do.
        signal =. (<section,direction){SignalAt
        if. signal~:_1 do.
            if. 0=signal{SignalAspects do.
                distance return.
            end.
        end.
        if. index<#stops do.
            if. section=(<index,1){stops do.
                distance return.
            end.
        end.
        'kind following' =. section beyond direction
        if. kind=3 do.
            _1 return.
        elseif. kind e.2 4 do.
            distance return.
        end.
        distance =. distance+following{SectionLengths
        section =. following
    end.
)
pass_signal =: 4 : 0
    routes =. I.(RouteStarts=y)*.RouteStates e.1 3
    route_name =. '-'
    if. #routes do.
        route =. {.routes
        route_name =. route{::RouteNames
    end.
    aspect =. y{SignalAspects
    log_event 'PASS ',(x{::TrainNames),' ',(y{::SignalNames),' ',(aspect{::AspectNames),' ',route_name
    SignalPasses =: ((y{SignalPasses)+1)y}SignalPasses
    TrainPasses =: ((x{TrainPasses)+1)x}TrainPasses
    if. #routes do.
        RouteStates =: 2 route}RouteStates
        route route_stat_add 2 1
    end.
    if. aspect=0 do.
        detail =. (x{::TrainNames),' ',y{::SignalNames
        log_event 'SPAD ',detail
        3 safety_check detail
        TrainEmergency =: 1 x}TrainEmergency
    else.
        3 safety_check ''
    end.
)
move_train =: 4 : 0
    train =. x
    remaining =. y
    'section start' =. head_section train
    while. remaining>0 do.
        head =. train{TrainHeads
        if. _1~:train{TrainBoundary do.
            TrainHeads =: (head+remaining)train}TrainHeads
            break.
        end.
        end =. start+section{SectionLengths
        if. (head+remaining)<:end do.
            TrainHeads =: (head+remaining)train}TrainHeads
            break.
        end.
        remaining =. remaining-(end-head)
        TrainHeads =: end train}TrainHeads
        signal =. (<section,train{TrainDirections){SignalAt
        if. signal~:_1 do.
            train pass_signal signal
        end.
        index =. train{TrainAwaitingDeparture
        if. index~:_1 do.
            stops =. train{::TrainStops
            if. section=(<index,1){stops do.
                log_event 'DEPART ',(train{::TrainNames),' ',section{::SectionNames
                stops =. Time(<index,6)}stops
                TrainStops =: (<stops)train}TrainStops
                TrainAwaitingDeparture =: _1 train}TrainAwaitingDeparture
            end.
        end.
        'kind following' =. section beyond train{TrainDirections
        if. kind=3 do.
            TrainBoundary =: following train}TrainBoundary
            TrainBoundaryCoordinates =: end train}TrainBoundaryCoordinates
        else.
            section =. following
            start =. end
            path =. (train{::TrainPaths),section,start
            TrainPaths =: (<path)train}TrainPaths
        end.
    end.
)
after_movement =: 4 : 0
    train =. x
    'speed previous_speed' =. y
    TrainSpeeds =: speed train}TrainSpeeds
    TrainDistance =: ((train{TrainDistance)+speed)train}TrainDistance
    TrainRecordedMaximum =: (speed>.train{TrainRecordedMaximum)train}TrainRecordedMaximum
    if. speed=0 do.
        TrainEmergency =: 0 train}TrainEmergency
    end.
    'section start' =. head_section train
    stops =. train{::TrainStops
    index =. train{TrainStopIndices
    arrived =. 0
    if. (speed=0)*.index<#stops do.
        arrived =. (section=(<index,1){stops)*.(train{TrainHeads)=start+section{SectionLengths
    end.
    if. arrived do.
        TrainDwelling =: 1 train}TrainDwelling
        stops =. Time(<index,5)}stops
        TrainStops =: (<stops)train}TrainStops
        log_event 'ARRIVE ',(train{::TrainNames),' ',section{::SectionNames
    end.
    if. (speed=0)*.-.arrived do.
        TrainStanding =: ((train{TrainStanding)+1)train}TrainStanding
        if. previous_speed>0 do.
            log_event 'HOLD ',(train{::TrainNames),' ',section{::SectionNames
        end.
    end.
    boundary =. train{TrainBoundary
    if. boundary~:_1 do.
        if. ((train{TrainHeads)-train{TrainLengths)>:train{TrainBoundaryCoordinates do.
            TrainStates =: 2 train}TrainStates
            TrainExited =: Time train}TrainExited
            log_event 'EXIT ',(train{::TrainNames),' ',boundary{::BoundaryNames
        end.
    end.
)
run_trains =: 3 : 0
    EnteredBoundaries =: (#BoundaryNames)$0
    for_train. i.#TrainNames do.
        if. -.enter_train train do.
            continue.
        end.
        if. -.finish_dwell train do.
            continue.
        end.
        distance =. limit_distance train
        previous_speed =. train{TrainSpeeds
        speed =. train select_speed distance
        train move_train speed
        train after_movement speed,previous_speed
    end.
)
recompute_occupancy =: 3 : 0
    Occupants =: (#SectionNames)$<i.0
    for_train. i.#TrainNames do.
        for_part. occupied_parts train do.
            section =. 0{part
            occupants =. ~.(section{::Occupants),train
            Occupants =: (<occupants)section}Occupants
        end.
    end.
)
sectional_release =: 3 : 0
    for_route. I.RouteStates=2 do.
        sections =. route{::RouteSections
        remaining =. sections#~route=sections{SectionRouteLocks
        for_section. remaining do.
            if. occupied section do.
                RoutePassed =: 1(<route,section)}RoutePassed
            end.
        end.
        for_section. remaining do.
            if. (-.(<route,section){RoutePassed)+.occupied section do.
                break.
            end.
            route unlock_section section
            log_event 'RELEASE ',(route{::RouteNames),' ',section{::SectionNames
        end.
        if. -. +./route=sections{SectionRouteLocks do.
            release_route route
            log_event 'DONE ',route{::RouteNames
        elseif. (0<#route{::RouteOverlap)*.route{RouteOverlapLocked do.
            counter =. 0
            if. occupied {:sections do.
                counter =. 1+route{RouteOverlapCounters
            end.
            RouteOverlapCounters =: counter route}RouteOverlapCounters
            if. counter>:OverlapTime do.
                unlock_overlap route
                log_event 'OVERLAP ',route{::RouteNames
            end.
        end.
    end.
)
record_statistics =: 3 : 0
    for_route. I.RouteStates~:0 do.
        route route_stat_add 6 1
    end.
    PointLockedSeconds =: PointLockedSeconds+0<#&>PointLocks
    PointMovingSeconds =: PointMovingSeconds+PointMoving
    for_section. i.#SectionNames do.
        if. occupied section do.
            SectionOccupiedSeconds =: ((section{SectionOccupiedSeconds)+1)section}SectionOccupiedSeconds
        end.
        if. (_1~:section{SectionRouteLocks)+.+./section{SectionOverlapLocks do.
            SectionLockedSeconds =: ((section{SectionLockedSeconds)+1)section}SectionLockedSeconds
        end.
        seen =. ~.(section{::SectionTrains),section{::Occupants
        SectionTrains =: (<seen)section}SectionTrains
    end.
    for_signal. i.#SignalNames do.
        position =. <signal,signal{SignalAspects
        SignalSeconds =: (1+position{SignalSeconds)position}SignalSeconds
    end.
)

diagram =: 3 : 0
    grid =. (DiagramHeight*DiagramWidth)$' '
    for_label. Labels do.
        'row column text' =. >label
        positions =. (column+i.#text)+DiagramWidth*row
        grid =. text positions}grid
    end.
    for_section. i.#SectionNames do.
        character =. '-'
        if. section{SectionFailed do.
            character =. '#'
        elseif. _1~:section{SectionRouteLocks do.
            character =. '='
        elseif. +./section{SectionOverlapLocks do.
            character =. '~'
        end.
        first =. section{SectionFirst
        last =. section{SectionLast
        positions =. (first+i.1+last-first)+DiagramWidth*section{SectionRows
        grid =. character positions}grid
    end.
    for_train. i.#TrainNames do.
        for_part. occupied_parts train do.
            'section start low high' =. part
            length =. section{SectionLengths
            cells =. 1+(section{SectionLast)-section{SectionFirst
            if. 0=train{TrainDirections do.
                left =. low-start
                right =. high-start
            else.
                left =. length-(high-start)
                right =. length-(low-start)
            end.
            for_cell. i.cells do.
                if. ((left*cells)<(cell+1)*length)*.(right*cells)>cell*length do.
                    column =. (section{SectionFirst)+cell
                    position =. column+DiagramWidth*section{SectionRows
                    previous =. position{grid
                    if. (previous e.(97+i.26){a.)+.previous='*' do.
                        character =. '*'
                    else.
                        character =. train{TrainSymbols
                    end.
                    grid =. character position}grid
                end.
            end.
        end.
    end.
    for_buffer. i.#BufferNames do.
        position =. (buffer{BufferColumns)+DiagramWidth*buffer{BufferRows
        grid =. '|'position}grid
    end.
    for_point. i.#PointNames do.
        character =. '?'
        if. point_detected point do.
            character =. (point{PointPositions){'NR'
        end.
        position =. (point{PointColumns)+DiagramWidth*point{PointRows
        grid =. character position}grid
    end.
    for_signal. i.#SignalNames do.
        position =. (signal{SignalColumns)+DiagramWidth*signal{SignalRows
        grid =. ((signal{SignalAspects){'XYG')position}grid
    end.
    lines =. 0$a:
    for_row. (DiagramHeight,DiagramWidth)$grid do.
        last =. #row
        while. last>0 do.
            if. ' '~:(last-1){row do.
                break.
            end.
            last =. last-1
        end.
        lines =. lines,<last{.row
    end.
    lines
)
snapshot =: 3 : 0
    lines =. (<'SNAPSHOT ',integer Time),diagram ''
    for_train. I.TrainStates=1 do.
        line =. 'TRAIN ',(train{TrainSymbols),' ',(train{::TrainNames),' ',(train{TrainDirections){::DirectionNames
        line =. line,' ',integer train{TrainSpeeds
        sections =. 0{"1 occupied_parts train
        if. #sections do.
            line =. line,' ',','join sections{SectionNames
        end.
        lines =. lines,<line
    end.
    routes =. 0$a:
    for_route. I.RouteStates~:0 do.
        routes =. routes,<(route{::RouteNames),'/',(route{RouteStates){::RouteStateNames
    end.
    detail =. '-'
    if. #routes do.
        detail =. ' 'join routes
    end.
    lines,<'ROUTES ',detail
)
train_rows =: 3 : 0
    rows =. 0$a:
    for_train. i.#TrainNames do.
        name =. train{TrainNames
        location =. 'enter:',(train{TrainEntry){::BoundaryNames
        row =. name,(<location),(<train{TrainEntryTimes),<train{TrainEntered
        rows =. rows,<row
        for_stop. train{::TrainStops do.
            section =. (1{stop){::SectionNames
            row =. name,(<'arr:',section),(<3{stop),<5{stop
            rows =. rows,<row
            row =. name,(<'dep:',section),(<4{stop),<6{stop
            rows =. rows,<row
        end.
        location =. 'exit:',(train{TrainExit){::BoundaryNames
        row =. name,(<location),(<train{TrainExitTimes),<train{TrainExited
        rows =. rows,<row
    end.
    rows
)
train_report =: 3 : 0
    lines =. ,<'train,location,scheduled,actual,delay'
    for_row. y do.
        'name location scheduled actual' =. >row
        timing =. '-,-'
        if. actual~:_1 do.
            timing =. (integer actual),',',integer actual-scheduled
        end.
        lines =. lines,<name,',',location,',',(integer scheduled),',',timing
    end.
    lines
)
punctuality =: 3 : 0
    on_time =. 0
    late =. 0
    missing =. 0
    total_delay =. 0
    maximum =. 0
    for_row. y do.
        'name location scheduled actual' =. >row
        if. actual=_1 do.
            missing =. missing+1
            continue.
        end.
        delay =. actual-scheduled
        if. delay<:0 do.
            on_time =. on_time+1
        else.
            late =. late+1
            total_delay =. total_delay+delay
            maximum =. maximum>.delay
        end.
    end.
    line =. 'PUNCTUALITY on_time ',(integer on_time),' late ',(integer late),' missing ',integer missing
    line,' total_delay ',(integer total_delay),' max_delay ',integer maximum
)
paired_counts =: 4 : 0
    parts =. 0$a:
    for_i. i.#x do.
        parts =. parts,<(i{::x),' ',integer i{y
    end.
    ' 'join parts
)
summary =: 3 : 0
    lines =. 0$a:
    for_route. i.#RouteNames do.
        line =. 'ROUTE ',(route{::RouteNames),' ',(route{RouteStarts){::SignalNames
        line =. line,'-',(route{::RouteFinishNames),' ',(;:'requests grants uses cancels wait maxwait locked')paired_counts route{RouteStats
        lines =. lines,<line
    end.
    for_point. i.#PointNames do.
        final =. '?'
        if. point_detected point do.
            final =. (point{PointPositions){'NR'
        end.
        line =. 'POINT ',(point{::PointNames),' throws ',(integer point{PointThrows),' locked ',integer point{PointLockedSeconds
        lines =. lines,<line,' moving ',(integer point{PointMovingSeconds),' final ',final
    end.
    for_section. i.#SectionNames do.
        line =. 'SECTION ',(section{::SectionNames),' occupied ',(integer section{SectionOccupiedSeconds),' locked ',integer section{SectionLockedSeconds
        lines =. lines,<line,' trains ',integer #section{::SectionTrains
    end.
    for_signal. i.#SignalNames do.
        line =. 'SIGNAL ',(signal{::SignalNames),' ',(;:'red yellow green')paired_counts signal{SignalSeconds
        lines =. lines,<line,' passes ',integer signal{SignalPasses
    end.
    for_train. i.#TrainNames do.
        line =. 'TRAIN ',(train{::TrainNames),' ',(train{TrainSymbols),' ',(train{TrainStates){::StateNames
        line =. line,' distance ',(integer train{TrainDistance),' maxspeed ',integer train{TrainRecordedMaximum
        lines =. lines,<line,' standing ',(integer train{TrainStanding),' passes ',integer train{TrainPasses
    end.
    line =. 'TRAINS total ',(integer #TrainNames),' exited ',(integer +/TrainStates=2),' running ',integer +/TrainStates=1
    lines =. lines,<line,' waiting ',integer +/TrainStates=0
    lines =. lines,<punctuality y
    line =. 'REQUESTS total ',(integer #QRoutes),' granted ',(integer +/1{"1 RouteStats),' dropped ',integer Dropped
    lines,<line,' pending ',integer +/QActive
)
write_lines =: 4 : 0
    text =. ''
    if. #y do.
        text =. (LF join y),LF
    end.
    text 1!:2 <'output/',x
)
run =: 3 : 0
    read_layout ''
    read_routes ''
    read_trains ''
    read_settings ''
    for_time. i.EndTime+1 do.
        Time =: time
        complete_throws ''
        release_approaches ''
        for_request. PlannedRequests#~Time=0{"1 PlannedRequests do.
            'requested train route' =. request
            route add_request train{::TrainNames
        end.
        execute_events ''
        judge_requests ''
        decide_signals ''
        run_trains ''
        recompute_occupancy ''
        sectional_release ''
        inspect_safety ''
        record_statistics ''
        if. Time e.SnapshotTimes do.
            Snapshots =: Snapshots,snapshot ''
        end.
    end.
    rows =. train_rows ''
    try.
        1!:5 <'output'
    catch.
    end.
    'events.txt'write_lines EventLog
    'snapshots.txt'write_lines Snapshots
    'train_log.csv'write_lines train_report rows
    'safety.txt'write_lines safety_report ''
    'summary.txt'write_lines summary rows
)
run ''
