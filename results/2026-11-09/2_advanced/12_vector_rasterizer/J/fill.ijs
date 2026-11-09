fill_polygons =: 3 : 0
    'sequences rule clip' =. y
    edges =. 0$a:
    for_box. sequences do.
        vertices =. >box
        for_index. i.#vertices do.
            start =. index{vertices
            finish =. ((#vertices)|index+1){vertices
            if. (1{start)~:1{finish do. edges =. edges,<start,:finish end.
        end.
    end.
    'x0 y0 x1 y1' =. clip
    pixels =. 0$0
    for_py. y0+i.1+y1-y0 do.
        crossings =. 0 2$0
        for_box. edges do.
            edge =. >box
            'xa ya xb yb' =. ,edge
            if. (py<ya<.yb)+.py>:ya>.yb do. continue. end.
            denominator =. yb-ya
            numerator =. (2*xa*denominator)+(((2*py)+1)-2*ya)*(xb-xa)
            direction =. 1
            if. denominator<0 do. numerator =. -numerator
                denominator =. -denominator
                direction =. _1 end.
            first =. 1+(numerator-denominator) div 2*denominator
            crossings =. crossings,first,direction
        end.
        crossings =. (/:crossings){crossings
        count =. winding =. index =. 0
        for_px. x0+i.1+x1-x0 do.
            while. index<#crossings do.
                if. px<(<index,0){crossings do. break. end.
                count =. count+1
                winding =. winding+(<index,1){crossings
                index =. index+1
            end.
            if. rule-:'evenodd' do. filled =. 1=2|count else. filled =. winding~:0 end.
            if. filled do. pixels =. pixels,(py*Width)+px end.
        end.
    end.
    pixels
)
fill_shape =: 3 : 0
    'center points clip' =. y
    'cx cy' =. center
    'x0 y0 x1 y1' =. clip
    pixels =. 0$0
    for_dy. ~.1{"1 points do.
        py =. cy+dy
        if. (py<y0)+.py>y1 do. continue. end.
        extent =. >./|0{"1 points#~dy=1{"1 points
        first =. x0>.cx-extent
        last =. x1<.cx+extent
        if. first<:last do. pixels =. pixels,(py*Width)+first+i.1+last-first end.
    end.
    pixels
)
flood_fill =: 3 : 0
    'seed clip' =. y
    colors =. layer_get 'colors'
    painted =. layer_get 'painted'
    id =. (Width*1{seed)+0{seed
    target =. id{colors
    targetpainted =. id{painted
    seen =. 1 id}PixelCount$0
    queue =. ,id
    head =. 0
    while. head<#queue do.
        id =. head{queue
        head =. head+1
        point =. (Width|id),id div Width
        for_delta. 4 2$1 0 _1 0 0 1 0 _1 do.
            other =. point+delta
            if. -.clip contains other do. continue. end.
            nextid =. (Width*1{other)+0{other
            if. nextid{seen do. continue. end.
            if. targetpainted~:nextid{painted do. continue. end.
            if. targetpainted do. if. -.target-:nextid{colors do. continue. end. end.
            seen =. 1 nextid}seen
            queue =. queue,nextid
        end.
    end.
    I.seen
)
