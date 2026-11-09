strong_components =: 3 : 0
    count =. #y
    order =. count$_1
    low =. count$0
    onstack =. count$0
    stack =. 0$0
    groups =. 0$a:
    counter =. 0
    for_root. i.count do.
        if. _1~:root{order do. continue. end.
        order =. counter root}order
        low =. counter root}low
        counter =. counter+1
        stack =. stack,root
        onstack =. 1 root}onstack
        worknodes =. ,root
        workpositions =. ,0
        while. #worknodes do.
            node =. {:worknodes
            position =. {:workpositions
            neighbors =. node{::y
            if. position<#neighbors do.
                workpositions =. (position+1) ((#workpositions)-1)}workpositions
                child =. position{neighbors
                if. _1=child{order do.
                    order =. counter child}order
                    low =. counter child}low
                    counter =. counter+1
                    stack =. stack,child
                    onstack =. 1 child}onstack
                    worknodes =. worknodes,child
                    workpositions =. workpositions,0
                elseif. child{onstack do.
                    low =. ((node{low)<.child{order) node}low
                end.
                continue.
            end.
            worknodes =. }:worknodes
            workpositions =. }:workpositions
            if. #worknodes do.
                parent =. {:worknodes
                low =. ((parent{low)<.node{low) parent}low
            end.
            if. (node{low)=node{order do.
                group =. 0$0
                while. 1 do.
                    member =. {:stack
                    stack =. }:stack
                    onstack =. 0 member}onstack
                    group =. group,member
                    if. member=node do. break. end.
                end.
                groups =. groups,<group
            end.
        end.
    end.
    groups
)
reachable =: 4 : 0
    seen =. (#x)$0
    stack =. 0$0
    for_start. y do.
        if. -.start{seen do. seen =. 1 start}seen
            stack =. stack,start end.
    end.
    while. #stack do.
        node =. {:stack
        stack =. }:stack
        for_child. node{::x do.
            if. -.child{seen do. seen =. 1 child}seen
                stack =. stack,child end.
        end.
    end.
    seen
)
bfs_distances =: 4 : 0
    distances =. (#x)$_1
    queue =. 0$0
    for_start. y do.
        if. _1=start{distances do. distances =. 0 start}distances
            queue =. queue,start end.
    end.
    head =. 0
    while. head<#queue do.
        node =. head{queue
        head =. head+1
        for_child. node{::x do.
            if. _1=child{distances do.
                distances =. (1+node{distances) child}distances
                queue =. queue,child
            end.
        end.
    end.
    distances
)
weak_components =: 3 : 0
    labels =. (#y)$_1
    next =. 0
    for_root. i.#y do.
        if. _1~:root{labels do. continue. end.
        labels =. next root}labels
        stack =. ,root
        while. #stack do.
            node =. {:stack
            stack =. }:stack
            for_child. node{::y do.
                if. _1=child{labels do.
                    labels =. next child}labels
                    stack =. stack,child
                end.
            end.
        end.
        next =. next+1
    end.
    labels
)
