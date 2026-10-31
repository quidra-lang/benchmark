inside =: 4 : 0
    point =. y
    parity =. 0
    for_index. i.#x do.
        first =. index{x
        second =. ((#x)|index+1){x
        if. ((1{first)>1{point)~:(1{second)>1{point do.
            low =. first
            high =. second
            if. (1{second)<1{first do.
                low =. second
                high =. first
            end.
            if. 0<cross low,high,:point do.
                parity =. -.parity
            end.
        end.
    end.
    parity
)
interior =: 4 : 0
    parity =. 0
    for_ring. x do.
        parity =. parity~:(>ring)inside y
    end.
    parity
)
boundary =: 4 : 0
    for_index. i.#x do.
        segment =. (index{x),:((#x)|index+1){x
        if. y on_segment segment do.
            1 return.
        end.
    end.
    0
)
rotate_ring =: 3 : 0
    index =. {. /:|."1 y
    index|.y
)
counterclockwise =: 3 : '0<cross (_1{y),(0{y),:1{y'
reverse_ring =: 3 : '(1{.y),|.}.y'
normalize_ring =: 4 : 0
    ring =. rotate_ring y
    if. x~:counterclockwise ring do.
        ring =. reverse_ring ring
    end.
    ring
)
sort_rings =: 3 : 0
    keys =. 0 2$0x
    for_ring. y do.
        keys =. keys,point_key 0{>ring
    end.
    (/:keys){y
)
assemble =: 3 : 0
    rotated =. rotate_ring&.>y
    depths =. (#y)$0
    for_index. i.#y do.
        point =. 0{index{::rotated
        depth =. 0
        for_other. (i.#y)-.index do.
            depth =. depth+(other{::rotated)inside point
        end.
        depths =. depth index}depths
    end.
    oriented =. 0$a:
    for_index. i.#y do.
        ring =. index{::rotated
        if. (counterclockwise ring)~:0=2|index{depths do.
            ring =. reverse_ring ring
        end.
        oriented =. oriented,<ring
    end.
    outer_indices =. I.0=2|depths
    keys =. 0 2$0x
    for_index. outer_indices do.
        keys =. keys,point_key 0{index{::oriented
    end.
    result =. 0$a:
    for_index. (/:keys){outer_indices do.
        outer =. index{::oriented
        holes =. 0$a:
        for_other. I.depths=1+index{depths do.
            ring =. other{::oriented
            if. outer inside 0{ring do.
                holes =. holes,<ring
            end.
        end.
        result =. result,<(<outer),sort_rings holes
    end.
    result
)
ring_area =: 3 : 0
    total =. 0.0
    for_index. i.#y do.
        'x1 y1' =. real"0 index{y
        'x2 y2' =. real"0 ((#y)|index+1){y
        total =. total+((x1*y2)-x2*y1)
    end.
    total%2.0
)
ring_perimeter =: 3 : 0
    total =. 0.0
    for_index. i.#y do.
        first =. real"0 index{y
        second =. real"0 ((#y)|index+1){y
        'dx dy' =. second-first
        total =. total+%:(dx*dx)+dy*dy
    end.
    total
)
