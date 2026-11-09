build_graph =: 3 : 0
    Shared =: (CourseCount,CourseCount)$0
    for_box. StudentCourses do.
        courses =. >box
        for_i. i.#courses do.
            first =. i{courses
            for_second. (i+1)}.courses do.
                Shared =: (1+(<first,second){Shared) (<first,second)}Shared
                Shared =: (1+(<second,first){Shared) (<second,first)}Shared
            end.
        end.
    end.
    Vertices =: I.Sizes>0
    Degrees =: +/"1 Shared>0
    Edges =: 0 3$0
    for_first. Vertices do.
        for_second. I.0<first{Shared do.
            if. first<second do. Edges =: Edges,first,second,(<first,second){Shared end.
        end.
    end.
    i.0
)
neighbours =: 3 : 'I.0<y{Shared'
graph_components =: 3 : 0
    seen =. CourseCount$0
    result =. 0$a:
    for_vertex. Vertices do.
        if. vertex{seen do. continue. end.
        seen =. 1 vertex}seen
        component =. ,vertex
        index =. 0
        while. index<#component do.
            for_other. neighbours index{component do.
                if. -.other{seen do.
                    seen =. 1 other}seen
                    component =. component,other
                end.
            end.
            index =. index+1
        end.
        result =. result,</:~component
    end.
    order =. /:(-#&>result),.{.&>result
    order{result
)
greedy_clique =: 3 : 0
    candidates =. y
    clique =. 0$0
    while. #candidates do.
        chosen =. {.by_degree candidates
        clique =. clique,chosen
        candidates =. candidates#~candidates e.neighbours chosen
    end.
    clique
)
kempe_chain =: 4 : 0
    'course home target' =. x
    assignment =. y
    chain =. ,course
    index =. 0
    while. index<#chain do.
        adjacent =. neighbours index{chain
        added =. adjacent#~(-.adjacent e.chain)*.(adjacent{assignment)e.home,target
        chain =. chain,added
        index =. index+1
    end.
    /:~chain
)
reachable =: 4 : 0
    stack =. ,x
    seen =. ,x
    while. #stack do.
        node =. {:stack
        stack =. }:stack
        if. node=y do. 1 return. end.
        successors =. 1{"1 Orders#~node=0{"1 Orders
        added =. successors#~-.successors e.seen
        stack =. stack,added
        seen =. seen,added
    end.
    0
)
