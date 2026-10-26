instance_sequence =: 3 : 0
    instances =. 0 2$0
    keys =. 0 2$0
    for_index. y do.
        rule =. index{::Rules
        from =. 3{::rule
        to =. 4{::rule
        month =. 5{::rule
        for_year. from+i.1+to-from do.
            nominal =. (DaySeconds*(6{::rule)day_value year,month)+7{::rule
            instances =. instances,nominal,index
            keys =. keys,nominal,0{::rule
        end.
    end.
    (/:keys){instances
)
adjustment =: 3 : 0
    'kind offset save' =. y
    if. kind-:'u' do. 0
    elseif. kind-:'s' do. offset
    else. offset+save end.
)
run_instances =: 4 : 0
    'offset start until' =. y
    pre =. 0$0
    applied =. 0 2$0
    ending =. PositiveInfinity
    save =. 0
    for_instance. x do.
        'nominal index' =. instance
        rule =. index{::Rules
        time =. nominal-adjustment (8{rule),(<offset),<save
        if. #until do.
            limit =. (5{::until)-adjustment (4{until),(<offset),<save
            if. time>:limit do. break. end.
        end.
        if. time<:start do. pre =. pre,index
        else. applied =. applied,time,index end.
        save =. 9{::rule
    end.
    if. #until do. ending =. (5{::until)-adjustment (4{until),(<offset),<save end.
    (<pre),(<applied),<ending
)
abbreviation =: 4 : 0
    'save letter' =. y
    slash =. x i.'/'
    if. slash<#x do.
        if. save=0 do. slash{.x else. (slash+1)}.x end.
    else.
        position =. I.'%s'E.x
        if. #position do.
            position =. {.position
            (position{.x),letter,(position+2)}.x
        else. x end.
    end.
)
