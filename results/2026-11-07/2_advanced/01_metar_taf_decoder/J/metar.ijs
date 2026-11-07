MainSlots =: i.10
TrendSlots =: 1 3 5 6
Repeatable =: 4 5 6
TrendIndicators =: ;:'BECMG TEMPO'
split_body =: 3 : 0
    body =. y
    remarks =. 0$a:
    for_i. i.#body do.
        if. 'RMK'-:1{::i{::body do.
            remarks =. (i+1)}.body
            body =. i{.body
            break.
        end.
    end.
    for_i. i.#body do.
        if. (<1{::i{::body)e.TrendIndicators do.
            (<i{.body),(<i}.body),<remarks return.
        end.
    end.
    (<body),(<0$a:),<remarks
)
trend_sections =: 3 : 0
    sections =. 0$a:
    current =. 0$a:
    for_b. y do.
        g =. >b
        if. (<1{::g)e.TrendIndicators do.
            if. #current do. sections =. sections,<current end.
            current =. 0$a:
        end.
        current =. current,<g
    end.
    if. #current do. sections =. sections,<current end.
    sections
)
is_trend_time =: 4 : 0
    if. 6~:#y do. 0 return. end.
    ((<2{.y)e.x)*.4 4 width 2}.y
)
read_trend =: 3 : 0
    gs =. y
    n =. 0
    if. 1<#gs do.
        t =. 1{::1{::gs
        if. (<'FM') is_trend_time t do.
            n =. 1
            if. 2<#gs do. if. (<'TL') is_trend_time 1{::2{::gs do. n =. 2 end. end.
        elseif. (;:'TL AT') is_trend_time t do. n =. 1 end.
    end.
    times =. 0$a:
    for_b. n{.}.gs do.
        'pos t' =. >b
        h =. num 2{.2}.t
        m =. num 4}.t
        if. (h>23)+.m>59 do.
            pos error 'invalid period "',t,'"'
            NONE return.
        end.
        times =. times,<(<2{.t),(<h),<m
    end.
    (<1{::0{::gs),(<times),<(n+1)}.gs
)
signed_tenths =: 3 : '(1-2*''1''={.y)*num }.y'
read_remarks =: 3 : 0
    slp =. temps =. 0$a:
    for_b. y do.
        t =. 1{::>b
        if. ('SLP'-:3{.t)*.3 3 width 3}.t do.
            p =. num 3}.t
            slp =. slp,<p+10000-1000*p>:500
        elseif. 9=#t do.
            if. ('T'={.t)*.(*./(1 5{t)e.'01')*.(*./(2 3 4 6 7 8{t)e.Digits) do.
                temps =. temps,<(signed_tenths 4{.}.t),signed_tenths 5}.t
            end.
        end.
    end.
    (<slp),<temps
)
