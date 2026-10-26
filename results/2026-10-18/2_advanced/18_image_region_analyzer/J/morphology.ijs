Neighborhood =: 8 2$0 _1 1 _1 1 0 1 1 0 1 _1 1 _1 0 _1 _1
occupied =: 4 : 0
    'px py' =. y
    'height width' =. $x
    if. (px<0)+.(py<0)+.(px>:width)+.py>:height do. 0
    else. (<py,px){x end.
)
erode =: 4 : 0
    result =. ($x)$0
    'height width' =. $x
    for_py. i.height do.
        for_px. i.width do.
            value =. 1
            for_offset. y do.
                if. -.x occupied (px,py)+offset do. value =. 0 break. end.
            end.
            result =. value (<py,px)}result
        end.
    end.
    result
)
dilate =: 4 : 0
    result =. ($x)$0
    'height width' =. $x
    for_py. i.height do.
        for_px. i.width do.
            value =. 0
            for_offset. y do.
                if. x occupied (px,py)-offset do. value =. 1 break. end.
            end.
            result =. value (<py,px)}result
        end.
    end.
    result
)
opening =: 4 : '(x erode y)dilate y'
closing =: 4 : '(x dilate y)erode y'
neighbor_bits =: 4 : 0
    bits =. 0$0
    for_offset. Neighborhood do. bits =. bits,x occupied y+offset end.
    bits
)
transitions =: 3 : '+/(-.y)*.1|.y'
crossing_number =: 4 : 'transitions x neighbor_bits y'
thinning_step =: 4 : 0
    first =. y
    removed =. 0 2$0
    'height width' =. $x
    for_py. i.height do.
        for_px. i.width do.
            if. -.x occupied px,py do. continue. end.
            bits =. x neighbor_bits px,py
            count =. +/bits
            if. (count<2)+.(count>6)+.1~:transitions bits do. continue. end.
            'p2 p4 p6 p8' =. 0 2 4 6{bits
            if. first do. a =. p2*p4*p6
                b =. p4*p6*p8
            else. a =. p2*p4*p8
                b =. p2*p6*p8 end.
            if. -.a+.b do. removed =. removed,py,px end.
        end.
    end.
    result =. x
    for_point. removed do. result =. 0 (<point)}result end.
    (<result),<#removed
)
thin =: 3 : 0
    while. 1 do.
        'y first' =. y thinning_step 1
        'y second' =. y thinning_step 0
        if. 0=first+second do. y return. end.
    end.
)
