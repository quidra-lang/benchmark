make_graph =: 4 : 0
    sequences =. (<x),<y
    slots_a =. 0$a:
    slots_b =. 0$a:
    for_ring. x do.
        slots_a =. slots_a,< (#>ring)$<i.0
    end.
    for_ring. y do.
        slots_b =. slots_b,< (#>ring)$<i.0
    end.
    cross_points =. 0 2$0x
    positions =. 0 2$0x
    for_ra. i.#x do.
        first =. ra{::x
        for_ea. i.#first do.
            segment_a =. (ea{first),:((#first)|ea+1){first
            for_rb. i.#y do.
                second =. rb{::y
                for_eb. i.#second do.
                    segment_b =. (eb{second),:((#second)|eb+1){second
                    found =. crossing segment_a,segment_b
                    if. 0=#found do.
                        continue.
                    end.
                    't u point' =. found
                    number =. #cross_points
                    cross_points =. cross_points,point
                    positions =. positions,t,u
                    entries =. ra{::slots_a
                    entries =. (<(ea{::entries),number)ea}entries
                    slots_a =. (<entries)ra}slots_a
                    entries =. rb{::slots_b
                    entries =. (<(eb{::entries),number)eb}entries
                    slots_b =. (<entries)rb}slots_b
                end.
            end.
        end.
    end.
    slots =. (<slots_a),<slots_b
    pairs =. ((#cross_points),2)$_1
    points =. 0 2$0x
    sides =. i.0
    ids =. i.0
    next =. i.0
    previous =. i.0
    other =. i.0
    entering =. i.0
    ring_nodes =. 0$a:
    initial_inside =. 0$a:
    order =. i.0
    for_side. i.2 do.
        sequence =. side{::sequences
        opposite =. (1-side){::sequences
        nodes_by_ring =. 0$a:
        states =. i.0
        for_ri. i.#sequence do.
            ring =. ri{::sequence
            entries =. ri{::side{::slots
            nodes =. i.0
            for_edge. i.#ring do.
                nodes =. nodes,#points
                points =. points,edge{ring
                sides =. sides,side
                ids =. ids,_1
                next =. next,_1
                previous =. previous,_1
                other =. other,_1
                entering =. entering,0
                inserted =. edge{::entries
                keys =. side{"1 inserted{positions
                for_number. (/:keys){inserted do.
                    node =. #points
                    nodes =. nodes,node
                    points =. points,number{cross_points
                    sides =. sides,side
                    ids =. ids,number
                    next =. next,_1
                    previous =. previous,_1
                    other =. other,_1
                    entering =. entering,0
                    pairs =. node(<number,side)}pairs
                    if. side=0 do.
                        order =. order,node
                    end.
                end.
            end.
            next =. (1|.nodes)nodes}next
            previous =. (_1|.nodes)nodes}previous
            state =. opposite interior 0{ring
            states =. states,state
            for_node. nodes do.
                if. _1~:node{ids do.
                    entering =. (-.state)node}entering
                    state =. -.state
                end.
            end.
            nodes_by_ring =. nodes_by_ring,<nodes
        end.
        ring_nodes =. ring_nodes,<nodes_by_ring
        initial_inside =. initial_inside,<states
    end.
    for_pair. pairs do.
        'a b' =. pair
        other =. b a}other
        other =. a b}other
    end.
    result =. (<points),(<sides),(<ids),(<next),(<previous),(<other),(<entering),(<order)
    result,(<ring_nodes),(<initial_inside),<sequences
)
traverse_graph =: 4 : 0
    'points sides ids next previous other entering order ring_nodes initial_inside sequences' =. x
    inverted =. y
    visited =. (#order)$0
    result =. 0$a:
    for_start. order do.
        start_id =. start{ids
        if. start_id{visited do.
            continue.
        end.
        ring =. 0 2$0x
        current =. start
        while. 1 do.
            visited =. 1(current{ids)}visited
            ring =. ring,current{points
            forward =. (current{entering)~:(current{sides){inverted
            if. forward do.
                stopped =. current{next
            else.
                stopped =. current{previous
            end.
            while. _1=stopped{ids do.
                ring =. ring,stopped{points
                if. forward do.
                    stopped =. stopped{next
                else.
                    stopped =. stopped{previous
                end.
            end.
            if. start_id=stopped{ids do.
                break.
            end.
            current =. stopped{other
        end.
        result =. result,<ring
    end.
    for_side. i.2 do.
        sequence =. side{::sequences
        for_index. i.#sequence do.
            nodes =. index{::side{::ring_nodes
            if. +./_1~:nodes{ids do.
                continue.
            end.
            state =. index{side{::initial_inside
            if. state~:side{inverted do.
                result =. result,index{sequence
            end.
        end.
    end.
    result
)
