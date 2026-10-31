decide_aspects =: 3 : 0
    cleared =. (#SignalNames)$_1
    for_route. I.RouteStates=1 do.
        valid =. 1
        for_requirement. route{::RouteRequirements do.
            'point position' =. requirement
            valid =. valid*.(point_detected point)*.position=point{PointPositions
        end.
        sections =. (route{::RouteSections),route{::RouteOverlap
        for_section. sections do.
            valid =. valid*.-.occupied section
        end.
        if. valid do.
            cleared =. route(route{RouteStarts)}cleared
        end.
    end.
    result =. (#SignalNames)$0
    for_signal. i.#SignalNames do.
        route =. signal{cleared
        if. route=_1 do.
            continue.
        end.
        kind =. route{RouteFinishKinds
        if. kind=0 do.
            aspect =. 1+_1~:(route{RouteFinishes){cleared
        elseif. kind=1 do.
            aspect =. 1
        else.
            aspect =. 2
        end.
        result =. aspect signal}result
    end.
    result
)
