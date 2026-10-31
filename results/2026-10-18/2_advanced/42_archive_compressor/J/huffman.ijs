tree_lengths =: 3 : 0
    lengths =. (#y)$0
    nodes =. 0 5$0x
    active =. i.0
    for_symbol. I.y>0 do.
        active =. active,#nodes
        nodes =. nodes,(symbol{y),symbol,symbol,_1,_1
    end.
    if. 0=#active do.
        lengths return.
    end.
    if. 1=#active do.
        symbol =. (<({.active),2){nodes
        lengths =. 1 symbol}lengths
        lengths return.
    end.
    while. 1<#active do.
        order =. /:0 1{"1 active{nodes
        chosen =. (2{.order){active
        active =. (2}.order){active
        first =. (0{chosen){nodes
        second =. (1{chosen){nodes
        active =. active,#nodes
        nodes =. nodes,((0{first)+0{second),((1{first)<.1{second),_1,chosen
    end.
    pending =. ,:({.active),0
    while. #pending do.
        'node_index depth' =. {:pending
        pending =. }:pending
        node =. node_index{nodes
        symbol =. 2{node
        if. symbol>:0 do.
            lengths =. depth symbol}lengths
        else.
            pending =. pending,(3{node),depth+1
            pending =. pending,(4{node),depth+1
        end.
    end.
    lengths
)
limited_lengths =: 4 : 0
    maximum =. x
    weights =. y
    halvings =. 0
    lengths =. tree_lengths weights
    while. (>./lengths)>maximum do.
        weights =. (weights+1)intdiv 2
        halvings =. halvings+1
        lengths =. tree_lengths weights
    end.
    (<lengths),<halvings
)
canonical_codes =: 3 : 0
    lengths =. y
    used =. I.lengths>0
    order =. /:(used{lengths),.used
    ordered =. order{used
    codes =. (#lengths)$0x
    code =. 0x
    previous =. 0
    for_index. i.#ordered do.
        symbol =. index{ordered
        length =. symbol{lengths
        if. index do.
            code =. (code+1)*2x^length-previous
        end.
        codes =. code symbol}codes
        previous =. length
    end.
    codes
)
