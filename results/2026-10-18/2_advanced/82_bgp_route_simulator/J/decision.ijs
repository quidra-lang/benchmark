originated_route =: 3 : 0
    'origin communities' =. y
    (<i.0),(<origin),(<0),(<communities),(<_1),<_1
)
local_route =: 3 : '_1=5{::y'
best_route =: 3 : 0
    remaining =. y
    if. 1=#remaining do.
        (0{remaining),<'ONLY' return.
    end.
    reasons =. ;:'LOCALPREF ASPATH ORIGIN MED ROUTERID LINK'
    for_stage. i.6 do.
        if. stage=3 do.
            keep =. (#remaining)$1
            for_i. i.#remaining do.
                route =. i{::remaining
                neighbor =. {.0{::route
                med =. 2{::route
                for_other. remaining do.
                    other =. >other
                    if. (neighbor={.0{::other)*.(2{::other)<med do.
                        keep =. 0 i}keep
                        break.
                    end.
                end.
            end.
            remaining =. remaining#~keep
        else.
            keys =. i.0
            for_route. remaining do.
                route =. >route
                select. stage
                case. 0 do. key =. -4{::route
                case. 1 do. key =. #0{::route
                case. 2 do. key =. 1{::route
                case. 4 do. key =. (ASNumbers i.{.0{::route){RouterIds
                case. 5 do. key =. 5{::route
                end.
                keys =. keys,key
            end.
            remaining =. remaining#~keys=<./keys
        end.
        if. 1=#remaining do.
            (0{remaining),stage{reasons return.
        end.
    end.
)
