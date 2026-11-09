TafSlots =: 1 3 5 6
ChangeIndicators =: ;:'BECMG TEMPO PROB30 PROB40'
TemporaryKinds =: 'TEMPO';'PROB30';'PROB40';'PROB30 TEMPO';'PROB40 TEMPO'
is_fm =: 3 : '(8=#y)*.(''FM''-:2{.y)*.6 6 width 2}.y'
is_indicator =: 3 : '((<y)e.ChangeIndicators)+.is_fm y'
is_period =: 3 : 0
    if. 9~:#y do. 0 return. end.
    ('/'=4{y)*.(4 4 width 4{.y)*.4 4 width 5}.y
)
period =: 4 : 0
    if. -.is_period y do. NONE return. end.
    h1 =. num 2{.2}.y
    h2 =. num 7}.y
    if. (h1>23)+.(h2<1)+.h2>24 do. NONE return. end.
    s =. forecasttime (num 2{.y),h1,0,x
    e =. forecasttime (num 2{.5}.y),h2,0,x
    if. (isnone s)+.(isnone e)+.s>:e do. NONE else. s,e end.
)
split_changes =: 4 : 0
    f =. x
    gs =. y
    i =. 0
    while. i<#gs do.
        if. is_indicator 1{::i{::gs do. break. end.
        i =. i+1
    end.
    base =. i{.gs
    changes =. 0$a:
    while. i<#gs do.
        'pos kind' =. i{::gs
        i =. i+1
        if. (<kind)e.;:'PROB30 PROB40' do.
            if. i<#gs do.
                if. 'TEMPO'-:1{::i{::gs do. kind =. kind,' TEMPO'
                i =. i+1 end.
            end.
        end.
        valid =. 0
        start =. finish =. NONE
        if. is_fm kind do.
            h =. num 2{.4}.kind
            m =. num 6}.kind
            if. (h<:23)*.m<:59 do.
                start =. forecasttime (num 2{.2}.kind),h,m,dayof 2{::f
            end.
            valid =. (-.isnone start)*.(start>:4{::f)*.start<5{::f
            if. -.valid do. pos error 'invalid period "',kind,'"' end.
            kind =. 'FM'
        else.
            present =. 0
            if. i<#gs do. present =. is_period 1{::i{::gs end.
            if. -.present do. pos error 'missing period "',kind,'"'
            else.
                'pp pt' =. i{::gs
                i =. i+1
                p =. (dayof 2{::f) period pt
                if. -.isnone p do.
                    'start finish' =. p
                    valid =. (start>:4{::f)*.finish<:5{::f
                end.
                if. -.valid do. pp error 'invalid period "',pt,'"' end.
            end.
        end.
        j =. i
        while. j<#gs do.
            if. is_indicator 1{::j{::gs do. break. end.
            j =. j+1
        end.
        if. valid do.
            changes =. changes,<(<kind),(<start),(<finish),(<i}.j{.gs),<NONE
        end.
        i =. j
    end.
    (<base),<changes
)
overlay =: 4 : 0
    r =. x
    for_i. i.4 do.
        if. -.isnone i{::y do. r =. (i{y) i}r end.
    end.
    r
)
prevailing =: 4 : 0
    h =. y
    s =. 6{::x
    for_b. 7{::x do.
        c =. >b
        if. ('FM'-:0{::c)*.(1{::c)<:h do. s =. 4{::c
        elseif. ('BECMG'-:0{::c)*.(2{::c)<:h do. s =. s overlay 4{::c end.
    end.
    s
)
temporary =: 4 : 0
    s =. x prevailing y
    states =. 0$a:
    for_b. 7{::x do.
        c =. >b
        if. ((<0{::c)e.TemporaryKinds)*.((1{::c)<:y)*.y<2{::c do.
            states =. states,<(<0{::c),<s overlay 4{::c
        end.
    end.
    states
)
