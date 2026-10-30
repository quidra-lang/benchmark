parse_action =: 3 : 0
    kind =. 0{::y
    if. (<kind)e.;:'LOCAL BROADCAST SNAPSHOT' do.
        (<kind),(<_1),(1{y),<0 return.
    end.
    destination =. _1
    if. -.'SENDER'-:1{::y do. destination =. Names i.<1{::y end.
    amount =. 0
    text =. 2{::y
    if. 'TRANSFER'-:kind do. amount =. ".text
        text =. 'transfer'
    end.
    (<kind),(<destination),(<text),<amount
)
read_scripts =: 3 : 0
    rows =. <;._2 (1!:1 <'input/programs.txt')
    initial =. i.0
    at =. rules =. N#<0$a:
    current =. _1
    for_row. rows do.
        fields =. split_words >row
        select. 0{::fields
        case. 'PROCESS' do.
            current =. current+1
            initial =. initial,".3{::fields
        case. 'AT' do.
            start =. ".1{::fields
            period =. 0
            first =. 2
            if. 'EVERY'-:2{::fields do. period =. ".3{::fields
                first =. 4
            end.
            entry =. (<start),(<period),<parse_action first}.fields
            at =. (<(current{::at),<entry)current}at
        case. 'ON' do.
            entry =. (1{fields),<parse_action 2}.fields
            rules =. (<(current{::rules),<entry)current}rules
        end.
    end.
    (<initial),(<at),<rules
)
initialize_processes =: 3 : 0
    Balance =: Initial
    Lamport =: MaxHeld =: MoneyIn =: MoneyOut =: Refused =: N$0
    MinimumBalance =: Initial
    VectorsState =: Broadcast =: (N,N)$0
    NextSequence =: (N,N)$1
    Reorder =: (N,N)$<i.0
    Holdback =: Delivered =: ProcessEvents =: BalanceHistory =: N#<i.0
    TypeCounts =: (N,5)$0
    0
)
expand_actions =: 3 : 0
    result =. 0$a:
    for_p. i.N do.
        for_entry. p{::At do.
            'start period action' =. >entry
            now =. start
            while. now<:EndTime do.
                entry =. (<now),(<p),<action
                result =. result,<entry
                if. period=0 do. break. end.
                now =. now+period
            end.
        end.
    end.
    result
)
balance_at_cut =: 4 : 0
    if. y=0 do. x{Initial else. (y-1){x{::BalanceHistory end.
)
held_count =: 3 : '(#y{::Holdback)++/#&>y{Reorder'
