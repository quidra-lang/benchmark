neighbor_points =: 4 : 0
    'width height' =. x
    'column row' =. y
    result =. 0 2$0x
    for_dy. _1 0 1 do.
        for_dx. _1 0 1 do.
            if. (dx=0)*.dy=0 do.
                continue.
            end.
            nx =. column+dx
            ny =. row+dy
            if. (nx>:0)*.(nx<width)*.(ny>:0)*.ny<height do.
                result =. result,nx,ny
            end.
        end.
    end.
    result
)
directions =: 3 : 0
    'gx gy' =. y
    'height width' =. $gx
    result =. (height,width)$0
    for_row. i.height do.
        for_column. i.width do.
            horizontal =. (<row,column){gx
            vertical =. (<row,column){gy
            ax =. |horizontal
            ay =. |vertical
            if. (29*ay)<:12*ax do.
                angle =. 0
            elseif. (29*ay)>:70*ax do.
                angle =. 90
            elseif. (horizontal*vertical)<0 do.
                angle =. 45
            else.
                angle =. 135
            end.
            result =. angle (<row,column)}result
        end.
    end.
    result
)
suppress =: 4 : 0
    magnitude =. x
    direction =. y
    'height width' =. $magnitude
    offsets =. 4 2$_1 0 1 _1 0 _1 _1 _1
    result =. (height,width)$0x
    for_row. 1+i.height-2 do.
        for_column. 1+i.width-2 do.
            angle =. (<row,column){direction
            'dx dy' =. (angle intdiv 45){offsets
            value =. (<row,column){magnitude
            before =. (<(row+dy),column+dx){magnitude
            after =. (<(row-dy),column-dx){magnitude
            if. (value>before)*.value>:after do.
                result =. value (<row,column)}result
            end.
        end.
    end.
    result
)
hysteresis =: 4 : 0
    'low high' =. x
    'height width' =. $y
    strong =. y>:high
    weak =. (y>:low)*.y<high
    edges =. strong
    indices =. I.,strong
    queue =. (width|indices),.indices intdiv width
    cursor =. 0
    while. cursor<#queue do.
        point =. cursor{queue
        cursor =. cursor+1
        for_next. (width,height)neighbor_points point do.
            'nx ny' =. next
            position =. <ny,nx
            if. (-.position{edges)*.(position{strong)+.position{weak do.
                edges =. 1 position}edges
                queue =. queue,next
            end.
        end.
    end.
    (<edges),(<strong),<weak
)
edge_components =: 3 : 0
    edges =. y
    'height width' =. $edges
    visited =. (height,width)$0
    result =. 0$a:
    for_index. I.,edges do.
        'column row' =. (width|index),index intdiv width
        position =. <row,column
        if. position{visited do.
            continue.
        end.
        visited =. 1 position}visited
        queue =. ,:column,row
        cursor =. 0
        while. cursor<#queue do.
            point =. cursor{queue
            cursor =. cursor+1
            for_next. (width,height)neighbor_points point do.
                'nx ny' =. next
                position =. <ny,nx
                if. (position{edges)*.-.position{visited do.
                    visited =. 1 position}visited
                    queue =. queue,next
                end.
            end.
        end.
        result =. result,<queue
    end.
    result
)
