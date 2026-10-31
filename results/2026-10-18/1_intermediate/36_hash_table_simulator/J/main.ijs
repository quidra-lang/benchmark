LF =: 10{a.
Modes =: ;:'CHAIN LINEAR QUADRATIC DOUBLE ROBINHOOD CUCKOO'
Commands =: ;:'CREATE MAXLOAD MINLOAD TRACE HASH PUT ADD GET DEL PROBE GEN GENDEL RESIZE CONVERT CLEAR DUMP MAP STATS KEYS TOP SCAN CLUSTERS DIST COMPARE BENCH'
Have =: Mode =: Size =: Tomb =: Tracing =: MinLoad =: 0
Cap =: 2
MaxLoad =: 75
Buckets =: Slots =: 0$a:
Counters =: 8#0
Error =: ''
number =: 3 : ',''0'' 8!:2 y'
join =: 4 : 0
    text =. ''
    for_i. i.#y do.
        if. i do. text =. text,x end.
        text =. text,i{::y
    end.
    text
)
fail =: 3 : 0
    Error =: y
    throw.
)
decimal =: 4 : 0
    if. y=0 do. '0.00' return. end.
    q =. <.(100*x)%y
    (number <.q%100),'.',_2{.'00',number 100|q
)
prime =: 3 : '4 p: y-1'
hash =: 4 : 0
    'base modulus' =. x
    value =. 0
    for_code. a.i.y do. value =. modulus|code+base*value end.
    value
)
slot_count =: 3 : 'Cap*(1+Mode=5)'
position =: 3 : 0
    if. Mode=5 do.
        'T',(number 1+<.y%Cap),'.',number Cap|y
    else. number y end.
)
distance =: 4 : 'Cap|x-(31,Cap) hash y'
content =: 3 : 0
    select. #y
    case. 0 do. '-'
    case. 1 do. 'D'
    case. do. 0{::y
    end.
)
pair_text =: 3 : '(0{::y),''='',number 1{::y'
gauge =: 3 : '(10<.y){''0123456789+'''
tally =: 4 : 0
    Counters =: (y+x{Counters) x}Counters
)
snapshot =: 3 : 'Have;Mode;Cap;Size;Tomb;Buckets;Slots;<Counters'
restore =: 3 : 0
    'Have Mode Cap Size Tomb Buckets Slots Counters' =: y
)
new_table =: 4 : 0
    Mode =: x
    Cap =: y
    Have =: 1
    Size =: Tomb =: 0
    Counters =: 8#0
    Buckets =: Slots =: 0$a:
    if. Mode=0 do. Buckets =: Cap#<0$a:
    else. Slots =: (slot_count '')#<i.0 end.
)
items =: 3 : 0
    if. Mode=0 do. ;Buckets
    else. Slots#~2=#&>Slots end.
)
item_keys =: 3 : 0
    if. 0=#y do. 0$a: else. 0&{::&.>y end.
)
sorted_items =: 3 : '(/:s:item_keys y){y'

search =: 4 : 0
    p =. chain =. available =. _1
    probes =. 0
    path =. 0$a:
    home =. (31,Cap) hash y
    if. Mode=0 do.
        bucket =. home{::Buckets
        for_i. i.#bucket do.
            key =. 0{::i{::bucket
            probes =. probes+1
            if. x do. path =. path,<(number home),':',key end.
            if. key-:y do. p =. home [ chain =. i break. end.
        end.
    elseif. Mode=5 do.
        for_q. home,Cap+(37,Cap) hash y do.
            item =. q{::Slots
            probes =. probes+1
            if. x do. path =. path,<(position q),':',content item end.
            if. 2=#item do.
                if. y-:0{::item do. p =. q break. end.
            end.
        end.
    else.
        step =. 1+(37,Cap-1) hash y
        for_i. i.Cap do.
            select. Mode
            case. 2 do. q =. Cap|home+i*i
            case. 3 do. q =. Cap|home+i*step
            case. do. q =. Cap|home+i
            end.
            item =. q{::Slots
            probes =. probes+1
            if. x do. path =. path,<(position q),':',content item end.
            if. 0=#item do.
                if. available=_1 do. available =. q end.
                break.
            elseif. 1=#item do.
                if. available=_1 do. available =. q end.
            else.
                if. y-:0{::item do. p =. q break. end.
                if. Mode=4 do.
                    if. i>q distance 0{::item do. break. end.
                end.
            end.
        end.
    end.
    p;chain;probes;available;<path
)
item_at =: 3 : 0
    p =. 0{::y
    if. Mode=0 do. (1{::y){::p{::Buckets else. p{::Slots end.
)
change_item =: 4 : 0
    p =. 0{::x
    if. Mode=0 do.
        bucket =. p{::Buckets
        bucket =. (<y) (1{::x)}bucket
        Buckets =: (<bucket) p}Buckets
    else. Slots =: (<y) p}Slots end.
)
place =: 3 : 0
    'item initial tracing' =. y
    key =. 0{::item
    p =. _1
    success =. 1
    reused =. shifted =. kicks =. 0
    homeless =. i.0
    moves =. 0$a:
    if. Mode=0 do.
        p =. (31,Cap) hash key
        Buckets =: (<(p{::Buckets),<item) p}Buckets
    elseif. Mode e.1 2 3 do.
        if. 0=#initial do. initial =. 0 search key end.
        p =. 3{::initial
        if. p=_1 do. success =. 0 [ homeless =. item
        else.
            reused =. 1=#p{::Slots
            Tomb =: Tomb-reused
            Slots =: (<item) p}Slots
        end.
    elseif. Mode=4 do.
        q =. (31,Cap) hash key
        d =. 0
        origin =. _1
        while. 1 do.
            other =. q{::Slots
            if. 0=#other do.
                Slots =: (<item) q}Slots
                if. p=_1 do. p =. q end.
                if. tracing*.origin>:0 do.
                    moves =. moves,<'SHIFT ',(0{::item),' ',(number origin),' -> ',number q
                end.
                break.
            end.
            old_distance =. q distance 0{::other
            if. old_distance<d do.
                Slots =: (<item) q}Slots
                if. p=_1 do. p =. q end.
                if. tracing*.origin>:0 do.
                    moves =. moves,<'SHIFT ',(0{::item),' ',(number origin),' -> ',number q
                end.
                item =. other
                origin =. q
                d =. old_distance
                shifted =. shifted+1
            end.
            q =. Cap|q+1
            d =. d+1
        end.
    else.
        part =. 0
        while. 1 do.
            q =. (part*Cap)+((31+6*part),Cap) hash 0{::item
            other =. q{::Slots
            if. 0=#other do.
                Slots =: (<item) q}Slots
                p =. 0{::0 search key
                break.
            end.
            if. kicks=Cap do. success =. 0 [ homeless =. item break. end.
            Slots =: (<item) q}Slots
            kicks =. kicks+1
            if. tracing do. moves =. moves,<'KICK ',(0{::other),' ',position q end.
            item =. other
            part =. 1-part
        end.
    end.
    success;p;reused;shifted;kicks;homeless;<moves
)
remove_item =: 4 : 0
    p =. 0{::x
    moves =. 0$a:
    shifted =. 0
    if. Mode=0 do.
        bucket =. p{::Buckets
        bucket =. ((i.#bucket)~:1{::x)#bucket
        Buckets =: (<bucket) p}Buckets
    elseif. Mode e.1 2 3 do.
        Slots =: (<,_1) p}Slots
        Tomb =: Tomb+1
    else.
        Slots =: (<i.0) p}Slots
        if. Mode=4 do.
            q =. Cap|p+1
            while. 1 do.
                item =. q{::Slots
                if. 0=#item do. break. end.
                if. 0=q distance 0{::item do. break. end.
                destination =. Cap|q-1
                Slots =: (<item) destination}Slots
                Slots =: (<i.0) q}Slots
                if. y do.
                    moves =. moves,<'SHIFT ',(0{::item),' ',(number q),' -> ',number destination
                end.
                shifted =. shifted+1
                q =. Cap|q+1
            end.
        end.
    end.
    Size =: Size-1
    shifted;<moves
)

rebuild =: 4 : 0
    saved =. snapshot ''
    (0{x) new_table 1{x
    for_item. y do.
        result =. place (>item);(i.0);0
        if. -.0{::result do.
            restore saved
            0 return.
        end.
        Size =: Size+1
    end.
    Counters =: 7{::saved
    1
)
automatic =: 3 : 0
    'reason capacity pending' =. y
    old =. Cap
    list =. items ''
    if. #pending do. list =. list,<pending end.
    while. -.(Mode,capacity) rebuild list do. capacity =. prime 2*capacity end.
    1 tally 1
    'REHASH ',reason,' ',(number old),' -> ',number Cap
)
load_check =: 3 : 0
    rows =. 0$a:
    if. (100*Size+Tomb)>MaxLoad*slot_count '' do.
        if. (200*Size)>MaxLoad*slot_count '' do.
            rows =. <automatic 'load';(prime 2*Cap);<i.0
        else. rows =. <automatic 'tomb';Cap;<i.0 end.
    end.
    rows
)
shrink_check =: 3 : 0
    rows =. 0$a:
    capacity =. prime <.Cap%2
    small_slots =. capacity*(1+Mode=5)
    if. ((100*Size)<MinLoad*slot_count '')*.(capacity<Cap)*.(100*Size)<:MaxLoad*small_slots do.
        old =. Cap
        if. (Mode,capacity) rebuild items '' do.
            1 tally 1
            rows =. <'REHASH shrink ',(number old),' -> ',number Cap
        end.
    end.
    rows
)
trace_path =: 3 : 0
    if. #y do. <'PATH ',' ' join y else. <'PATH none' end.
)
put =: 4 : 0
    'command key value' =. y
    initial =. x search key
    'p chain probes available path' =. initial
    0 tally probes
    trace =. 0$a:
    if. x do. trace =. trace_path path end.
    rehashes =. 0$a:
    if. p>:0 do.
        old =. 1{::item_at initial
        if. command-:'ADD' do. value =. old+value end.
        initial change_item key;value
        3 tally 1
        row =. command,' ',key,'=',(number value),' UPDATED old=',(number old),' at=',(position p),' probes=',number probes
        0;rehashes;<(<row),trace return.
    end.
    'success p reused shifted kicks homeless moves' =. place (key;value);initial;x
    Size =: Size+1
    2 tally 1
    row =. command,' ',key,'=',(number value),' NEW'
    if. success do.
        row =. row,' at=',(position p),' probes=',number probes
        if. reused do. row =. row,' reused' end.
        if. Mode=4 do. row =. row,' shifted=',number shifted end.
        if. Mode=5 do. row =. row,' kicks=',number kicks end.
    else.
        row =. row,' probes=',number probes
        reason =. 'full'
        if. Mode=5 do.
            reason =. 'kicks'
            row =. row,' kicks=',(number kicks),' failed'
        else. row =. row,' full' end.
        rehashes =. <automatic reason;(prime 2*Cap);<homeless
    end.
    rehashes =. rehashes,load_check ''
    1;rehashes;<(<row),trace,moves,rehashes
)
get =: 4 : 0
    found =. x search y
    'p chain probes available path' =. found
    0 tally probes
    if. p=_1 do.
        5 tally 1
        row =. 'GET ',y,' NOT FOUND probes=',number probes
    else.
        4 tally 1
        row =. 'GET ',(pair_text item_at found),' at=',(position p),' probes=',number probes
    end.
    rows =. <row
    if. x do. rows =. rows,trace_path path end.
    rows
)
delete =: 4 : 0
    found =. x search y
    'p chain probes available path' =. found
    0 tally probes
    trace =. rehashes =. 0$a:
    if. x do. trace =. trace_path path end.
    if. p=_1 do.
        7 tally 1
        row =. 'DEL ',y,' NOT FOUND probes=',number probes
        0;rehashes;<(<row),trace return.
    end.
    'shifted moves' =. found remove_item x
    6 tally 1
    row =. 'DEL ',y,' OK at=',(position p),' probes=',number probes
    if. Mode=4 do. row =. row,' shifted=',number shifted end.
    rehashes =. shrink_check ''
    1;rehashes;<(<row),trace,moves,rehashes
)

costs =: 3 : 0
    result =. 0$a:
    if. Mode=0 do.
        for_p. i.Cap do.
            bucket =. p{::Buckets
            for_i. i.#bucket do.
                result =. result,<(0{::i{::bucket);(i+1);p
            end.
        end.
    else.
        for_p. I.2=#&>Slots do.
            key =. 0{::p{::Slots
            if. Mode=5 do. cost =. 1+<.p%Cap
            elseif. Mode e.1 4 do. cost =. 1+p distance key
            else. cost =. 2{::0 search key end.
            result =. result,<key;cost;p
        end.
    end.
    result
)
cost_values =: 3 : 0
    if. 0=#y do. i.0 else. 1&{::&>y end.
)
metrics =: 3 : 0
    values =. cost_values costs ''
    (>./0,values);(+/values) decimal Size
)
dump =: 3 : 0
    rows =. <'DUMP ',(Mode{::Modes),' cap=',(number Cap),' size=',(number Size),' tomb=',number Tomb
    if. Mode=0 do.
        for_p. i.Cap do.
            bucket =. p{::Buckets
            text =. '-'
            if. #bucket do. text =. ' ' join pair_text&.>bucket end.
            rows =. rows,<(number p),' ',text
        end.
    else.
        for_p. i.#Slots do.
            item =. p{::Slots
            text =. content item
            if. 2=#item do.
                text =. pair_text item
                if. Mode=4 do. text =. text,' d=',number p distance 0{::item end.
            end.
            prefix =. number p
            if. Mode=5 do. prefix =. 'T',(number 1+<.p%Cap),' ',number Cap|p end.
            rows =. rows,<prefix,' ',text
        end.
    end.
    rows
)
map_report =: 3 : 0
    rows =. <'MAP ',(Mode{::Modes),' cap=',number Cap
    chars =. (slot_count '')#'.'
    if. Mode=0 do.
        counts =. #&>Buckets
        occupied =. I.counts>0
        chars =. (gauge"0 occupied{counts) occupied}chars
    else.
        chars =. 'D' (I.1=#&>Slots)}chars
        for_record. costs '' do.
            'key cost p' =. >record
            if. Mode=5 do. mark =. '#' else. mark =. gauge cost-1 end.
            chars =. mark p}chars
        end.
    end.
    for_part. i.1+Mode=5 do.
        section =. Cap{.(part*Cap)}.chars
        prefix =. ''
        if. Mode=5 do. prefix =. 'T',(number part+1),' ' end.
        for_start. 40*i.>.Cap%40 do.
            text =. (40<.Cap-start){.start}.section
            rows =. rows,<prefix,(_5{.'00000',number start),' ',text
        end.
    end.
    rows
)
statistics =: 3 : 0
    'longest average' =. metrics ''
    rows =. <'STATS ',(Mode{::Modes),' size=',(number Size),' cap=',(number Cap),' slots=',(number slot_count ''),' tomb=',(number Tomb),' load=',((100*Size) decimal slot_count ''),'% longest=',(number longest),' avg=',average,' probes=',(number 0{Counters),' rehashes=',number 1{Counters
    labels =. ;:'inserts updates hits misses deletes absent'
    fields =. 0$a:
    for_i. i.6 do. fields =. fields,<(i{::labels),'=',number (i+2){Counters end.
    rows,<'OPS ',' ' join fields
)
scan =: 3 : 0
    'cursor limit' =. y
    keys =. 0$a:
    while. (cursor<slot_count '')*.limit>#keys do.
        if. Mode=0 do. keys =. keys,item_keys cursor{::Buckets
        else.
            item =. cursor{::Slots
            if. 2=#item do. keys =. keys,<0{::item end.
        end.
        cursor =. cursor+1
    end.
    if. cursor=slot_count '' do. cursor =. 0 end.
    <' ' join (<'SCAN next=',number cursor),keys
)
runs =: 3 : 0
    if. *./y do. ,#y return. end.
    lengths =. i.0
    length =. 0
    for_occupied. (1+y i.0)|.y do.
        if. occupied do. length =. length+1
        elseif. length do.
            lengths =. lengths,length
            length =. 0
        end.
    end.
    lengths
)
histogram =: 3 : 0
    rows =. 0$a:
    for_value. /:~~.y do.
        frequency =. +/y=value
        bar =. (50<.frequency)#'#'
        if. frequency>50 do. bar =. bar,'+' end.
        rows =. rows,<(number value),' ',(number frequency),' ',bar
    end.
    rows
)
clusters =: 3 : 0
    if. Mode=0 do. values =. (#&>Buckets)-.0
    elseif. Mode=5 do.
        occupied =. 0<#&>Slots
        values =. (runs Cap{.occupied),runs Cap}.occupied
    else. values =. runs 0<#&>Slots end.
    (<'CLUSTERS runs=',(number #values),' longest=',number >./0,values),histogram values
)
generated_keys =: 3 : 0
    'count length state' =. y
    state =. x:state
    keys =. 0$a:
    for_i. i.count do.
        key =. ''
        for_j. i.length do.
            state =. 2147483647x|48271x*state
            key =. key,(97+26|state){a.
        end.
        keys =. keys,<key
    end.
    keys
)
compare =: 3 : 0
    saved =. snapshot ''
    list =. sorted_items items ''
    rows =. <'COMPARE keys=',(number #list),' cap=',number y
    for_mode. i.#Modes do.
        mode new_table y
        for_item. list do. 0 put (<'PUT'),>item end.
        'longest average' =. metrics ''
        rows =. rows,<(mode{::Modes),' cap=',(number Cap),' longest=',(number longest),' avg=',average,' probes=',(number 0{Counters),' rehashes=',number 1{Counters
    end.
    restore saved
    rows
)
bench =: 3 : 0
    'capacity count length seed' =. y
    saved =. snapshot ''
    keys =. generated_keys (2*count),length,seed
    rows =. <'BENCH cap=',(number capacity),' count=',(number count),' len=',(number length),' seed=',number seed
    for_mode. i.#Modes do.
        mode new_table capacity
        for_i. i.count do. 0 put 'PUT';(i{::keys);i+1 end.
        misses =. probes =. 0
        for_key. count}.keys do.
            found =. 0 search >key
            if. _1=0{::found do.
                misses =. misses+1
                probes =. probes+2{::found
            end.
        end.
        average =. 1{::metrics ''
        rows =. rows,<(mode{::Modes),' cap=',(number Cap),' keys=',(number Size),' hit=',average,' misses=',(number misses),' miss=',(probes decimal misses),' rehashes=',number 1{Counters
    end.
    restore saved
    rows
)
check_capacity =: 3 : 0
    if. (y<2)+.y>10000 do. fail 'BAD CAPACITY' end.
    y
)
check_mode =: 3 : 0
    mode =. Modes i.<y
    if. mode=#Modes do. fail 'BAD MODE ',y end.
    mode
)
check_generation =: 3 : 0
    if. +./(y<1)+.y>500 10 2147483646 do. fail 'BAD ARGUMENT' end.
    y
)
execute =: 3 : 0
    words =. <;._1 ' ',y
    command =. 0{::words
    if. -. (<command)e.Commands do. fail 'UNKNOWN COMMAND ',command end.
    select. command
    case. 'CREATE' do.
        mode =. check_mode 1{::words
        capacity =. prime check_capacity 0".2{::words
        mode new_table capacity
        <'CREATE ',(Mode{::Modes),' cap=',number Cap return.
    case. 'MAXLOAD' do.
        value =. 0".1{::words
        if. (value<10)+.value>95 do. fail 'BAD LOAD' end.
        MaxLoad =: value
        <y return.
    case. 'MINLOAD' do.
        value =. 0".1{::words
        if. value>40 do. fail 'BAD LOAD' end.
        MinLoad =: value
        <y return.
    case. 'TRACE' do.
        flag =. 1{::words
        if. -. (<flag)e.;:'ON OFF' do. fail 'BAD ARGUMENT' end.
        Tracing =: flag-:'ON'
        <y return.
    case. 'HASH' do.
        key =. 1{::words
        capacity =. check_capacity 0".2{::words
        <'HASH ',key,' m=',(number capacity),' h31=',(number (31,capacity) hash key),' h37=',(number (37,capacity) hash key),' step=',number 1+(37,capacity-1) hash key return.
    case. 'BENCH' do.
        capacity =. prime check_capacity 0".1{::words
        args =. check_generation 0".&>2}.words
        bench capacity,args return.
    end.
    if. -.Have do. fail 'NO TABLE' end.
    select. command
    case. 'PUT';'ADD' do.
        2{::Tracing put command;(1{::words);0".2{::words
    case. 'GET' do. Tracing get 1{::words
    case. 'DEL' do. 2{::Tracing delete 1{::words
    case. 'PROBE' do.
        'p chain probes available path' =. 1 search 1{::words
        ending =. ((p>:0){::'MISS';'FOUND'),' probes=',number probes
        <' ' join (<'PROBE ',1{::words),path,<ending
    case. 'GEN';'GENDEL' do.
        args =. check_generation 0".&>}.words
        count =. {.args
        keys =. generated_keys args
        successes =. 0
        rows =. 0$a:
        for_i. i.count do.
            if. command-:'GEN' do. result =. 0 put 'PUT';(i{::keys);i+1
            else. result =. 0 delete i{::keys end.
            successes =. successes+0{::result
            rows =. rows,1{::result
        end.
        if. command-:'GEN' do.
            summary =. 'GEN ',(number count),' new=',(number successes),' updated=',number count-successes
        else.
            summary =. 'GENDEL ',(number count),' deleted=',(number successes),' missing=',number count-successes
        end.
        rows,<summary
    case. 'RESIZE';'CONVERT' do.
        mode =. Mode
        capacity =. Cap
        if. command-:'RESIZE' do. capacity =. prime check_capacity 0".1{::words
        else. mode =. check_mode 1{::words end.
        if. (100*Size)>MaxLoad*capacity*(1+mode=5) do. fail 'TOO SMALL' end.
        if. command-:'RESIZE' do. row =. 'RESIZE ',(number Cap),' -> ',number capacity
        else. row =. 'CONVERT ',(Mode{::Modes),' -> ',(mode{::Modes),' cap=',number capacity end.
        if. -. (mode,capacity) rebuild items '' do. fail 'REBUILD FAILED' end.
        <row
    case. 'CLEAR' do.
        row =. 'CLEAR ',number Size
        saved =. Counters
        Mode new_table Cap
        Counters =: saved
        <row
    case. 'DUMP' do. dump ''
    case. 'MAP' do. map_report ''
    case. 'STATS' do. statistics ''
    case. 'KEYS' do. <' ' join (<'KEYS ',number Size),item_keys sorted_items items ''
    case. 'TOP' do.
        limit =. 0".1{::words
        if. (limit<1)+.limit>100 do. fail 'BAD ARGUMENT' end.
        records =. costs ''
        records =. (/:s:item_keys records){records
        records =. (\:cost_values records){records
        records =. (limit<.#records){.records
        rows =. <'TOP ',number #records
        for_record. records do.
            'key cost p' =. >record
            rows =. rows,<key,' cost=',(number cost),' at=',position p
        end.
        rows
    case. 'SCAN' do.
        'cursor limit' =. 0".&>}.words
        if. (limit<1)+.limit>100 do. fail 'BAD ARGUMENT' end.
        if. cursor>:slot_count '' do. fail 'BAD CURSOR' end.
        scan cursor,limit
    case. 'CLUSTERS' do. clusters ''
    case. 'DIST' do.
        values =. cost_values costs ''
        (<'DIST keys=',(number Size),' longest=',number >./0,values),histogram values
    case. 'COMPARE' do. compare prime check_capacity 0".1{::words
    end.
)
main =: 3 : 0
    count =. 0".1!:1 3
    for_i. i.count do.
        try. rows =. execute 1!:1 3
        catcht. rows =. <'ERROR ',Error
        end.
        for_row. rows do. ((>row),LF) 1!:2 4 end.
    end.
)
main ''
exit 0
