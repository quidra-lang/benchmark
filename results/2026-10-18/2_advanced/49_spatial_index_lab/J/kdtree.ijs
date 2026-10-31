kd_less =: 4 : 0
    keys =. ((1+x),(2-x),0){"1 y
    different =. I.(0{keys)~:1{keys
    if. 0=#different do.
        0
    else.
        column =. {.different
        (column{0{keys)<column{1{keys
    end.
)
kd_build_subtree =: 4 : 0
    if. 0=#y do.
        _1 return.
    end.
    axis =. 2|x
    ordered =. y /: ((1+axis),(2-axis),0){"1 y
    middle =. (#ordered)intdiv 2
    index =. #KDNodes
    KDNodes =: KDNodes,(middle{ordered),axis,_1,_1
    left =. (x+1)kd_build_subtree middle{.ordered
    right =. (x+1)kd_build_subtree (middle+1)}.ordered
    KDNodes =: left (<index,4)}KDNodes
    KDNodes =: right (<index,5)}KDNodes
    index
)
kd_build =: 3 : 0
    KDNodes =: 0 6$0x
    KDRoot =: 0 kd_build_subtree y
    i.0
)
kd_insert =: 3 : 0
    current =. KDRoot
    if. current<0 do.
        KDRoot =: #KDNodes
        KDNodes =: KDNodes,y,0,_1,_1
        i.0 return.
    end.
    while. 1 do.
        node =. current{KDNodes
        axis =. 3{node
        left =. axis kd_less y,:3{.node
        column =. 5-left
        child =. column{node
        if. child<0 do.
            index =. #KDNodes
            KDNodes =: KDNodes,y,(1-axis),_1,_1
            KDNodes =: index (<current,column)}KDNodes
            i.0 return.
        end.
        current =. child
    end.
)
kd_minimum =: 4 : 0
    pending =. ,y
    best =. i.0
    while. #pending do.
        current =. {:pending
        pending =. }:pending
        node =. current{KDNodes
        if. (x=3{node)*.(4{node)>:0 do.
            pending =. pending,4{node
        else.
            point =. 3{.node
            if. 0=#best do.
                best =. point
            elseif. x kd_less point,:best do.
                best =. point
            end.
            if. x~:3{node do.
                children =. 5 4{node
                pending =. pending,children#~children>:0
            end.
        end.
    end.
    best
)
kd_delete =: 3 : 0
    point =. y
    current =. KDRoot
    parent =. _1
    column =. 4
    while. current>:0 do.
        node =. current{KDNodes
        if. (0{node)~:0{point do.
            parent =. current
            column =. 5-(3{node)kd_less point,:3{.node
            current =. column{node
        elseif. (5{node)>:0 do.
            point =. (3{node)kd_minimum 5{node
            KDNodes =: (point,3}.node)current}KDNodes
            parent =. current
            column =. 5
            current =. 5{node
        elseif. (4{node)>:0 do.
            point =. (3{node)kd_minimum 4{node
            KDNodes =: (point,(3{node),_1,4{node)current}KDNodes
            parent =. current
            column =. 5
            current =. 4{node
        else.
            if. parent<0 do.
                KDRoot =: _1
            else.
                KDNodes =: _1 (<parent,column)}KDNodes
            end.
            i.0 return.
        end.
    end.
)
