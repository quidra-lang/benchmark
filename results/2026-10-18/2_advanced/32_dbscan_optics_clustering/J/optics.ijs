INF =: 1000000000000000000x
core_distances =: 3 : 0
    'points neighborhoods minimum' =. y
    result =. i.0
    for_index. i.#points do.
        row =. index{::neighborhoods
        value =. INF
        if. minimum<:#row do.
            distances =. i.0
            for_other. row do.
                distances =. distances,(index{points)squared_distance other{points
            end.
            value =. (minimum-1){/:~distances
        end.
        result =. result,value
    end.
    result
)
optics_ordering =: 3 : 0
    'points neighborhoods core' =. y
    count =. #points
    reach =. count$INF
    predecessor =. count$_1
    processed =. count$0
    ordering =. i.0
    for_start. i.count do.
        if. start{processed do.
            continue.
        end.
        seeds =. start
        while. #seeds do.
            current =. {.seeds /:(seeds{reach),.seeds
            seeds =. seeds-.current
            processed =. 1 current}processed
            ordering =. ordering,current
            if. INF=current{core do.
                continue.
            end.
            for_other. current{::neighborhoods do.
                if. other{processed do.
                    continue.
                end.
                candidate =. (current{core)>.(current{points)squared_distance other{points
                if. candidate<other{reach do.
                    reach =. candidate other}reach
                    predecessor =. current other}predecessor
                    seeds =. ~.seeds,other
                end.
            end.
        end.
    end.
    (<ordering),(<reach),<predecessor
)
