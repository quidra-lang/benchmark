intdiv =: 4 : '<.(x: x)%x: y'
digest =: 3 : 0
    result =. ''
    bases =. 1000003 1500007 2750159 4194301
    initials =. 11 23 37 53
    for_lane. i.4 do.
        base =. lane{bases
        value =. lane{initials
        for_code. (a.i.y),(#y),0 0 do.
            value =. 2147483647|code+value*base
        end.
        result =. result,'0123456789abcdef'{~_8{.(8$0),16#.inv value
    end.
    result
)
merkle_root =: 3 : 0
    level =. y
    while. 1<#level do.
        if. 2|#level do.
            level =. level,{:level
        end.
        next =. 0$a:
        for_i. 2*i.(#level)intdiv 2 do.
            next =. next,<digest (i{::level),(i+1){::level
        end.
        level =. next
    end.
    0{::level
)
short =: 8&{.
