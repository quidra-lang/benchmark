power_iteration =: 4 : 0
    'teleport damping iterations tolerance' =. y
    count =. #x
    weight =. count$0
    for_group. x do.
        for_edge. >group do.
            'source value' =. edge
            weight =. (value+source{weight) source}weight
        end.
    end.
    dangling =. I.weight=0
    inteleport =. (i.count)e.teleport
    size =. #teleport
    values =. inteleport%size
    changes =. 0$0.0
    converged =. 0
    for_step. 1+i.iterations do.
        mass =. ordered_sum dangling{values
        base =. ((1-damping)+damping*mass)%size
        updated =. count$0.0
        for_node. i.count do.
            inflow =. 0.0
            for_edge. node{::x do.
                'source value' =. edge
                inflow =. inflow+((source{values)*value)%source{weight
            end.
            updated =. ((damping*inflow)+(node{inteleport)*base) node}updated
        end.
        change =. ordered_sum |updated-values
        changes =. changes,change
        if. (converged=0)*.change<tolerance do. converged =. step end.
        values =. updated
    end.
    (<values),(<changes),<converged
)
