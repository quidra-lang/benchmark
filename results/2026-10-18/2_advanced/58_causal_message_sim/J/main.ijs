load 'network.ijs'
load 'clocks.ijs'
load 'processes.ijs'
load 'snapshot.ijs'
load 'analysis.ijs'
EventTypes =: ;:'LOCAL NOFUNDS SEND BCAST RECV'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
words =: 3 : ''' ''join integer&.>y'
yes =: 3 : 'y{::;:''no yes'''
message_name =: 3 : '''m'',integer y+1'
name_list =: 3 : ''',''join y{Names'
read_params =: 3 : 0
    rows =. <;._2 (1!:1 <'input/params.txt')
    Comparisons =: Cuts =: 0$a:
    Thresholds =: i.0
    for_row. rows do.
        fields =. split_words >row
        select. 0{::fields
        case. 'SEED' do. Seed =: ".1{::fields
        case. 'END' do. EndTime =: ".1{::fields
        case. 'CUTCOUNT' do. CutTime =: ".1{::fields
        case. 'COMPARE' do. Comparisons =: Comparisons,<}.fields
        case. 'CUT' do. Cuts =: Cuts,<".&>}.fields
        case. 'PREDICATE' do. Thresholds =: Thresholds,".1{::fields
        end.
    end.
    0
)
item_less =: 4 : 0
    first =. 3{.x
    second =. 3{.y
    different =. I.first~:second
    if. 0=#different do. 0 else. (({.different){first)<({.different){second end.
)
enqueue =: 3 : 0
    'now process kind payload' =. y
    Creation =: Creation+1
    item =. now,process,Creation,kind,payload
    index =. #Queue
    Queue =: Queue,item
    while. index>0 do.
        parent =. (index-1)floor_div 2
        if. -.item item_less parent{Queue do. break. end.
        Queue =: (parent{Queue)index}Queue
        index =. parent
    end.
    Queue =: item index}Queue
    0
)
queue_pop =: 3 : 0
    result =. 0{Queue
    last =. _1{Queue
    Queue =: }:Queue
    if. #Queue do.
        index =. 0
        while. (1+2*index)<#Queue do.
            child =. 1+2*index
            if. (child+1)<#Queue do.
                if. ((child+1){Queue)item_less child{Queue do. child =. child+1 end.
            end.
            if. -.(child{Queue)item_less last do. break. end.
            Queue =: (child{Queue)index}Queue
            index =. child
        end.
        Queue =: last index}Queue
    end.
    result
)
new_packet =: 3 : 0
    index =. #Packets
    Packets =: Packets,y,0 0 0 _1 _1 0 0
    Missing =: Missing,<i.0
    index
)
dispatch_packet =: 3 : 0
    packet =. y{Packets
    source =. 2{packet
    destination =. 3{packet
    vector =. i.0
    if. 0=0{packet do. vector =. (5{packet){EventVectors end.
    'sequence arrival' =. (destination+N*source)channel_dispatch (<CurrentTime),(<0{packet),<vector
    packet =. sequence 6}packet
    packet =. CurrentTime 7}packet
    packet =. arrival 8}packet
    Packets =: packet y}Packets
    enqueue arrival,destination,1,y
    0
)
record_event =: 3 : 0
    'p kind message packet destination amount label sending' =. y
    if. kind=4 do. p receive_clock sending else. local_clock p end.
    index =. #Events
    number =. 1+#p{::ProcessEvents
    Events =: Events,p,number,kind,CurrentTime,(p{Lamport),(p{Balance),message,packet,destination,amount
    EventVectors =: EventVectors,p{VectorsState
    Labels =: Labels,<label
    ProcessEvents =: (<(p{::ProcessEvents),index)p}ProcessEvents
    BalanceHistory =: (<(p{::BalanceHistory),p{Balance)p}BalanceHistory
    TypeCounts =: (1+(<p,kind){TypeCounts)(<p,kind)}TypeCounts
    MinimumBalance =: ((p{MinimumBalance)<.p{Balance)p}MinimumBalance
    Timeline =: Timeline,0,index,p,CurrentTime
    index
)
record_snapshot =: 3 : 0
    'shot p reason' =. y
    shot snapshot_record (<p),(<CurrentTime),<reason
    Timeline =: Timeline,1,shot,p,CurrentTime
    for_destination. i.N do.
        if. destination~:p do.
            snapshot =. shot{::Snapshots
            markers =. 5{::snapshot
            channel =. destination+N*p
            markers =. CurrentTime channel}markers
            snapshot =. (<markers)5}snapshot
            Snapshots =: (<snapshot)shot}Snapshots
            packet =. new_packet 1,shot,p,destination,_1,_1
            dispatch_packet packet
        end.
    end.
    0
)
initiate_snapshot =: 4 : 0
    p =. x
    shot =. _1
    for_i. i.#Snapshots do.
        if. y-:0{::i{::Snapshots do. shot =. i end.
    end.
    if. shot<0 do.
        shot =. #Snapshots
        Snapshots =: Snapshots,<y new_snapshot CurrentTime
    end.
    snapshot =. shot{::Snapshots
    if. #p{::3{::snapshot do.
        ignored =. 8{::snapshot
        ignored =. ignored,p,CurrentTime
        snapshot =. (<ignored)8}snapshot
        Snapshots =: (<snapshot)shot}Snapshots
    else.
        record_snapshot (<shot),(<p),<'initiate'
    end.
    0
)
send_message =: 4 : 0
    p =. x
    'action sender' =. y
    'kind destination tag amount' =. action
    if. destination<0 do. destination =. sender end.
    if. 'TRANSFER'-:kind do.
        if. amount>p{Balance do.
            Refused =: (1+p{Refused)p}Refused
            record_event (<p),(<1),(<_1),(<_1),(<destination),(<amount),(<''),<_1
            0 return.
        end.
        Balance =: ((p{Balance)-amount)p}Balance
        MoneyOut =: (amount+p{MoneyOut)p}MoneyOut
    end.
    broadcast =. 'BROADCAST'-:kind
    if. broadcast do. Broadcast =: (1+(<p,p){Broadcast)(<p,p)}Broadcast end.
    message_index =. #Messages
    event_type =. 2+broadcast
    sending =. record_event (<p),(<event_type),(<message_index),(<_1),(<destination),(<amount),(<''),<_1
    stamp =. i.0
    if. broadcast do. stamp =. p{Broadcast end.
    message =. (<broadcast),(<p),(<tag),(<amount),(<stamp),(<CurrentTime),(<sending),<i.0
    Messages =: Messages,<message
    for_target. i.N do.
        if. (broadcast*.target~:p)+.((-.broadcast)*.target=destination) do.
            packet_index =. new_packet 0,_1,p,target,message_index,sending
            Copies =: Copies,packet_index
            message =. message_index{::Messages
            message =. (<(7{::message),packet_index)7}message
            Messages =: (<message)message_index}Messages
            dispatch_packet packet_index
        end.
    end.
    0
)
perform_action =: 4 : 0
    p =. x
    'action sender' =. y
    'kind destination text amount' =. action
    select. kind
    case. 'LOCAL' do.
        record_event (<p),(<0),(<_1),(<_1),(<_1),(<0),(<text),<_1
    case. 'SNAPSHOT' do. p initiate_snapshot text
    case. do. p send_message (<action),<sender
    end.
    0
)
process_marker =: 4 : 0
    p =. x
    packet =. y{Packets
    shot =. 1{packet
    if. 0=#p{::3{::shot{::Snapshots do.
        reason =. 'marker ',(2{packet){::Names
        record_snapshot (<shot),(<p),<reason
    end.
    shot accept_marker (p+N*2{packet),CurrentTime
    0
)
deliver_copy =: 4 : 0
    p =. x
    packet_index =. y
    packet =. packet_index{Packets
    message =. (4{packet){::Messages
    source =. 2{packet
    if. 0{::message do.
        Broadcast =: (1+(<p,source){Broadcast)(<p,source)}Broadcast
    end.
    amount =. 3{::message
    Balance =: (amount+p{Balance)p}Balance
    MoneyIn =: (amount+p{MoneyIn)p}MoneyIn
    event =. record_event (<p),(<4),(<4{packet),(<packet_index),(<_1),(<amount),(<''),<5{packet
    packet =. event 10}packet
    packet =. CurrentTime 9}packet
    Packets =: packet packet_index}Packets
    Delivered =: (<(p{::Delivered),packet_index)p}Delivered
    for_rule. p{::Rules do.
        'tag action' =. >rule
        if. tag-:2{::message do. p perform_action (<action),<source end.
    end.
    0
)
can_deliver =: 4 : 0
    packet =. y{Packets
    stamp =. 4{::(4{packet){::Messages
    stamp broadcast_deliverable (<x{Broadcast),<2{packet
)
release_causal =: 3 : 0
    p =. y
    while. 1 do.
        found =. _1
        held =. p{::Holdback
        for_i. i.#held do.
            if. p can_deliver i{held do. found =. i
                break.
            end.
        end.
        if. found<0 do. break. end.
        packet =. found{held
        Holdback =: (<((i.#held)~:found)#held)p}Holdback
        p deliver_copy packet
    end.
    0
)
accept_packet =: 4 : 0
    p =. x
    index =. y
    packet =. index{Packets
    source =. 2{packet
    channel =. p+N*source
    NextSequence =: (1+(<p,source){NextSequence)(<p,source)}NextSequence
    if. 0{packet do. p process_marker index
        0 return.
    end.
    for_shot. i.#Snapshots do.
        snapshot =. shot{::Snapshots
        if. (#p{::3{::snapshot)*.0>channel{6{::snapshot do.
            states =. 4{::snapshot
            states =. (<(channel{::states),index)channel}states
            snapshot =. (<states)4}snapshot
            Snapshots =: (<snapshot)shot}Snapshots
        end.
    end.
    message =. (4{packet){::Messages
    if. Raw+.-.0{::message do. p deliver_copy index
    elseif. p can_deliver index do.
        p deliver_copy index
        release_causal p
    else.
        Packets =: 1 (<index,12)}Packets
        missing =. (4{::message)missing_indices (<p{Broadcast),<source
        Missing =: (<missing)index}Missing
        Holdback =: (<(p{::Holdback),index)p}Holdback
    end.
    0
)
receive_packet =: 4 : 0
    p =. x
    packet_index =. y
    packet =. packet_index{Packets
    source =. 2{packet
    if. Raw do. p accept_packet packet_index
    elseif. (6{packet)~:(<p,source){NextSequence do.
        Packets =: 1 (<packet_index,11)}Packets
        buffer =. (<p,source){::Reorder
        Reorder =: (<buffer,packet_index)(<p,source)}Reorder
        channel =. p+N*source
        ChannelBuffered =: (1+channel{ChannelBuffered)channel}ChannelBuffered
    else.
        p accept_packet packet_index
        while. 1 do.
            buffer =. (<p,source){::Reorder
            found =. _1
            for_i. i.#buffer do.
                if. (6{(i{buffer){Packets)=(<p,source){NextSequence do. found =. i
                    break.
                end.
            end.
            if. found<0 do. break. end.
            following =. found{buffer
            Reorder =: (<((i.#buffer)~:found)#buffer)(<p,source)}Reorder
            p accept_packet following
        end.
    end.
    MaxHeld =: ((p{MaxHeld)>.held_count p)p}MaxHeld
    0
)
simulate =: 3 : 0
    Raw =: y
    initialize_processes ''
    initialize_network (<OriginalChannels),<Seed
    Messages =: Missing =: Labels =: Snapshots =: ActionArena =: 0$a:
    Copies =: i.0
    Packets =: 0 13$0
    Events =: 0 10$0
    EventVectors =: (0,N)$0
    Timeline =: 0 4$0
    Queue =: 0 5$0
    Creation =: CurrentTime =: 0
    for_entry. expand_actions '' do.
        'now p action' =. >entry
        index =. #ActionArena
        ActionArena =: ActionArena,<action
        enqueue now,p,0,index
    end.
    while. #Queue do.
        if. EndTime<0{0{Queue do. break. end.
        'now p creation kind payload' =. queue_pop ''
        CurrentTime =: now
        if. kind do. p receive_packet payload
        else. p perform_action (<payload{::ActionArena),<_1
        end.
    end.
    0
)
save_state =: 3 : 0
    (<Balance),(<Lamport),(<MaxHeld),(<MoneyIn),(<MoneyOut),(<Refused),(<MinimumBalance),(<VectorsState),(<Broadcast),(<NextSequence),(<Reorder),(<Holdback),(<Delivered),(<ProcessEvents),(<BalanceHistory),(<TypeCounts),(<ChannelFIFO),(<ChannelLow),(<ChannelHigh),(<ChannelSequence),(<ChannelLast),(<ChannelMessages),(<ChannelMarkers),(<ChannelBuffered),(<ChannelMaxDelay),(<ChannelEntries),(<PreviousVectors),(<ChannelOrder),(<RandomState),(<Draws),(<Messages),(<Packets),(<Missing),(<Copies),(<Events),(<EventVectors),(<Labels),(<Timeline),<Snapshots
)
restore_state =: 3 : 0
    'Balance Lamport MaxHeld MoneyIn MoneyOut Refused MinimumBalance VectorsState Broadcast NextSequence Reorder Holdback Delivered ProcessEvents BalanceHistory TypeCounts ChannelFIFO ChannelLow ChannelHigh ChannelSequence ChannelLast ChannelMessages ChannelMarkers ChannelBuffered ChannelMaxDelay ChannelEntries PreviousVectors ChannelOrder RandomState Draws Messages Packets Missing Copies Events EventVectors Labels Timeline Snapshots' =: y
    0
)
event_name =: 3 : 0
    event =. y{Events
    ((0{event){::Names),'.',integer 1{event
)
copy_label =: 3 : 0
    packet =. y{Packets
    (message_name 4{packet),'->',(3{packet){::Names
)
initial_total =: 3 : '+/Initial'
delivered_count =: 3 : '+/0<:10{"1 Copies{Packets'
trace_event_line =: 3 : 0
    event =. y{Events
    'p number kind now lamport balance message_index packet_index destination amount' =. event
    information =. ''
    select. kind
    case. 0 do. information =. y{::Labels
    case. 1 do. information =. 'to ',(destination{::Names),' amount ',(integer amount),' balance ',integer balance
    case. 2;3 do.
        message =. message_index{::Messages
        information =. message_name message_index
        if. kind=2 do. information =. information,' to ',destination{::Names end.
        information =. information,' tag ',2{::message
        if. amount do. information =. information,' amount ',(integer amount),' balance ',integer balance end.
    case. 4 do.
        packet =. packet_index{Packets
        message =. message_index{::Messages
        information =. (message_name message_index),' from ',((2{packet){::Names),' tag ',2{::message
        if. amount do. information =. information,' amount ',(integer amount),' balance ',integer balance end.
    end.
    (integer y+1),' t=',(integer now),' ',(event_name y),' ',(kind{::EventTypes),' ',information,' L=',(integer lamport),' V=',vector_text y{EventVectors
)
trace_lines =: 3 : 0
    lines =. trace_event_line&.>i.#Events
    count =. delivered_count ''
    lines =. lines,<'SUMMARY events ',(integer #Events),' messages ',(integer #Messages),' copies ',(integer #Copies),' delivered ',(integer count),' undelivered ',(integer (#Copies)-count),' draws ',integer Draws
    for_p. i.N do.
        lines =. lines,<'FINAL ',(p{::Names),' events ',(integer #p{::ProcessEvents),' L=',(integer p{Lamport),' V=',(vector_text p{VectorsState),' B=',(vector_text p{Broadcast),' balance ',(integer p{Balance),' in ',(integer p{MoneyIn),' out ',(integer p{MoneyOut),' refused ',(integer p{Refused),' min ',integer p{MinimumBalance
    end.
    for_p. i.N do.
        c =. p{TypeCounts
        lines =. lines,<'COUNTS ',(p{::Names),' local ',(integer 0{c),' nofunds ',(integer 1{c),' send ',(integer 2{c),' bcast ',(integer 3{c),' recv ',integer 4{c
    end.
    lines
)
wait_mode =: 3 : 0
    packet =. y{Packets
    fifo =. 11{packet
    causal =. 12{packet
    if. -.causal do.
        if. fifo do. 'fifo' else. 'direct' end. return.
    end.
    prefix =. 'causal '
    if. fifo do. prefix =. 'fifo+causal ' end.
    prefix,name_list y{::Missing
)
broadcast_history =: 3 : 0
    result =. i.0
    for_index. y{::ProcessEvents do.
        event =. index{Events
        kind =. 2{event
        if. kind=3 do. result =. result,6{event
        elseif. kind=4 do.
            if. 0{::(6{event){::Messages do. result =. result,6{event end.
        end.
    end.
    result
)
copy_description =: 3 : 0
    packet =. y{Packets
    message =. (4{packet){::Messages
    kind =. 'P2P'
    if. 0{::message do. kind =. 'BCAST' end.
    (message_name 4{packet),' from ',((2{packet){::Names),' ',kind,' tag ',(2{::message),' sent ',integer 5{::message
)
deliveries_lines =: 3 : 0
    lines =. 0$a:
    histories =. broadcast_history&.>i.N
    for_p. i.N do.
        lines =. lines,<'PROCESS ',p{::Names
        modes =. 4$0
        total_wait =. max_wait =. 0
        delivered =. p{::Delivered
        for_number. i.#delivered do.
            index =. number{delivered
            packet =. index{Packets
            wait =. (9{packet)-8{packet
            total_wait =. total_wait+wait
            max_wait =. max_wait>.wait
            mode =. (11{packet)+2*12{packet
            modes =. (1+mode{modes)mode}modes
            lines =. lines,<(integer number+1),' ',(copy_description index),' arrived ',(integer 8{packet),' delivered ',(integer 9{packet),' wait ',(integer wait),' ',wait_mode index
        end.
        for_index. Copies do.
            packet =. index{Packets
            if. (p=3{packet)*.(EndTime>:8{packet)*.0>10{packet do.
                place =. 'causal ',name_list index{::Missing
                if. index e.(<p,2{packet){::Reorder do. place =. 'fifo' end.
                lines =. lines,<'HELD ',(copy_description index),' arrived ',(integer 8{packet),' ',place
            end.
        end.
        for_index. Copies do.
            packet =. index{Packets
            if. (p=3{packet)*.EndTime<8{packet do.
                lines =. lines,<'TRANSIT ',(copy_description index),' arrival ',integer 8{packet
            end.
        end.
        lines =. lines,<'TOTAL delivered ',(integer #delivered),' direct ',(integer 0{modes),' fifo ',(integer 1{modes),' causal ',(integer 2{modes),' both ',(integer 3{modes),' wait ',(integer total_wait),' max_wait ',(integer max_wait),' max_held ',integer p{MaxHeld
        history =. p{::histories
        text =. 'none'
        if. #history do. text =. ' 'join message_name&.>history end.
        lines =. lines,<'BCASTS ',text
    end.
    for_channel. ChannelOrder do.
        source =. channel floor_div N
        destination =. N|channel
        kind =. 'NONFIFO'
        if. channel{ChannelFIFO do. kind =. 'FIFO' end.
        lines =. lines,<'CHANNEL ',(source{::Names),'->',(destination{::Names),' ',kind,' ',(delay_text channel),' messages ',(integer channel{ChannelMessages),' markers ',(integer channel{ChannelMarkers),' buffered ',(integer channel{ChannelBuffered),' max_delay ',(integer channel{ChannelMaxDelay),' entries ',integer channel{ChannelEntries
    end.
    tags =. 0$a:
    broadcasts =. i.0
    for_i. i.#Messages do.
        message =. i{::Messages
        tags =. tags,2{message
        if. 0{::message do. broadcasts =. broadcasts,i end.
    end.
    for_tag. /:~~.tags do.
        tag =. >tag
        count =. completed =. latency =. longest =. 0
        for_index. Copies do.
            packet =. index{Packets
            message =. (4{packet){::Messages
            if. tag-:2{::message do.
                count =. count+1
                if. (10{packet)>:0 do.
                    completed =. completed+1
                    elapsed =. (9{packet)-5{::message
                    latency =. latency+elapsed
                    longest =. longest>.elapsed
                end.
            end.
        end.
        lines =. lines,<'TAG ',tag,' copies ',(integer count),' delivered ',(integer completed),' latency ',(integer latency),' max ',integer longest
    end.
    for_id. broadcasts do.
        message =. id{::Messages
        complete =. 1
        latest =. 0
        for_index. 7{::message do.
            packet =. index{Packets
            if. (10{packet)<0 do. complete =. 0 else. latest =. latest>.9{packet end.
        end.
        stable =. 'none'
        if. complete do. stable =. integer latest end.
        lines =. lines,<'STABLE ',(message_name id),' ',((1{::message){::Names),' tag ',(2{::message),' sent ',(integer 5{::message),' stable ',stable
    end.
    disagreements =. 0
    for_i. i.#broadcasts do.
        for_j. (i+1)+i.(#broadcasts)-(i+1) do.
            first =. i{broadcasts
            second =. j{broadcasts
            earlier =. later =. i.0
            for_p. i.N do.
                history =. p{::histories
                a =. history i.first
                b =. history i.second
                if. (a<#history)*.b<#history do.
                    if. a<b do. earlier =. earlier,p else. later =. later,p end.
                end.
            end.
            if. (#earlier)*.#later do.
                disagreements =. disagreements+1
                lines =. lines,<'DISAGREE ',(message_name first),' ',(message_name second),' ',(name_list earlier),' ',name_list later
            end.
        end.
    end.
    lines,<'DISAGREEMENTS ',integer disagreements
)
consistent_verdict =: 3 : 0
    orphans =. 0{::y
    if. 0=#orphans do. 'yes' else. 'no ',' 'join copy_label&.>orphans end.
)
snapshot_lines =: 3 : 0
    raw =. y
    lines =. 0$a:
    initial =. initial_total ''
    for_snapshot. Snapshots do.
        snapshot =. >snapshot
        'name start complete records states sent accepted accepted_count ignored' =. snapshot
        cut =. snapshot_cut snapshot
        details =. cut_details cut
        'entries pending' =. recorded_copies snapshot
        channels_total =. 0
        for_index. entries do. channels_total =. channels_total+3{::(4{index{Packets){::Messages end.
        balance_total =. 0
        for_record. records do. balance_total =. balance_total+2{::>record end.
        money =. balance_total+channels_total
        if. raw do.
            lines =. lines,<'RAW ',name,' completed ',(integer complete),' cut ',(vector_text cut),' consistent ',(consistent_verdict details),' money ',(integer money),' conserved ',yes money=initial
        else.
            lines =. lines,<'SNAPSHOT ',name,' started ',(integer start),' completed ',integer complete
            for_p. i.N do.
                'now reason balance lamport vector held' =. p{::records
                text =. 'none'
                if. #held do. text =. ' 'join message_name&.>4{"1 held{Packets end.
                lines =. lines,<'RECORD ',(p{::Names),' t=',(integer now),' ',reason,' balance ',(integer balance),' L=',(integer lamport),' V=',(vector_text vector),' pending ',text
            end.
            for_channel. ChannelOrder do.
                values =. 0$a:
                for_index. channel{::states do.
                    packet =. index{Packets
                    amount =. 3{::(4{packet){::Messages
                    text =. message_name 4{packet
                    if. amount do. text =. text,':',integer amount end.
                    values =. values,<text
                end.
                text =. 'empty'
                if. #values do. text =. ' 'join values end.
                source =. channel floor_div N
                destination =. N|channel
                lines =. lines,<'CHANNEL ',(source{::Names),'->',(destination{::Names),' marker ',(integer channel{sent),' ',(integer channel{accepted),' state ',text
            end.
            for_item. ignored do. lines =. lines,<'IGNORED ',((0{item){::Names),' t=',integer 1{item end.
            lines =. lines,<'CUT ',(vector_text cut),' consistent ',(consistent_verdict details),' vector ',yes snapshot vector_consistent cut
            match =. (entries,pending)transit_match 1{::details
            lines =. lines,<'TRANSIT channels ',(integer #entries),' pending ',(integer #pending),' cut ',(integer #1{::details),' match ',yes match
            lines =. lines,<'MONEY balances ',(integer balance_total),' channels ',(integer channels_total),' total ',(integer money),' initial ',(integer initial),' conserved ',yes money=initial
        end.
    end.
    lines
)
range_notation =: 3 : 0
    if. 0=#y do. ,'-' return. end.
    parts =. 0$a:
    first =. last =. {.y
    for_index. }.y do.
        event =. index{Events
        previous =. last{Events
        if. ((0{event)=0{previous)*.(1{event)=1+1{previous do.
            last =. index
        else.
            text =. event_name first
            if. first~:last do. text =. text,'-',integer 1{last{Events end.
            parts =. parts,<text
            first =. last =. index
        end.
    end.
    text =. event_name first
    if. first~:last do. text =. text,'-',integer 1{last{Events end.
    ' 'join parts,<text
)
longest_chain =: 3 : 0
    values =. 4{"1 Events
    current =. {.I.values=>./values
    result =. ,current
    while. (4{current{Events)>1 do.
        event =. current{Events
        previous =. _1
        if. 4=2{event do.
            sending =. 5{(7{event){Packets
            if. (4{sending{Events)=_1+4{event do. previous =. sending end.
        end.
        if. previous<0 do. previous =. ((1{event)-2){(0{event){::ProcessEvents end.
        result =. previous,result
        current =. previous
    end.
    result
)
compare_lines =: 3 : 0
    edges =. event_graph ''
    names =. event_name&.>i.#Events
    lines =. 0$a:
    for_pair. Comparisons do.
        pair =. >pair
        first =. names i.<0{::pair
        second =. names i.<1{::pair
        rel =. (first{EventVectors)relation second{EventVectors
        path =. (first,second)graph_path edges
        graph_relation =. '->'
        if. 0=#path do.
            path =. (second,first)graph_path edges
            graph_relation =. '||'
            if. #path do. graph_relation =. '<-' end.
        end.
        lines =. lines,<'COMPARE ',(first{::names),' ',rel,' ',(second{::names),' L=',(integer 4{first{Events),',',(integer 4{second{Events),' graph ',graph_relation,' agree ',yes rel-:graph_relation
        if. #path do.
            p =. 0{"1 path{Events
            message_count =. +/(}.p)~:}:p
            lines =. lines,<'PATH length ',(integer #path),' messages ',(integer message_count),' ',range_notation path
        end.
        for_index. first,second do.
            event =. index{Events
            p =. 0{event
            number =. 1{event
            future =. i.0
            for_q. i.N do.
                future =. future,+/number>p{"1 (q{::ProcessEvents){EventVectors
            end.
            lines =. lines,<'WINDOW ',(event_name index),' past ',(vector_text index{EventVectors),' future ',vector_text future
        end.
    end.
    lines
)
analysis_lines =: 3 : 0
    lines =. compare_lines ''
    'ordered concurrent same_lamport inversions by_pair' =. concurrency_statistics ''
    count =. #Events
    pair_count =. (count*count-1)floor_div 2
    lines =. lines,<'CONCURRENCY events ',(integer count),' pairs ',(integer pair_count),' ordered ',(integer ordered),' concurrent ',(integer concurrent),' same_lamport ',(integer same_lamport),' inversions ',integer inversions
    for_p. i.N do.
        for_q. (p+1)+i.N-(p+1) do.
            lines =. lines,<'PAIR ',(p{::Names),' ',(q{::Names),' ',integer (<p,q){by_pair
        end.
    end.
    chain =. longest_chain ''
    lines =. lines,<'CHAIN length ',(integer #chain),' ',range_notation chain
    'races violations fifo' =. races_and_violations ''
    for_race. races do.
        'p a b' =. race
        lines =. lines,<'RACE ',(p{::Names),' ',(message_name 4{a{Packets),' ',((2{a{Packets){::Names),' ',(message_name 4{b{Packets),' ',(2{b{Packets){::Names
    end.
    lines =. lines,<'RACES ',integer #races
    for_violation. violations do.
        'p a b' =. violation
        lines =. lines,<'VIOLATION ',(p{::Names),' ',(message_name 4{a{Packets),' ',((2{a{Packets){::Names),' overtook ',(message_name 4{b{Packets),' ',(2{b{Packets){::Names
    end.
    lines =. lines,<'VIOLATIONS causal ',(integer #violations),' fifo ',integer fifo
    'raw_events raw_delivered raw_causal raw_fifo' =. RawSummary
    lines =. lines,<'RAW events ',(integer raw_events),' delivered ',(integer raw_delivered),' causal ',(integer raw_causal),' fifo ',integer raw_fifo
    for_cut. Cuts do.
        cut =. >cut
        details =. cut_details cut
        'orphans transit balances money' =. details
        text =. 'CUT ',vector_text cut
        if. #orphans do. text =. text,' inconsistent orphans ',' 'join copy_label&.>orphans
        else. text =. text,' consistent'
        end.
        lines =. lines,<text,' transit ',(integer #transit),' money ',(integer money),' initial ',integer initial_total ''
    end.
    'limits product consistent levels predicates' =. enumerate_cuts ''
    lines =. lines,<'CUTCOUNT t=',(integer CutTime),' events ',(vector_text limits),' product ',(integer product),' consistent ',integer consistent
    lines =. lines,<'LEVELS ',words levels
    for_i. i.#Thresholds do.
        'cuts possible definite' =. i{predicates
        lines =. lines,<'PREDICATE transit>=',(integer i{Thresholds),' cuts ',(integer cuts),' possibly ',(yes possible),' definitely ',yes definite
    end.
    lines
)
put_text =: 4 : 0
    'line text' =. y
    text =. ,text
    line =. ((#line)>.x+#text){.line,(x+#text)$' '
    text (x+i.#text)}line
)
trimmed =: 3 : 0
    indices =. I.y~:' '
    if. #indices do. (1+{:indices){.y else. '' end.
)
diagram_header =: 3 : 0
    line =. '    ',y,' '
    for_p. i.N do. line =. (6+8*p)put_text (<line),<p{::Names end.
    trimmed line
)
diagram_entry =: 3 : 0
    'value p kind message source shot_name' =. y
    line =. (_5{.(5$' '),integer value),' '
    for_q. i.N do. line =. (6+8*q)put_text (<line),<,'|' end.
    own =. 6+8*p
    line =. own put_text (<line),<kind{'*xSBR#'
    if. kind=5 do. line =. (own+1)put_text (<line),<shot_name
    elseif. kind e.2 3 do. line =. (own+1)put_text (<line),<message_name message
    elseif. kind=4 do.
        other =. 6+8*source
        low =. own<.other
        high =. own>.other
        for_position. (low+1)+i.high-(low+1) do.
            symbol =. '-'
            if. 0=8|position-6 do. symbol =. '+' end.
            line =. position put_text (<line),<symbol
        end.
        arrow_position =. low+1
        symbol =. '<'
        if. other<own do. arrow_position =. high-1
            symbol =. '>'
        end.
        line =. arrow_position put_text (<line),<symbol
        line =. (low+2)put_text (<line),<message_name message
    end.
    trimmed line
)
event_diagram =: 4 : 0
    event =. y{Events
    source =. _1
    if. 4=2{event do. source =. 2{(7{event){Packets end.
    diagram_entry (<x),(<0{event),(<2{event),(<6{event),(<source),<''
)
diagram_lines =: 3 : 0
    lines =. <diagram_header 't'
    for_entry. Timeline do.
        'kind index p now' =. entry
        if. kind=0 do. lines =. lines,<now event_diagram index
        else. lines =. lines,<diagram_entry (<now),(<p),(<5),(<_1),(<_1),<0{::index{::Snapshots
        end.
    end.
    lines =. lines,<diagram_header 'L'
    order =. /:(4{"1 Events),.0{"1 Events
    for_index. order do. lines =. lines,<(4{index{Events)event_diagram index end.
    lines
)
write_lines =: 4 : '((LF join y),LF)1!:2 <''output/'',x'
run =: 3 : 0
    'Names OriginalChannels' =: read_topology ''
    N =: #Names
    'Initial At Rules' =: read_scripts ''
    read_params ''
    simulate 0
    NormalState =. save_state ''
    simulate 1
    'raw_races raw_violations raw_fifo' =. races_and_violations ''
    RawSummary =: (#Events),(delivered_count ''),(#raw_violations),raw_fifo
    RawSnapshotLines =: snapshot_lines 1
    restore_state NormalState
    'trace.txt'write_lines trace_lines ''
    'deliveries.txt'write_lines deliveries_lines ''
    'snapshots.txt'write_lines (snapshot_lines 0),RawSnapshotLines
    'analysis.txt'write_lines analysis_lines ''
    'diagram.txt'write_lines diagram_lines ''
    0
)
run ''
