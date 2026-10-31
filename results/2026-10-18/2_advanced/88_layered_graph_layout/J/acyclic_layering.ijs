edge_neighbors =: 4 : 0
    upper =. x$<i.0
    lower =. x$<i.0
    for_edge. y do.
        'first second' =. edge
        upper =. (<(second{::upper),first)second}upper
        lower =. (<(first{::lower),second)first}lower
    end.
    (<upper),<lower
)
acyclic_order =: 4 : 0
    count =. x
    'upper lower' =. count edge_neighbors y
    remaining =. count$1
    head =. i.0
    tail =. i.0
    while. +./remaining do.
        nodes =. I.remaining
        indegrees =. count$0
        outdegrees =. count$0
        for_vertex. nodes do.
            indegrees =. (+/(vertex{::upper){remaining)vertex}indegrees
            outdegrees =. (+/(vertex{::lower){remaining)vertex}outdegrees
        end.
        sinks =. nodes#~0=nodes{outdegrees
        sources =. nodes#~0=nodes{indegrees
        if. #sinks do.
            chosen =. {.sinks
            tail =. chosen,tail
        elseif. #sources do.
            chosen =. {.sources
            head =. head,chosen
        else.
            differences =. nodes{outdegrees-indegrees
            chosen =. nodes{~differences i.>./differences
            head =. head,chosen
        end.
        remaining =. 0 chosen}remaining
    end.
    head,tail
)
lex_less =: 4 : 0
    count =. (#x)<.#y
    differences =. I.(count{.x)~:count{.y
    if. #differences do.
        first =. {.differences
        (first{x)<first{y
    else.
        (#x)<#y
    end.
)
initial_heights =: 3 : 0
    'count upper lower method width' =. y
    heights =. count$_1
    labels =. i.0
    if. method-:'coffman' do.
        labels =. count$_1
        for_label. 1+i.count do.
            chosen =. _1
            best =. i.0
            for_vertex. I.labels=_1 do.
                previous =. (vertex{::upper){labels
                if. _1 e.previous do.
                    continue.
                end.
                key =. \:~previous
                if. (chosen=_1)+.key lex_less best do.
                    chosen =. vertex
                    best =. key
                end.
            end.
            labels =. label chosen}labels
        end.
        current =. 0
        occupied =. 0
        for_iteration. i.count do.
            candidates =. i.0
            for_vertex. I.heights=_1 do.
                if. -._1 e.(vertex{::lower){heights do.
                    candidates =. candidates,vertex
                end.
            end.
            chosen =. candidates{~(candidates{labels)i.>./candidates{labels
            if. (occupied=width)+.current e.(chosen{::lower){heights do.
                current =. current+1
                occupied =. 0
            end.
            heights =. current chosen}heights
            occupied =. occupied+1
        end.
    else.
        for_iteration. i.count do.
            for_vertex. I.heights=_1 do.
                successors =. (vertex{::lower){heights
                if. -._1 e.successors do.
                    heights =. (>./0,1+successors)vertex}heights
                    break.
                end.
            end.
        end.
    end.
    (<heights),<labels
)
promote_vertex =: 3 : 0
    difference =. 0
    for_previous. y{::PromotionUpper do.
        if. (previous{PromotionHeights)=1+y{PromotionHeights do.
            difference =. difference+promote_vertex previous
        end.
    end.
    PromotionHeights =: (1+y{PromotionHeights)y}PromotionHeights
    difference+(#y{::PromotionLower)-#y{::PromotionUpper
)
assign_heights =: 4 : 0
    count =. x
    edges =. y
    'upper lower' =. count edge_neighbors edges
    args =. (<count),(<upper),(<lower),(<setting 'layering'),<setting 'width'
    'heights labels' =. initial_heights args
    before =. 0
    for_edge. edges do.
        'first second' =. edge
        before =. before+((first{heights)-(second{heights))-1
    end.
    rounds =. 0
    record =. 0 3$0
    if. 'on'-:setting 'promotion' do.
        PromotionUpper =: upper
        PromotionLower =: lower
        PromotionHeights =: heights
        while. 1 do.
            rounds =. rounds+1
            accepted =. 0
            for_vertex. i.count do.
                if. 0=#vertex{::upper do.
                    continue.
                end.
                saved =. PromotionHeights
                difference =. promote_vertex vertex
                if. difference<0 do.
                    accepted =. accepted+1
                    record =. record,rounds,vertex,difference
                else.
                    PromotionHeights =: saved
                end.
            end.
            if. accepted=0 do.
                break.
            end.
        end.
        heights =. PromotionHeights
    end.
    (<heights),(<labels),(<before),(<rounds),<record
)
