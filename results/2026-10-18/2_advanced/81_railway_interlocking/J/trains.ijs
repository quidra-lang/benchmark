read_trains =: 3 : 0
    lines =. read_lines 'input/trains.txt'
    TrainNames =: 0$a:
    TrainLengths =: i.0
    TrainAcceleration =: i.0
    TrainDeceleration =: i.0
    TrainMaximum =: i.0
    TrainEntry =: i.0
    TrainEntryTimes =: i.0
    TrainEntrySpeed =: i.0
    for_line. lines do.
        fields =. split_words >line
        if. 'TRAIN'-:0{::fields do.
            TrainNames =: TrainNames,1{fields
            'length acceleration deceleration maximum' =. ".' 'join 4{.2}.fields
            TrainLengths =: TrainLengths,length
            TrainAcceleration =: TrainAcceleration,acceleration
            TrainDeceleration =: TrainDeceleration,deceleration
            TrainMaximum =: TrainMaximum,maximum
            TrainEntry =: TrainEntry,BoundaryNames i.6{fields
            TrainEntryTimes =: TrainEntryTimes,".7{::fields
            TrainEntrySpeed =: TrainEntrySpeed,".8{::fields
        end.
    end.
    count =. #TrainNames
    TrainStops =: count$<0 7$0
    TrainExit =: count$_1
    TrainExitTimes =: count$_1
    PlannedRequests =: 0 3$0
    for_line. lines do.
        fields =. split_words >line
        kind =. 0{::fields
        if. kind-:'TRAIN' do.
            continue.
        end.
        train =. TrainNames i.1{fields
        select. kind
        case. 'REQUEST' do.
            time =. ".3{::fields
            route =. RouteNames i.2{fields
            PlannedRequests =: PlannedRequests,time,train,route
        case. 'STOP';'TURN' do.
            section =. SectionNames i.2{fields
            'dwell arrival departure' =. ".' 'join 3}.fields
            stop =. (kind-:'TURN'),section,dwell,arrival,departure,_1,_1
            TrainStops =: (<(train{::TrainStops),stop)train}TrainStops
        case. 'EXIT' do.
            TrainExit =: (BoundaryNames i.2{fields)train}TrainExit
            TrainExitTimes =: (".3{::fields)train}TrainExitTimes
        end.
    end.
    TrainStates =: count$0
    TrainDirections =: count$0
    TrainPaths =: count$<0 2$0
    TrainHeads =: count$0
    TrainSpeeds =: count$0
    TrainStopIndices =: count$0
    TrainDwelling =: count$0
    TrainAwaitingDeparture =: count$_1
    TrainEmergency =: count$0
    TrainBoundary =: count$_1
    TrainBoundaryCoordinates =: count$0
    TrainEntered =: count$_1
    TrainExited =: count$_1
    TrainDistance =: count$0
    TrainRecordedMaximum =: count$0
    TrainStanding =: count$0
    TrainPasses =: count$0
    TrainSymbols =: (97+i.count){a.
)
braking_distance =: 4 : 0
    count =. y intdiv x
    (count*y)-(x*count*(count+1))intdiv 2
)
select_speed =: 4 : 0
    low =. 0>.(x{TrainSpeeds)-x{TrainDeceleration
    if. -.x{TrainEmergency do.
        high =. (x{TrainMaximum)<.(x{TrainSpeeds)+x{TrainAcceleration
        for_speed. high-i.1+high-low do.
            if. y=_1 do.
                speed return.
            end.
            if. y>:speed+(x{TrainDeceleration)braking_distance speed do.
                speed return.
            end.
        end.
    end.
    low
)
