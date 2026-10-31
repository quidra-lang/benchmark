ordered_sum =: 3 : 0
    if. 0=#y do. 0.0 return. end.
    result =. {.y
    for_value. }.y do. result =. result+value end.
    result
)
heat_flow =: 4 : 0
    'point first last' =. x
    terms =. i.0
    for_direction. first+i.1+last-first do.
        neighbor =. (<point,direction){Neighbors
        g =. (<point,direction){FaceG
        if. neighbor>:0 do. terms =. terms,g*((neighbor{y)-point{y)
        elseif. (<point,direction){BoundaryFaces do.
            terms =. terms,g*(((<point,direction){Theta)-point{y)
        end.
    end.
    ordered_sum terms
)
horizontal_flow =: 4 : '(x,0 1)heat_flow y'
vertical_flow =: 4 : '(x,2 3)heat_flow y'
total_flow =: 4 : '(x,0 3)heat_flow y'
thomas =: 3 : 0
    'lower diagonal upper rhs' =. y
    up =. ,({.upper)%{.diagonal
    rp =. ,({.rhs)%{.diagonal
    for_i. 1+i.(#diagonal)-1 do.
        pivot =. (i{diagonal)-(i{lower)*(i-1){up
        up =. up,(i{upper)%pivot
        rp =. rp,((i{rhs)-(i{lower)*(i-1){rp)%pivot
    end.
    result =. (#diagonal)$0.0
    result =. ({:rp)((#diagonal)-1)}result
    for_i. |.i.(#diagonal)-1 do.
        result =. ((i{rp)-(i{up)*(i+1){result)i}result
    end.
    result
)
sweep =: 4 : 0
    'tau horizontal' =. x
    line_count =. Width
    length =. Height
    first =. 2
    if. horizontal do. line_count =. Height
        length =. Width
        first =. 0
    end.
    second =. first+1
    field =. CellCount$0.0
    for_line. i.line_count do.
        cells =. line+Width*i.length
        if. horizontal do. cells =. (Width*line)+i.length end.
        lower =. diagonal =. upper =. values =. i.0
        for_point. cells do.
            a =. (<point,first){FaceG
            b =. (<point,second){FaceG
            lo =. hi =. 0.0
            if. ((<point,first){Neighbors)>:0 do. lo =. -a end.
            if. ((<point,second){Neighbors)>:0 do. hi =. -b end.
            lower =. lower,lo
            diagonal =. diagonal,(((point{Capacity)%tau)+a)+b
            upper =. upper,hi
            value =. point{y
            if. (<point,first){BoundaryFaces do. value =. value+a*(<point,first){Theta end.
            if. (<point,second){BoundaryFaces do. value =. value+b*(<point,second){Theta end.
            values =. values,value
        end.
        solved =. thomas (<lower),(<diagonal),(<upper),<values
        field =. solved cells}field
    end.
    field
)
advance =: 4 : 0
    'method dt' =. x
    'field source' =. y
    rhs =. i.0
    if. 'ftcs'-:method do.
        for_p. i.CellCount do.
            value =. (p{field)+((dt*((p total_flow field)+p{source))%p{Capacity)
            rhs =. rhs,value
        end.
        (<rhs),<i.0 return.
    end.
    tau =. dt
    if. 'crank_nicolson'-:method do. tau =. dt%2.0 end.
    vertical =. i.0
    for_p. i.CellCount do.
        value =. p vertical_flow field
        vertical =. vertical,value
        rhs =. rhs,((((p{Capacity)%tau)*p{field)+value)+p{source
    end.
    intermediate =. (tau,1)sweep rhs
    for_p. i.CellCount do.
        if. 'backward_euler'-:method do.
            value =. (((p{Capacity)%dt)*p{intermediate)-p{vertical
        else.
            value =. (((((p{Capacity)%tau)*p{intermediate)+p horizontal_flow intermediate)+p{source)
        end.
        rhs =. value p}rhs
    end.
    (<(tau,0)sweep rhs),<intermediate
)
