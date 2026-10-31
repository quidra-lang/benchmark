find_root =: 4 : 0
    while. y~:y{x do. y =. y{x end.
    y
)
label_components =: 4 : 0
    mask =. x
    connectivity =. y
    'height width' =. $mask
    previous =. 2 2$_1 0 0 _1
    if. connectivity=8 do. previous =. 4 2$_1 0 _1 _1 0 _1 1 _1 end.
    provisional =. ($mask)$0
    parents =. ,0
    for_py. i.height do.
        for_px. i.width do.
            if. -.mask occupied px,py do. continue. end.
            neighbors =. 0$0
            for_offset. previous do.
                point =. (px,py)+offset
                if. mask occupied point do. neighbors =. neighbors,(<|.point){provisional end.
            end.
            if. #neighbors do.
                label =. {.neighbors
                for_other. }.neighbors do.
                    first =. parents find_root label
                    second =. parents find_root other
                    parents =. (first<.second) (first>.second)}parents
                end.
            else. label =. #parents
                parents =. parents,label end.
            provisional =. label (<py,px)}provisional
        end.
    end.
    numbers =. (#parents)$0
    labels =. ($mask)$0
    count =. 0
    for_py. i.height do.
        for_px. i.width do.
            label =. (<py,px){provisional
            if. label=0 do. continue. end.
            root =. parents find_root label
            if. 0=root{numbers do. count =. count+1
                numbers =. count root}numbers end.
            labels =. (root{numbers) (<py,px)}labels
        end.
    end.
    (<labels),(<count),<(#parents)-1
)
bit_quad_euler =: 4 : 0
    'height width' =. $x
    singles =. triples =. diagonals =. 0
    for_py. _1+i.height+1 do.
        for_px. _1+i.width+1 do.
            a =. x occupied px,py
            b =. x occupied (px+1),py
            c =. x occupied px,py+1
            d =. x occupied (px+1),py+1
            count =. a+b+c+d
            singles =. singles+count=1
            triples =. triples+count=3
            diagonals =. diagonals+(count=2)*.(a*.d)+.b*.c
        end.
    end.
    sign =. 2
    if. y=8 do. sign =. _2 end.
    ((singles-triples)+sign*diagonals)div 4
)
