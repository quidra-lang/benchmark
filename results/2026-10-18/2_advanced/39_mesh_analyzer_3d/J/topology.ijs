directed =: 3 : '3 2$(0 1 1 2 2 0{y)'
edge_index =: 4 : 0
    pair =. /:~y
    matches =. pair-:"1 x
    if. 1 e.matches do.
        matches i.1
    else.
        #x
    end.
)
connected =: 4 : 0
    selected =. x
    neighbors =. y
    visited =. (#neighbors)$0
    parts =. 0$a:
    for_seed. selected do.
        if. (seed-1){visited do.
            continue.
        end.
        visited =. 1 (seed-1)}visited
        queue =. ,seed
        head =. 0
        while. head<#queue do.
            current =. head{queue
            head =. head+1
            for_other. (current-1){::neighbors do.
                if. -.(other-1){visited do.
                    visited =. 1 (other-1)}visited
                    queue =. queue,other
                end.
            end.
        end.
        parts =. parts,</:~queue
    end.
    parts
)
mesh_edges =: 0&{::
mesh_edge_faces =: 1&{::
mesh_face_components =: 2&{::
mesh_components =: 3&{::
mesh_vertices =: 4&{::
mesh_component_edges =: 5&{::
mesh_boundary =: 6&{::
mesh_nonmanifold =: 7&{::
mesh_bad_vertices =: 8&{::
mesh_fans =: 9&{::
mesh_global_bad =: 10&{::
mesh_used =: 11&{::
analyze_mesh =: 3 : 0
    'faces vertex_count' =. y
    edges =. 0 2$0x
    edge_faces =. 0$a:
    used =. /:~~.,3{."1 faces
    for_id. i.#faces do.
        for_pair. directed id{faces do.
            pair =. /:~pair
            index =. edges edge_index pair
            if. index=#edges do.
                edges =. edges,pair
                edge_faces =. edge_faces,<i.0
            end.
            edge_faces =. (<(index{::edge_faces),id+1)index}edge_faces
        end.
    end.
    order =. /:edges
    edges =. order{edges
    edge_faces =. order{edge_faces
    neighbors =. (#faces)$<i.0
    for_box. edge_faces do.
        adjacent =. >box
        for_first. adjacent do.
            row =. (first-1){::neighbors
            row =. /:~~.row,adjacent-.first
            neighbors =. (<row)(first-1)}neighbors
        end.
    end.
    component_faces =. (1+i.#faces)connected neighbors
    face_components =. (#faces)$0
    component_vertices =. 0$a:
    component_edges =. (#component_faces)$<i.0
    boundary =. component_edges
    nonmanifold =. component_edges
    bad_vertices =. component_edges
    for_number. i.#component_faces do.
        ids =. number{::component_faces
        face_components =. (number+1)(ids-1)}face_components
        vertices =. /:~~.,3{."1 (ids-1){faces
        component_vertices =. component_vertices,<vertices
    end.
    for_index. i.#edges do.
        number =. (((0{index{::edge_faces)-1){face_components)-1
        component_edges =. (<(number{::component_edges),index)number}component_edges
        count =. #index{::edge_faces
        if. count=1 do.
            boundary =. (<(number{::boundary),index)number}boundary
        elseif. count>:3 do.
            nonmanifold =. (<(number{::nonmanifold),index)number}nonmanifold
        end.
    end.
    fans =. vertex_count$<0$a:
    global_bad =. i.0
    for_vertex. used do.
        containing =. 1+I.+./"1 vertex=3{."1 faces
        local_neighbors =. (#faces)$<i.0
        for_index. i.#edges do.
            if. vertex e.index{edges do.
                adjacent =. index{::edge_faces
                for_first. adjacent do.
                    row =. (first-1){::local_neighbors
                    row =. /:~~.row,adjacent-.first
                    local_neighbors =. (<row)(first-1)}local_neighbors
                end.
            end.
        end.
        parts =. containing connected local_neighbors
        fans =. (<parts)(vertex-1)}fans
        if. 2<:#parts do.
            global_bad =. global_bad,vertex
        end.
        counts =. (#component_faces)$0
        for_box. parts do.
            part =. >box
            number =. (((0{part)-1){face_components)-1
            counts =. (1+number{counts)number}counts
        end.
        for_number. I.counts>:2 do.
            bad_vertices =. (<(number{::bad_vertices),vertex)number}bad_vertices
        end.
    end.
    (<edges),(<edge_faces),(<face_components),(<component_faces),(<component_vertices),(<component_edges),(<boundary),(<nonmanifold),(<bad_vertices),(<fans),(<global_bad),<used
)
trace_loops =: 3 : 0
    'edges boundaries' =. y
    loops =. 0$a:
    for_number. i.#boundaries do.
        boundary =. number{::boundaries
        unused =. 1 boundary}(#edges)$0
        for_first. boundary do.
            if. -.first{unused do.
                continue.
            end.
            unused =. 0 first}unused
            sequence =. first{edges
            current =. {:sequence
            while. current~:{.sequence do.
                chosen =. _1
                other =. _1
                for_index. boundary do.
                    pair =. index{edges
                    if. (index{unused)*.current e.pair do.
                        next =. {.pair-.current
                        if. (other<0)+.next<other do.
                            chosen =. index
                            other =. next
                        end.
                    end.
                end.
                if. chosen<0 do.
                    break.
                end.
                unused =. 0 chosen}unused
                sequence =. sequence,other
                current =. other
            end.
            length =. (#sequence)-1
            kind =. 'open'
            if. current={.sequence do.
                sequence =. }:sequence
                kind =. 'closed'
            end.
            loop =. (<1+#loops),(<number+1),(<sequence),(<length),(<kind),<0
            loops =. loops,<loop
        end.
    end.
    loops
)
