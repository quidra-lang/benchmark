radius2 =: 3 : 0
    'a b c' =. y
    first =. 0.0+a d2 b
    second =. 0.0+b d2 c
    third =. 0.0+c d2 a
    area =. 0.0+orient y
    ((first*second)*third)%((4.0*area)*area)
)
center_position =: 3 : 0
    'center points hull' =. y
    'x y d' =. center
    on =. 0
    for_i. i.#hull do.
        p =. ((i{hull)-1){points
        q =. ((((i+1)|~#hull){hull)-1){points
        sigma =. (((0{q)-0{p)*(y-(1{p)*d))-((1{q)-1{p)*(x-(0{p)*d)
        if. sigma<0 do.
            'outside' return.
        end.
        on =. on+.sigma=0
    end.
    if. on do. 'on' else. 'inside' end.
)
neighbor_order =: 3 : 0
    'site adjacent directed following' =. y
    first =. (site-1){following
    if. first=0 do.
        first =. <./adjacent
    end.
    result =. ,first
    while. (#result)<#adjacent do.
        result =. result,(<(site-1),({:result)-1){directed
    end.
    result
)
outward =: 3 : 0
    'points u v' =. y
    delta =. ((v-1){points)-(u-1){points
    reduce_direction (1{delta),-0{delta
)
bounded_area =: 3 : 0
    'site centers' =. y
    relative =. 0 2$0.0
    for_center. centers do.
        'x y d' =. center
        relative =. relative,((0.0+x)%d),(0.0+y)%d
    end.
    for_i. i.#relative do.
        relative =. ((i{relative)-site)i}relative
    end.
    total =. 0.0
    for_i. i.#relative do.
        p =. i{relative
        q =. ((i+1)|~#relative){relative
        total =. total+((0{p)*1{q)-(0{q)*1{p
    end.
    total%2.0
)
clipped_area =: 3 : 0
    'points site neighbors' =. y
    polygon =. 4 2$0.0 0.0 1000.0 0.0 1000.0 1000.0 0.0 1000.0
    'xs ys' =. (site-1){points
    for_neighbor. neighbors do.
        'xt yt' =. (neighbor-1){points
        c1 =. 0.0+2*(xt-xs)
        c2 =. 0.0+2*(yt-ys)
        c3 =. 0.0+(((xt*xt)+yt*yt)-xs*xs)-ys*ys
        clipped =. 0 2$0.0
        for_i. i.#polygon do.
            p =. i{polygon
            q =. ((i+1)|~#polygon){polygon
            fp =. ((c1*0{p)+c2*1{p)-c3
            fq =. ((c1*0{q)+c2*1{q)-c3
            if. fp<:0.0 do.
                clipped =. clipped,p
            end.
            if. ((fp<0.0)*.fq>0.0)+.((fq<0.0)*.fp>0.0) do.
                fraction =. fp%(fp-fq)
                clipped =. clipped,p+(q-p)*fraction
            end.
        end.
        polygon =. clipped
    end.
    total =. 0.0
    for_i. i.#polygon do.
        p =. i{polygon
        q =. ((i+1)|~#polygon){polygon
        total =. total+((0{p)*1{q)-(0{q)*1{p
    end.
    total%2.0
)
