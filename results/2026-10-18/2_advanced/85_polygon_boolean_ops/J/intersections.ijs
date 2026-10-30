on_segment =: 4 : 0
    'first second' =. y
    if. 0~:cross first,second,:x do.
        0 return.
    end.
    (*/x>:(first<.second))*.*/x<:first>.second
)
touch =: 3 : 0
    'a b c d' =. y
    first =. (cross a,b,:c)*cross a,b,:d
    second =. (cross c,d,:a)*cross c,d,:b
    if. (first<0)*.second<0 do.
        1 return.
    end.
    (c on_segment a,:b)+.(d on_segment a,:b)+.(a on_segment c,:d)+.b on_segment c,:d
)
overlap =: 3 : 0
    'a b c d' =. y
    if. (0~:cross a,b,:c)+.0~:cross a,b,:d do.
        0 return.
    end.
    coordinate =. (0{a)=0{b
    aa =. coordinate{a
    bb =. coordinate{b
    cc =. coordinate{c
    dd =. coordinate{d
    ((aa<.bb)>.(cc<.dd))<((aa>.bb)<.(cc>.dd))
)
crossing =: 3 : 0
    'a b c d' =. y
    r =. b-a
    s =. d-c
    denominator =. ((0{r)*1{s)-(1{r)*0{s
    if. denominator=0 do.
        0$a: return.
    end.
    g =. c-a
    t =. (((0{g)*1{s)-(1{g)*0{s)%denominator
    u =. (((0{g)*1{r)-(1{g)*0{r)%denominator
    if. (t>0)*.(t<1)*.(u>0)*.u<1 do.
        (<t),(<u),<(a,:b)along t
    else.
        0$a:
    end.
)
clipping_point =: 4 : 0
    'a b' =. y
    x along a%a-b
)
