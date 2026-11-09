mask_condition =: 4 : 0
    'xx yy' =. y
    select. x
    case. 0 do. 0=2|xx+yy
    case. 1 do. 0=2|yy
    case. 2 do. 0=3|xx
    case. 3 do. 0=3|xx+yy
    case. 4 do. 0=2|(yy intdiv 2)+xx intdiv 3
    case. 5 do. 0=(2|xx*yy)+3|xx*yy
    case. 6 do. 0=2|(2|xx*yy)+3|xx*yy
    case. 7 do. 0=2|(2|xx+yy)+3|xx*yy
    end.
)
apply_mask =: 4 : 0
    'geometry mask' =. x
    'n unused areas order' =. geometry
    result =. y
    for_position. order do.
        if. mask mask_condition(n|position),position intdiv n do.
            result =. (-.position{result)position}result
        end.
    end.
    result
)
penalties =: 4 : 0
    n =. x
    table =. (n,n)$y
    lines =. table,|:table
    n1 =. 0
    n3 =. 0
    for_line. lines do.
        run =. 1
        for_i. 1+i.n-1 do.
            if. (i{line)=(i-1){line do.
                run =. run+1
            else.
                if. run>:5 do.
                    n1 =. n1+run-2
                end.
                run =. 1
            end.
        end.
        if. run>:5 do.
            n1 =. n1+run-2
        end.
        n3 =. n3+40*(+/1 0 1 1 1 0 1 0 0 0 0 E.line)+(+/0 0 0 0 1 0 1 1 1 0 1 E.line)
    end.
    n2 =. 0
    for_yy. i.n-1 do.
        for_xx. i.n-1 do.
            positions =. (xx+n*yy)+0 1,n,n+1
            if. 1=#~.positions{y do.
                n2 =. n2+3
            end.
        end.
    end.
    n4 =. 10*((|((20*+/y)-10*n*n))intdiv n*n)
    n1,n2,n3,n4
)
