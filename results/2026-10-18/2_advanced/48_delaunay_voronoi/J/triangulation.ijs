canonical =: 3 : '(y i.<./y)|.y'
add_triangle =: 3 : 0
    'a b c' =. y-1
    Directed =: (c+1)(<a,b)}Directed
    Directed =: (a+1)(<b,c)}Directed
    Directed =: (b+1)(<c,a)}Directed
)
remove_triangle =: 3 : 0
    'a b c' =. y-1
    Directed =: 0 (<a,b)}Directed
    Directed =: 0 (<b,c)}Directed
    Directed =: 0 (<c,a)}Directed
)
mesh_init =: 3 : 0
    MeshPoints =: y
    Directed =: ((#y),#y)$0
    Initial =: 1 2 3
    if. (orient 3{.y)<0 do.
        Initial =: 1 3 2
    end.
    add_triangle Initial
)
mesh_triangles =: 3 : 0
    result =. 0 3$0
    n =. #Directed
    for_key. I.0<,Directed do.
        a =. <.0.0+key intdiv n
        b =. n|key
        c =. (<a,b){Directed
        if. (a<b)*.a<c-1 do.
            result =. result,(a+1),(b+1),c
        end.
    end.
    result
)
hull_edges =: 3 : 0
    result =. 0 2$0
    n =. #Directed
    for_key. I.0<,Directed do.
        a =. <.0.0+key intdiv n
        b =. n|key
        if. 0=(<b,a){Directed do.
            result =. result,(a+1),b+1
        end.
    end.
    result
)
inside_triangle =: 4 : 0
    vertices =. (x-1){MeshPoints
    for_i. i.3 do.
        if. (orient (i{vertices),(((i+1)|~3){vertices),:y)<:0 do.
            0 return.
        end.
    end.
    1
)
insert_site =: 3 : 0
    site =. y
    point =. (site-1){MeshPoints
    containing =. i.0
    for_triangle. mesh_triangles 0 do.
        if. triangle inside_triangle point do.
            containing =. triangle
            break.
        end.
    end.
    visible =. 0
    check =. 0 2$0
    kind =. 'outside'
    if. #containing do.
        'a b c' =. containing
        remove_triangle containing
        check =. (a,b),((b,c),:(c,a))
        kind =. 'inside'
    else.
        for_edge. hull_edges 0 do.
            vertices =. (edge-1){MeshPoints
            if. (orient vertices,point)<0 do.
                check =. check,|.edge
            end.
        end.
        visible =. #check
    end.
    for_edge. check do.
        add_triangle edge,site
    end.
    pending =. check
    flips =. 0
    while. #pending do.
        'a b' =. {:pending
        pending =. }:pending
        q =. (<(b-1),a-1){Directed
        if. ((<(a-1),b-1){Directed)=site do.
            if. q do.
                ids =. a,b,site,q
                if. (incircle (ids-1){MeshPoints)>0 do.
                    remove_triangle a,b,site
                    remove_triangle b,a,q
                    add_triangle a,q,site
                    add_triangle q,b,site
                    pending =. ~.pending,((a,q),:(q,b))
                    flips =. flips+1
                end.
            end.
        end.
    end.
    (<kind),(<containing),(<visible),(<flips),(<#mesh_triangles 0),<#hull_edges 0
)
visibility_walk =: 3 : 0
    'query triangles edge_triangles' =. y
    path =. ,1
    while. 1 do.
        'a b c' =. (({:path)-1){triangles
        edges =. (a,b),((b,c),:(c,a))
        crossing =. i.0
        for_edge. edges do.
            vertices =. (edge-1){MeshPoints
            if. (orient vertices,query)<0 do.
                crossing =. edge
                break.
            end.
        end.
        if. 0=#crossing do.
            (<path),<i.0 return.
        end.
        'u v' =. crossing-1
        following =. (<v,u){edge_triangles
        if. following=0 do.
            (<path),</:~crossing return.
        end.
        path =. path,following
    end.
)
