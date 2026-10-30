event_graph =: 3 : 0
    edges =. (#Events)#<i.0
    for_i. i.#Events do.
        event =. i{Events
        p =. 0{event
        number =. 1{event
        if. number<#p{::ProcessEvents do.
            edges =. (<number{p{::ProcessEvents)i}edges
        end.
    end.
    for_index. Copies do.
        packet =. index{Packets
        if. (10{packet)>:0 do.
            sending =. 5{packet
            edges =. (<(sending{::edges),10{packet)sending}edges
        end.
    end.
    edges
)
graph_path =: 4 : 0
    'first last' =. x
    parents =. (#y)$_2
    parents =. _1 first}parents
    queue =. ,first
    head =. 0
    while. (head<#queue)*._2=last{parents do.
        current =. head{queue
        head =. head+1
        for_following. current{::y do.
            if. _2=following{parents do.
                parents =. current following}parents
                queue =. queue,following
            end.
        end.
    end.
    if. _2=last{parents do. i.0 return. end.
    result =. i.0
    current =. last
    while. current>:0 do. result =. current,result
        current =. current{parents
    end.
    result
)
concurrency_statistics =: 3 : 0
    ordered =. concurrent =. same_lamport =. inversions =. 0
    by_pair =. (N,N)$0
    for_i. i.#Events do.
        first =. i{Events
        for_j. (i+1)+i.(#Events)-(i+1) do.
            second =. j{Events
            if. '||'-:(i{EventVectors)relation j{EventVectors do.
                concurrent =. concurrent+1
                same_lamport =. same_lamport+(4{first)=4{second
                a =. (0{first)<.0{second
                b =. (0{first)>.0{second
                by_pair =. (1+(<a,b){by_pair)(<a,b)}by_pair
            else. ordered =. ordered+1
            end.
            inversions =. inversions+0>((3{first)-3{second)*((4{first)-4{second)
        end.
    end.
    (<ordered),(<concurrent),(<same_lamport),(<inversions),<by_pair
)
races_and_violations =: 3 : 0
    races =. violations =. 0 3$0
    fifo =. 0
    for_p. i.N do.
        deliveries =. p{::Delivered
        for_i. i.0>.(#deliveries)-1 do.
            a =. i{deliveries
            b =. (i+1){deliveries
            first_vector =. (5{a{Packets){EventVectors
            second_vector =. (5{b{Packets){EventVectors
            if. '||'-:first_vector relation second_vector do. races =. races,p,a,b end.
            for_j. (i+1)+i.(#deliveries)-(i+1) do.
                b =. j{deliveries
                second_vector =. (5{b{Packets){EventVectors
                if. second_vector before first_vector do.
                    violations =. violations,p,a,b
                    fifo =. fifo+(2{a{Packets)=2{b{Packets
                end.
            end.
        end.
    end.
    (<races),(<violations),<fifo
)
consistent_cut =: 3 : 0
    for_p. i.N do.
        count =. p{y
        if. count do.
            event =. (count-1){p{::ProcessEvents
            if. -.(event{EventVectors)less_equal y do. 0 return. end.
        end.
    end.
    1
)
enumerate_cuts =: 3 : 0
    limits =. i.0
    multipliers =. i.0
    product =. 1
    for_p. i.N do.
        count =. +/CutTime>:3{"1 (p{::ProcessEvents){Events
        limits =. limits,count
        multipliers =. multipliers,product
        product =. product*count+1
    end.
    levels =. (1++/limits)$0
    valid =. product$0
    amounts =. product$0
    counts =. (#Thresholds)$0
    consistent =. 0
    for_code. i.product do.
        cut =. (1+limits)|code floor_div multipliers
        if. consistent_cut cut do.
            valid =. 1 code}valid
            consistent =. consistent+1
            level =. +/cut
            levels =. (1+level{levels)level}levels
            balance =. 0
            for_p. i.N do. balance =. balance+p balance_at_cut p{cut end.
            amount =. (+/Initial)-balance
            amounts =. amount code}amounts
            counts =. counts+amount>:Thresholds
        end.
    end.
    predicates =. 0 3$0
    for_i. i.#Thresholds do.
        threshold =. i{Thresholds
        reachable =. product$0
        reachable =. 1 (0)}reachable
        avoids =. 0
        for_code. i.product do.
            if. (code{reachable)*.(code{valid)*.threshold>code{amounts do.
                if. code=product-1 do. avoids =. 1 end.
                cut =. (1+limits)|code floor_div multipliers
                for_p. i.N do.
                    if. (p{cut)<p{limits do.
                        following =. code+p{multipliers
                        if. following{valid do. reachable =. 1 following}reachable end.
                    end.
                end.
            end.
        end.
        predicates =. predicates,(i{counts),(0<i{counts),-.avoids
    end.
    (<limits),(<product),(<consistent),(<levels),<predicates
)
