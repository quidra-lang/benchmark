has_directed =: 4 : '+./y-:"1 directed x'
flip =: 3 : '(0 2 1{y)0 1 2}y'
inconsistent =: 3 : 0
    'faces edges edge_faces' =. y
    result =. i.0
    for_index. i.#edges do.
        adjacent =. index{::edge_faces
        if. 2=#adjacent do.
            edge =. index{edges
            if. (((0{adjacent)-1){faces)has_directed edge do.
                first =. 1
            else.
                first =. 0
            end.
            if. first=(((1{adjacent)-1){faces)has_directed edge do.
                result =. result,index
            end.
        end.
    end.
    result
)
repair_orientation =: 3 : 0
    'faces edges edge_faces' =. y
    visited =. (#faces)$0
    for_seed. i.#faces do.
        if. seed{visited do.
            continue.
        end.
        visited =. 1 seed}visited
        queue =. ,seed
        head =. 0
        while. head<#queue do.
            current =. head{queue
            head =. head+1
            for_pair. directed current{faces do.
                index =. edges edge_index pair
                adjacent =. index{::edge_faces
                if. 2~:#adjacent do.
                    continue.
                end.
                other =. {.adjacent-.current+1
                other =. other-1
                if. -.other{visited do.
                    if. (other{faces)has_directed pair do.
                        faces =. (flip other{faces)other}faces
                    end.
                    visited =. 1 other}visited
                    queue =. queue,other
                end.
            end.
        end.
    end.
    faces
)
