load_rooms =: 3 : 0
    ids =. 0$a:
    capacities =. 0$0
    records =. read_records 'rooms.csv'
    for_index. i.#records do.
        fields =. index{::records
        id =. 0{::fields
        capacity =. num 1{::fields
        if. (<id)e.ids do.
            Errors =: Errors,<'rooms.csv line |: duplicate room |' format (<index+2),<id
        elseif. capacity<1 do.
            Errors =: Errors,<'rooms.csv line |: bad capacity |' format (<index+2),<1{::fields
        else.
            ids =. ids,<id
            capacities =. capacities,capacity
        end.
    end.
    ascii =. ascii_order ids
    order =. ascii{~/:ascii{capacities
    RoomIds =: order{ids
    Capacities =: order{capacities
    RoomCount =: #RoomIds
    i.0
)
pack =: 3 : 0
    remaining =. Capacities
    durations =. RoomCount$0
    placed =. 0 4$0
    for_course. by_size y do.
        size =. course{Sizes
        duration =. course{Durations
        fits =. I.(remaining>:size)*.((durations=0)+.durations=duration)
        if. 0=#fits do. _1 return. end.
        room =. {.fits
        first =. 1+(room{Capacities)-room{remaining
        placed =. placed,course,room,first,(first+size)-1
        remaining =. ((room{remaining)-size) room}remaining
        durations =. duration room}durations
    end.
    placed
)
