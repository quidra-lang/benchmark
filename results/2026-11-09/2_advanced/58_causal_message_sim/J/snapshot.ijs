new_snapshot =: 4 : 0
    records =. N#<0$a:
    states =. (N*N)#<i.0
    markers =. (N*N)$_1
    (<x),(<y),(<_1),(<records),(<states),(<markers),(<markers),(<0),<0 2$0
)
snapshot_record =: 4 : 0
    shot =. x
    'p now reason' =. y
    snapshot =. shot{::Snapshots
    record =. (<now),(<reason),(<p{Balance),(<p{Lamport),(<p{VectorsState),<p{::Holdback
    records =. 3{::snapshot
    records =. (<record)p}records
    snapshot =. (<records)3}snapshot
    Snapshots =: (<snapshot)shot}Snapshots
    0
)
accept_marker =: 4 : 0
    shot =. x
    'channel now' =. y
    snapshot =. shot{::Snapshots
    markers =. 6{::snapshot
    markers =. now channel}markers
    count =. 1+7{::snapshot
    snapshot =. (<markers)6}snapshot
    snapshot =. (<count)7}snapshot
    if. count=N*(N-1) do. snapshot =. (<now)2}snapshot end.
    Snapshots =: (<snapshot)shot}Snapshots
    0
)
snapshot_cut =: 3 : 0
    result =. i.0
    for_p. i.N do.
        result =. result,p{4{::p{::3{::y
    end.
    result
)
cut_details =: 3 : 0
    orphans =. transit =. i.0
    amounts =. balances =. 0
    for_packet_index. Copies do.
        packet =. packet_index{Packets
        sent =. (1{(5{packet){Events)<:(2{packet){y
        received =. 0
        if. (10{packet)>:0 do. received =. (1{(10{packet){Events)<:(3{packet){y end.
        if. received*.-.sent do. orphans =. orphans,packet_index end.
        if. sent*.-.received do.
            transit =. transit,packet_index
            amounts =. amounts+3{::(4{packet){::Messages
        end.
    end.
    for_p. i.N do. balances =. balances+p balance_at_cut p{y end.
    (<orphans),(<transit),(<balances),<balances+amounts
)
recorded_copies =: 3 : 0
    entries =. pending =. i.0
    for_channel. ChannelOrder do. entries =. entries,channel{::4{::y end.
    for_record. 3{::y do. pending =. pending,5{::>record end.
    (<entries),<pending
)
transit_match =: 4 : '(/:~x)-:/:~y'
vector_consistent =: 4 : 0
    for_record. 3{::x do.
        if. -.(4{::>record)less_equal y do. 0 return. end.
    end.
    1
)
