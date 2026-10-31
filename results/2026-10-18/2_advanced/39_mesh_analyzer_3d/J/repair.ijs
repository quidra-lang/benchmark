split_polygons =: 3 : 0
    'polygons lines' =. y
    triangles =. 0 6$0x
    for_polygon. i.#polygons do.
        corners =. polygon{::polygons
        for_index. 1+i.(#corners)-2 do.
            triangles =. triangles,(0{corners),(index{corners),((index+1){corners),(1+#triangles),(polygon+1),polygon{lines
        end.
    end.
    triangles
)
snap_vertices =: 4 : 0
    points =. x*<.((2*y)+x)%2*x
    changed =. 1+I.+./"1 points~:y
    (<points),<changed
)
representatives =: 4 : 0
    if. x do.
        1+y i.y
    else.
        1+i.#y
    end.
)
clean_faces =: 3 : 0
    'triangles points representative remove_zero remove_duplicate' =. y
    faces =. 0 6$0x
    removed =. 0 6$0x
    reasons =. 0$a:
    seen =. 0$a:
    for_triangle. triangles do.
        face =. ((3{.triangle)-1){representative
        face =. face,3}.triangle
        reason =. ''
        if. 3>#~.3{.face do.
            reason =. 'repeated'
        elseif. remove_zero do.
            if. 0 0 0-:face normal points do.
                reason =. 'zero_area'
            end.
        end.
        if. 0=#reason do.
            ordered =. /:~3{.face
            if. remove_duplicate*.(<ordered)e.seen do.
                reason =. 'duplicate'
            else.
                seen =. seen,<ordered
            end.
        end.
        if. #reason do.
            removed =. removed,triangle
            reasons =. reasons,<reason
        else.
            faces =. faces,face
        end.
    end.
    (<faces),(<removed),<reasons
)
filling =: 3 : 0
    faces =. 0 6$0x
    for_index. 2+i.(#y)-2 do.
        faces =. faces,(0{y),(index{y),((index-1){y),0 0 0
    end.
    faces
)
