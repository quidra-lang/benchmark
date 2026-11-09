golden =: 1 : 0
    'a b iterations' =. y
    phi =. 0.6180339887498949
    c =. b-phi*(b-a)
    d =. a+phi*(b-a)
    fc =. u c
    fd =. u d
    records =. ,:a,b,c,d,fc,fd
    for_iteration. i.iterations do.
        if. fc<fd do.
            b =. d
            d =. c
            fd =. fc
            c =. b-phi*(b-a)
            fc =. u c
        else.
            a =. c
            c =. d
            fc =. fd
            d =. a+phi*(b-a)
            fd =. u d
        end.
        records =. records,a,b,c,d,fc,fd
    end.
    if. fc<fd do. (<c),(<fc),<records
    else. (<d),(<fd),<records end.
)
vertex_order =: 3 : '(/:3 0{"1 y){y'
nelder_mead =: 1 : 0
    'beta gamma db dg alpha chi psi omega iterations' =. y
    vertices =. (0,beta,gamma,0.0),(1,(beta+db),gamma,0.0),:2,beta,(gamma+dg),0.0
    for_i. i.3 do.
        point =. 1 2{i{vertices
        vertices =. (u point)(<i,3)}vertices
    end.
    initial =. vertices
    records =. 0$a:
    serial =. 3
    for_iteration. i.iterations do.
        vertices =. vertex_order vertices
        'first second third' =. <"1 vertices
        p1 =. 1 2{first
        p2 =. 1 2{second
        p3 =. 1 2{third
        f1 =. 3{first
        f2 =. 3{second
        f3 =. 3{third
        center =. (p1+p2)%2
        reflected =. center+alpha*(center-p3)
        fr =. u reflected
        accepted =. i.0
        if. fr<f1 do.
            expanded =. center+chi*(reflected-center)
            fe =. u expanded
            if. fe<fr do. accepted =. expanded [ value =. fe [ operation =. 'expand'
            else. accepted =. reflected [ value =. fr [ operation =. 'reflect' end.
        elseif. fr<f2 do.
            accepted =. reflected [ value =. fr [ operation =. 'reflect'
        elseif. fr<f3 do.
            contracted =. center+psi*(reflected-center)
            fc =. u contracted
            if. fc<:fr do. accepted =. contracted [ value =. fc [ operation =. 'contract_out' end.
        else.
            contracted =. center+psi*(p3-center)
            fc =. u contracted
            if. fc<f3 do. accepted =. contracted [ value =. fc [ operation =. 'contract_in' end.
        end.
        if. #accepted do.
            vertices =. first,second,:serial,accepted,value
            serial =. serial+1
        else.
            operation =. 'shrink'
            vertices =. ,:first
            for_point. p2,:p3 do.
                changed =. p1+omega*(point-p1)
                vertices =. vertices,serial,changed,u changed
                serial =. serial+1
            end.
        end.
        vertices =. vertex_order vertices
        records =. records,<(<operation),<0{vertices
    end.
    (<initial),(<records),<vertices
)
