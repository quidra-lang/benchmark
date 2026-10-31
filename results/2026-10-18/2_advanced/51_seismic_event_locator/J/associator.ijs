associate =: 4 : 0
    'window minimum station_count' =. x
    picks =. y
    assigned =. (#picks)$0
    candidates =. 0$a:
    for_index. i.#picks do.
        if. index{assigned do.
            continue.
        end.
        selected =. i.0
        stations =. station_count$0
        for_current. index+i.(#picks)-index do.
            pick =. current{picks
            if. (1{pick)>(1{index{picks)+window do.
                break.
            end.
            station =. 0{pick
            if. (-.current{assigned)*.-.station{stations do.
                selected =. selected,current
                stations =. 1 station}stations
            end.
        end.
        if. (#selected)>:minimum do.
            assigned =. 1 selected}assigned
            candidates =. candidates,<selected
        end.
    end.
    candidates
)
