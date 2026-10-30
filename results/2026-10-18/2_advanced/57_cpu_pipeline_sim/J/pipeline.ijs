simulate =: 4 : 0
    variant =. x
    flags =. y
    'name forwarding stage latency' =. variant
    timings =. 0 5$0
    records =. 0 5$0
    delays =. i.0
    for_i. i.#Instructions do.
        instruction =. i{Instructions
        length =. 1
        if. 1=1{instruction do. length =. latency end.
        fetch =. 1
        decode =. 2
        start =. 3
        if. i do.
            previous =. (i-1){timings
            fetch =. 1{previous
            if. (i-1){flags do.
                fetch =. (2{previous)+-.stage id_resolved (i-1){Instructions
            end.
            decode =. (fetch+1)>.2{previous
            ideal =. 1+2{previous
            available =. 2#ideal
            producers =. 2$_1
            for_source. i{::Sources do.
                producer =. 1{source
                if. producer>:0 do.
                    ready =. variant source_ready (<instruction),(<producer{Instructions),<producer{timings
                    slot =. -.2=1{producer{Instructions
                    if. ready>slot{available do.
                        available =. ready slot}available
                        producers =. producer slot}producers
                    end.
                end.
            end.
            bounds =. (decode+1),(3{previous),available
            start =. ideal
            for_cause. i.4 do.
                bound =. cause{bounds
                if. bound>start do.
                    responsible =. i-(cause<2)
                    producer =. _1
                    if. cause>:2 do. producer =. (cause-2){producers end.
                    records =. records,cause,(bound-start),responsible,i,producer
                    start =. bound
                end.
            end.
            delays =. delays,start-ideal
        end.
        timings =. timings,fetch,decode,start,(start+length),start+length+1
    end.
    if. (1=1{_1{Instructions)*.latency>:2 do.
        records =. records,1,(latency-1),((#Instructions)-1),_1,_1
    end.
    (<timings),(<records),(<delays),<4{_1{timings
)
