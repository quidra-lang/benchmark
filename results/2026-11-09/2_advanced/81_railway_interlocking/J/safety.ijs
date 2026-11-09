SafetyProperties =: ;:'OCCUPANCY POINT_MOTION CONFLICT SIGNAL_PASSING'
initialize_safety =: 3 : 0
    SafetyChecks =: 4$0
    SafetyViolations =: 4$0
    SafetyRecords =: 0$a:
)
safety_check =: 4 : 0
    SafetyChecks =: ((x{SafetyChecks)+1)x}SafetyChecks
    if. #y do.
        SafetyViolations =: ((x{SafetyViolations)+1)x}SafetyViolations
        SafetyRecords =: SafetyRecords,<'VIOLATION ',(integer Time),' ',(x{::SafetyProperties),' ',y
    end.
)
inspect_safety =: 3 : 0
    for_section. i.#SectionNames do.
        occupants =. section{::Occupants
        detail =. ''
        if. 2<:#occupants do.
            detail =. (section{::SectionNames),' ',','join occupants{TrainNames
        end.
        0 safety_check detail
    end.
    for_point. I.PointMoving do.
        detail =. ''
        if. # (point{PointCommon){::Occupants do.
            detail =. (point{::PointNames),' occupied'
        else.
            locks =. point{::PointLocks
            if. +./(0{"1 locks){RouteStates e.2 3 do.
                detail =. (point{::PointNames),' locked'
            end.
        end.
        1 safety_check detail
    end.
    active =. I.RouteStates e.1 3
    for_i. i.#active do.
        first =. i{active
        for_second. (i+1)}.active do.
            detail =. ''
            if. (second e.first{::RouteConflicts)+.first e.second{::RouteConflicts do.
                detail =. (first{::RouteNames),' ',second{::RouteNames
            end.
            2 safety_check detail
        end.
    end.
)
safety_report =: 3 : 0
    lines =. 0$a:
    for_i. i.4 do.
        verdict =. (0~:i{SafetyViolations){::'OK';'FAIL'
        line =. (i{::SafetyProperties),' ',verdict,' checks ',(integer i{SafetyChecks),' violations ',integer i{SafetyViolations
        lines =. lines,<line
    end.
    verdict =. (0<#SafetyRecords){::'SAFE';'UNSAFE'
    lines,SafetyRecords,<'RESULT ',verdict
)
