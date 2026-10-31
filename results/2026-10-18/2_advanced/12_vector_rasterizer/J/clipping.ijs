region_code =: 4 : 0
    'px py' =. x
    'x0 y0 x1 y1' =. y
    (px<x0),(px>x1),(py<y0),py>y1
)
clip_segment =: 3 : 0
    'start finish clip' =. y
    'x0 y0 x1 y1' =. clip
    while. 1 do.
        first =. start region_code clip
        last =. finish region_code clip
        if. (-.+./first)*.-.+./last do. start,:finish return. end.
        if. +./first*.last do. empty_points '' return. end.
        if. +./first do. code =. first
            outside =. start
            other =. finish
        else. code =. last
            outside =. finish
            other =. start end.
        'ax ay' =. outside
        'bx by' =. other
        if. 2{code do. point =. (ax+((bx-ax)*(y0-ay)) round_ratio by-ay),y0
        elseif. 3{code do. point =. (ax+((bx-ax)*(y1-ay)) round_ratio by-ay),y1
        elseif. 1{code do. point =. x1,ay+((by-ay)*(x1-ax)) round_ratio bx-ax
        else. point =. x0,ay+((by-ay)*(x0-ax)) round_ratio bx-ax end.
        if. +./first do. start =. point else. finish =. point end.
    end.
)
inside_boundary =: 4 : 0
    'axis limit minimum' =. x
    if. minimum do. (axis{y)>:limit else. (axis{y)<:limit end.
)
boundary_intersection =: 3 : 0
    'start finish axis limit' =. y
    'sx sy' =. start
    'ex ey' =. finish
    if. axis=0 do. limit,sy+((limit-sx)*(ey-sy)) round_ratio ex-sx
    else. (sx+((limit-sy)*(ex-sx)) round_ratio ey-sy),limit end.
)
clip_polygon =: 4 : 0
    vertices =. x
    'x0 y0 x1 y1' =. y
    boundaries =. 4 3$0,x0,1,0,(x1+1),0,1,y0,1,1,(y1+1),0
    for_boundary. boundaries do.
        output =. empty_points ''
        if. 0=#vertices do. output return. end.
        'axis limit minimum' =. boundary
        for_index. i.#vertices do.
            start =. ((#vertices)|index-1){vertices
            finish =. index{vertices
            if. boundary inside_boundary finish do.
                if. -.boundary inside_boundary start do. output =. output,boundary_intersection (<start),(<finish),(<axis),<limit end.
                output =. output,finish
            elseif. boundary inside_boundary start do. output =. output,boundary_intersection (<start),(<finish),(<axis),<limit end.
        end.
        vertices =. output
    end.
    vertices
)
