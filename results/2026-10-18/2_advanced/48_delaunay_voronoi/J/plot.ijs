canvas_init =: 3 : 0
    'PlotWidth PlotHeight' =: y
    Canvas =: (PlotHeight,PlotWidth)$' '
)
canvas_position =: 3 : 0
    d =. 1x
    if. (#y)=3 do.
        d =. 2{y
    end.
    column =. <.0.0+((2*(0{y)*(PlotWidth-1))+1000*d)intdiv 2000*d
    vertical =. <.0.0+((2*(1{y)*(PlotHeight-1))+1000*d)intdiv 2000*d
    column,(PlotHeight-1)-vertical
)
canvas_mark =: 4 : 0
    'column row' =. canvas_position y
    Canvas =: x(<row,column)}Canvas
)
canvas_line =: 3 : 0
    'first second character' =. y
    'x y' =. canvas_position first
    'end_x end_y' =. canvas_position second
    dx =. |end_x-x
    dy =. -|end_y-y
    sx =. _1+2*x<end_x
    sy =. _1+2*y<end_y
    error =. dx+dy
    while. 1 do.
        Canvas =: character(<y,x)}Canvas
        if. (x=end_x)*.y=end_y do.
            return.
        end.
        twice =. 2*error
        if. twice>:dy do.
            error =. error+dy
            x =. x+sx
        end.
        if. twice<:dx do.
            error =. error+dx
            y =. y+sy
        end.
    end.
)
canvas_voronoi =: 3 : 0
    points =. x:y
    horizontal =. PlotWidth-1
    vertical =. PlotHeight-1
    owners =. (PlotHeight,PlotWidth)$0
    for_r. i.PlotHeight do.
        for_c. i.PlotWidth do.
            dx =. ((c*1000)-(0{"1 points)*horizontal)*vertical
            dy =. (((vertical-r)*1000)-(1{"1 points)*vertical)*horizontal
            distances =. (dx*dx)+dy*dy
            owner =. 1+{.I.distances=<./distances
            owners =. owner(<r,c)}owners
        end.
    end.
    for_r. i.PlotHeight do.
        for_c. i.PlotWidth do.
            different =. 0
            owner =. (<r,c){owners
            if. c<horizontal do.
                different =. different+.owner~:(<r,c+1){owners
            end.
            if. r<vertical do.
                different =. different+.owner~:(<(r+1),c){owners
            end.
            if. different do.
                Canvas =: '#'(<r,c)}Canvas
            end.
        end.
    end.
    for_point. points do.
        'o' canvas_mark point
    end.
)
canvas_framed =: 3 : 0
    border =. '+',(PlotWidth#'-'),'+'
    result =. <border
    for_row. Canvas do.
        result =. result,<'|',row,'|'
    end.
    result,<border
)
