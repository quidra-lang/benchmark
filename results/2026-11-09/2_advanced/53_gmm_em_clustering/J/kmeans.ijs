distance2 =: 4 : '+/*:x-y'
distance =: 4 : '%:x distance2 y'
assign_centers =: 4 : 0
    result =. i.0
    for_point. x do.
        distances =. i.0
        for_center. y do.
            distances =. distances,point distance2 center
        end.
        result =. result,distances i.<./distances
    end.
    result
)
run_kmeans =: 3 : 0
    'points centers maximum' =. y
    labels =. points assign_centers centers
    count =. #centers
    iterations =. 0
    for_iteration. 1+i.maximum do.
        updated =. 0 2$0.0
        for_k. i.count do.
            total =. 2$0.0
            size =. 0
            for_i. i.#points do.
                if. k=i{labels do.
                    total =. total+i{points
                    size =. size+1
                end.
            end.
            center =. k{centers
            if. size do.
                center =. total%size
            end.
            updated =. updated,center
        end.
        centers =. updated
        next_labels =. points assign_centers centers
        same =. labels-:next_labels
        labels =. next_labels
        iterations =. iteration
        if. same do.
            break.
        end.
    end.
    inertia =. 0.0
    sizes =. count$0
    for_i. i.#points do.
        k =. i{labels
        sizes =. (1+k{sizes)k}sizes
        inertia =. inertia+(i{points)distance2 k{centers
    end.
    (<centers),(<labels),(<iterations),(<inertia),<sizes
)
