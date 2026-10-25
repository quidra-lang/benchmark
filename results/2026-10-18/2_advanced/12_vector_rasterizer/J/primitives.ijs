empty_points =: 3 : '0 2$0'
bresenham =: 4 : 0
    'px py' =. x
    'ex ey' =. y
    dx =. |ex-px
    dy =. -|ey-py
    sx =. _1+2*px<ex
    sy =. _1+2*py<ey
    error =. dx+dy
    points =. empty_points ''
    while. 1 do.
        points =. points,px,py
        if. (px=ex)*.py=ey do. points return. end.
        twice =. 2*error
        if. twice>:dy do. error =. error+dy
            px =. px+sx end.
        if. twice<:dx do. error =. error+dx
            py =. py+sy end.
    end.
)
expand_square =: 4 : 0
    low =. -((y-1) div 2)
    points =. empty_points ''
    for_dy. low+i.y do.
        for_dx. low+i.y do. points =. points,x+(dx,dy) end.
    end.
    points
)
circle_points =: 3 : 0
    points =. empty_points ''
    a =. y
    b =. 0
    error =. 1-y
    while. a>:b do.
        points =. points,8 2$a,b,b,a,(-b),a,(-a),b,(-a),(-b),(-b),(-a),b,(-a),a,-b
        b =. b+1
        if. error<0 do. error =. error+(2*b)+1
        else. a =. a-1
            error =. error+(2*(b-a))+1 end.
    end.
    ~.points
)
ellipse_points =: 3 : 0
    'rx ry' =. y
    rx2 =. rx*rx
    ry2 =. ry*ry
    px =. 0
    py =. ry
    points =. 2 2$0,ry,0,-ry
    while. (ry2*px)<rx2*py do.
        decision =. ((4*ry2*(px+1)*(px+1))+(rx2*((2*py)-1)*((2*py)-1)))-4*rx2*ry2
        px =. px+1
        if. decision>:0 do. py =. py-1 end.
        points =. points,4 2$px,py,(-px),py,px,(-py),(-px),-py
    end.
    while. py>0 do.
        decision =. ((ry2*((2*px)+1)*((2*px)+1))+(4*rx2*(py-1)*(py-1)))-4*rx2*ry2
        py =. py-1
        if. decision<:0 do. px =. px+1 end.
        points =. points,4 2$px,py,(-px),py,px,(-py),(-px),-py
    end.
    ~.points
)
bezier_points =: 4 : 0
    controls =. x
    segments =. y
    degree =. (#controls)-1
    scale =. */degree#segments
    points =. empty_points ''
    for_index. i.segments+1 do.
        rest =. segments-index
        if. degree=2 do. weights =. (rest*rest),(2*index*rest),index*index
        else. weights =. (rest*rest*rest),(3*index*rest*rest),(3*index*index*rest),index*index*index end.
        totals =. +/weights*"0 1 controls
        points =. points,totals round_ratio scale
    end.
    points
)
