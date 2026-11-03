name_list =: 3 : 0
    if. (,y)-:,'-' do.
        0$a:
    else.
        split_commas y
    end.
)
point_requirements =: 3 : 0
    result =. 0 2$0
    for_item. name_list y do.
        item =. >item
        colon =. item i.':'
        point =. PointNames i.<colon{.item
        position =. 'R'={:item
        result =. result,point,position
    end.
    result
)
read_routes =: 3 : 0
    lines =. read_lines 'input/routes.txt'
    RouteNames =: 0$a:
    for_line. lines do.
        RouteNames =: RouteNames,1{split_words >line
    end.
    RouteStarts =: i.0
    RouteFinishNames =: 0$a:
    RouteFinishKinds =: i.0
    RouteFinishes =: i.0
    RouteRequirements =: 0$a:
    RouteSections =: 0$a:
    RouteOverlap =: 0$a:
    RouteConflicts =: 0$a:
    RouteApproachTimes =: i.0
    for_line. lines do.
        fields =. split_words >line
        start =. SignalNames i.2{fields
        finish =. 3{::fields
        RouteStarts =: RouteStarts,start
        RouteFinishNames =: RouteFinishNames,<finish
        if. (<finish)e.SignalNames do.
            kind =. 0
            index =. SignalNames i.<finish
        elseif. (<finish)e.BufferNames do.
            kind =. 1
            index =. BufferNames i.<finish
        else.
            kind =. 2
            index =. BoundaryNames i.<finish
        end.
        RouteFinishKinds =: RouteFinishKinds,kind
        RouteFinishes =: RouteFinishes,index
        requirements =. (point_requirements 4{::fields),point_requirements 7{::fields
        RouteRequirements =: RouteRequirements,<requirements
        RouteSections =: RouteSections,<SectionNames i.name_list 5{::fields
        RouteOverlap =: RouteOverlap,<SectionNames i.name_list 6{::fields
        RouteConflicts =: RouteConflicts,<RouteNames i.name_list 8{::fields
        RouteApproachTimes =: RouteApproachTimes,".9{::fields
    end.
    count =. #RouteNames
    RouteDirections =: RouteStarts{SignalDirections
    RouteStates =: count$0
    RouteReleaseTimes =: count$_1
    RoutePassed =: (count,#SectionNames)$0
    RouteOverlapLocked =: count$0
    RouteOverlapCounters =: count$0
    RouteStats =: (count,7)$0
    SectionRouteLocks =: (#SectionNames)$_1
    SectionOverlapLocks =: ((#SectionNames),count)$0
    PointLocks =: (#PointNames)$<0 2$0
)
lock_route =: 3 : 0
    RouteStates =: 1 y}RouteStates
    RouteReleaseTimes =: _1 y}RouteReleaseTimes
    RoutePassed =: ((#SectionNames)$0)y}RoutePassed
    RouteOverlapLocked =: 1 y}RouteOverlapLocked
    RouteOverlapCounters =: 0 y}RouteOverlapCounters
    SectionRouteLocks =: y(y{::RouteSections)}SectionRouteLocks
    for_section. y{::RouteOverlap do.
        SectionOverlapLocks =: 1(<section,y)}SectionOverlapLocks
    end.
    for_requirement. y{::RouteRequirements do.
        'point position' =. requirement
        locks =. ~.(point{::PointLocks),y,position
        PointLocks =: (<locks)point}PointLocks
    end.
)
unlock_points =: 4 : 0
    for_point. i.#PointNames do.
        if. (0=#y)+.(point{PointCommon)e.y do.
            locks =. point{::PointLocks
            locks =. locks#~x~:0{"1 locks
            PointLocks =: (<locks)point}PointLocks
        end.
    end.
)
unlock_section =: 4 : 0
    if. x=y{SectionRouteLocks do.
        SectionRouteLocks =: _1 y}SectionRouteLocks
    end.
    x unlock_points ,y
)
unlock_overlap =: 3 : 0
    for_section. y{::RouteOverlap do.
        SectionOverlapLocks =: 0(<section,y)}SectionOverlapLocks
    end.
    sections =. y{::RouteOverlap
    if. #sections do.
        y unlock_points sections
    end.
    RouteOverlapLocked =: 0 y}RouteOverlapLocked
)
release_route =: 3 : 0
    for_section. y{::RouteSections do.
        if. y=section{SectionRouteLocks do.
            SectionRouteLocks =: _1 section}SectionRouteLocks
        end.
    end.
    if. y{RouteOverlapLocked do.
        unlock_overlap y
    end.
    y unlock_points i.0
    RouteStates =: 0 y}RouteStates
    RouteReleaseTimes =: _1 y}RouteReleaseTimes
)
