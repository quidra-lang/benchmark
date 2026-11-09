Directions =: 4 2$0 _1 1 0 0 1 _1 0
neighbor =: 4 : 'x+y{Directions'
distance_field =: 3 : 0
    dist =. (Width*Height)$_1
    exit =. grid_index Exit
    dist =. 0 exit}dist
    queue =. ,exit
    head =. 0
    while. head<#queue do.
        index =. head{queue
        head =. head+1
        cell =. cell_of_index index
        for_direction. i.4 do.
            next =. cell neighbor direction
            if. -.grid_inside next do. continue. end.
            next_index =. grid_index next
            if. (grid_rock next)+.(next_index{y)+.0<:next_index{dist do. continue. end.
            dist =. (1+index{dist)next_index}dist
            queue =. queue,next_index
        end.
    end.
    dist
)
field_at =: 4 : '(grid_index y){x'
field_direction =: 4 : 0
    best =. _1
    best_dist =. 0
    for_direction. i.4 do.
        next =. y neighbor direction
        if. -.grid_inside next do. continue. end.
        value =. x field_at next
        if. value<0 do. continue. end.
        if. (best<0)+.value<best_dist do. best =. direction
            best_dist =. value end.
    end.
    best
)
next_cell =: 4 : 'y neighbor x field_direction y'
field_path =: 4 : 0
    path =. ,grid_index y
    while. -.y-:Exit do.
        y =. x next_cell y
        path =. path,grid_index y
    end.
    path
)
