quad_store =: 4 : 'QuadNodes =: (<y)x}QuadNodes'
quad_destination =: 4 : 0
    'origin_x origin_y size' =. 0{::x{::QuadNodes
    half =. size intdiv 2
    ((1{y)>:origin_x+half)+2*(2{y)>:origin_y+half
)
quad_insert =: 3 : 0
    current =. 0
    while. #2{::current{::QuadNodes do.
        child =. current quad_destination y
        current =. child{2{::current{::QuadNodes
    end.
    'square points children' =. current{::QuadNodes
    points =. points,y
    points =. points /: 0{"1 points
    current quad_store (<square),(<points),<children
    pending =. ,current
    while. #pending do.
        index =. {:pending
        pending =. }:pending
        'square points children' =. index{::QuadNodes
        if. (#points)<:QuadCapacity do.
            continue.
        end.
        'origin_x origin_y size' =. square
        half =. size intdiv 2
        first =. #QuadNodes
        children =. first+i.4
        squares =. (origin_x,origin_y,half),:(origin_x+half),origin_y,half
        squares =. squares,(origin_x,(origin_y+half),half),:(origin_x+half),(origin_y+half),half
        for_child_square. squares do.
            QuadNodes =: QuadNodes,<(<child_square),(<0 3$0x),<i.0
        end.
        index quad_store (<square),(<0 3$0x),<children
        for_point. points do.
            child =. first+index quad_destination point
            record =. child{::QuadNodes
            held =. (1{::record),point
            child quad_store (<held)1}record
        end.
        for_child. |.children do.
            if. (#1{::child{::QuadNodes)>QuadCapacity do.
                pending =. pending,child
            end.
        end.
    end.
    i.0
)
quad_build =: 4 : 0
    'world QuadCapacity' =: x
    QuadNodes =: ,<(<0,0,world),(<0 3$0x),<i.0
    for_point. y do.
        quad_insert point
    end.
    i.0
)
quad_delete =: 3 : 0
    current =. 0
    ancestors =. i.0
    while. #2{::current{::QuadNodes do.
        ancestors =. ancestors,current
        child =. current quad_destination y
        current =. child{2{::current{::QuadNodes
    end.
    record =. current{::QuadNodes
    held =. 1{::record
    held =. held#~(0{"1 held)~:0{y
    current quad_store (<held)1}record
    for_index. |.ancestors do.
        record =. index{::QuadNodes
        children =. 2{::record
        held =. 0 3$0x
        merge =. 1
        for_child. children do.
            child_record =. child{::QuadNodes
            if. #2{::child_record do.
                merge =. 0
                break.
            end.
            held =. held,1{::child_record
        end.
        if. (-.merge)+.(#held)>QuadCapacity do.
            break.
        end.
        held =. held /: 0{"1 held
        index quad_store (0{record),(<held),<i.0
    end.
    i.0
)
