dbscan =: 4 : 0
    neighborhoods =. x
    core =. y<:#&>neighborhoods
    labels =. (#neighborhoods)$_2
    cluster =. 0
    for_point. i.#neighborhoods do.
        if. _2~:point{labels do.
            continue.
        end.
        if. -.point{core do.
            labels =. _1 point}labels
            continue.
        end.
        labels =. cluster point}labels
        queue =. point{::neighborhoods
        head =. 0
        while. head<#queue do.
            other =. head{queue
            head =. head+1
            if. _1=other{labels do.
                labels =. cluster other}labels
            elseif. _2=other{labels do.
                labels =. cluster other}labels
                if. other{core do.
                    queue =. queue,other{::neighborhoods
                end.
            end.
        end.
        cluster =. cluster+1
    end.
    (<labels),<core
)
