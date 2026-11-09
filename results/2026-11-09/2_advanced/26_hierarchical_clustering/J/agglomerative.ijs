lance_williams =: 4 : 0
    'a b k' =. y
    merged =. a+b
    select. x
    case. 'single' do. 0.5 0.5 0 _0.5
    case. 'complete' do. 0.5 0.5 0 0.5
    case. 'average' do. (a%merged),(b%merged),0 0
    case. 'weighted' do. 0.5 0.5 0 0
    case. 'centroid' do.
        ((a%merged),(b%merged),(-a*b)%(merged*merged)),0
    case. 'median' do. 0.5 0.5 _0.25 0
    case. do.
        total =. a+b+k
        ((a+k)%total),((b+k)%total),(-k%total),0
    end.
)
agglomerate =: 4 : 0
    count =. #y
    capacity =. (2*count)-1
    squared =. (<x)e.'centroid';'median';'ward'
    values =. (capacity,capacity)$0.0
    for_i. i.count do.
        for_j. i.count do.
            value =. (<i,j){y
            if. squared do. value =. value*value end.
            values =. value (<i,j)}values
        end.
    end.
    sizes =. capacity$1
    active =. i.count
    merges =. 0$a:
    for_step. i.count-1 do.
        a =. 0{active
        b =. 1{active
        best =. (<a,b){values
        for_position. i.#active do.
            first =. position{active
            for_second. (position+1)}.active do.
                value =. (<first,second){values
                if. value<best do. a =. first
                    b =. second
                    best =. value end.
            end.
        end.
        node =. count+step
        size =. (a{sizes)+b{sizes
        sizes =. size node}sizes
        height =. best
        if. squared do. height =. %:height end.
        merges =. merges,<(<a),(<b),(<height),<size
        for_k. active do.
            if. k e.a,b do. continue. end.
            'alpha_a alpha_b beta gamma' =. x lance_williams (a{sizes),(b{sizes),k{sizes
            first =. (<a,k){values
            second =. (<b,k){values
            value =. alpha_a*first
            value =. value+alpha_b*second
            value =. value+beta*best
            value =. value+gamma*|first-second
            values =. value (<node,k)}values
            values =. value (<k,node)}values
        end.
        active =. (active#~-.active e.a,b),node
    end.
    merges
)
minimum_spanning_tree =: 3 : 0
    count =. #y
    in_tree =. 1,(count-1)$0
    keys =. 0{y
    parents =. count$0
    edges =. 0$a:
    for_step. i.count-1 do.
        chosen =. _1
        for_u. I.-.in_tree do.
            if. chosen<0 do. chosen =. u
            elseif. (u{keys)<chosen{keys do. chosen =. u end.
        end.
        in_tree =. 1 chosen}in_tree
        edges =. edges,<(<chosen{parents),(<chosen),<chosen{keys
        for_u. I.-.in_tree do.
            value =. (<chosen,u){y
            if. value<u{keys do. keys =. value u}keys
                parents =. chosen u}parents end.
        end.
    end.
    edges
)
