load 'config_io.ijs'
load 'cache.ijs'
load 'protocol.ijs'
load 'bus.ijs'
load 'stats.ijs'

intdiv =: 4 : '<.(x:x)%x:y'
integer =: 3 : 0
    text =. ":y
    '-'(I.text='_')}text
)
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do.
            result =. result,x
        end.
        result =. result,i{::y
    end.
    result
)
numbers =: 3 : ''' ''join integer&.>y'
join_sections =: 3 : 0
    lines =. 0$a:
    for_i. i.#y do.
        if. i do.
            lines =. lines,<''
        end.
        lines =. lines,i{::y
    end.
    lines
)
trace_error =: 3 : 0
    if. (-.(#y)e.3 4)+.(<'')e.y do.
        'fields' return.
    end.
    cycle =. 0{::y
    if. (7<#cycle)+.-.decimal_integer cycle do.
        'cycle' return.
    end.
    core =. 1{::y
    if. -.decimal_integer core do.
        'core' return.
    end.
    if. NumberCores<:".core do.
        'core' return.
    end.
    operation =. 2{::y
    if. -.(<,operation)e.,&.>;:'R W FENCE' do.
        'op' return.
    end.
    if. (operation-:'FENCE')~:3=#y do.
        'op' return.
    end.
    if. -.operation-:'FENCE' do.
        address =. 3{::y
        if. -.valid_hex_address address do.
            'address' return.
        end.
        value =. hex_value address
        if. (0~:4|value)+.value>2147483647 do.
            'address' return.
        end.
    end.
    if. LatestCycle>".cycle do.
        'order' return.
    end.
    ''
)
validate_trace =: 3 : 0
    Events =: 0 9$0
    Rejected =: 0$a:
    LatestCycle =: 0
    for_i. i.#TraceLines do.
        fields =. split_words i{::TraceLines
        reason =. trace_error fields
        if. #reason do.
            Rejected =: Rejected,<(i+1);reason
            continue.
        end.
        cycle =. ".0{::fields
        core =. ".1{::fields
        operation =. (,&.>;:'R W FENCE')i.,&.>2{fields
        address =. 0
        block =. 0
        word =. 0
        if. operation~:2 do.
            address =. hex_value 3{::fields
            block =. address intdiv LineSize
            word =. (LineSize|address)intdiv 4
        end.
        event =. (1+#Events),(i+1),cycle,core,operation,address,block,word,0
        Events =: Events,event
        LatestCycle =: cycle
    end.
    ByCore =: 0$a:
    for_core. i.NumberCores do.
        ByCore =: ByCore,<I.core=3{"1 Events
    end.
    access_rows =. Events#~2~:4{"1 Events
    AllBlocks =: /:~~.6{"1 access_rows
    NumberBlocks =: #AllBlocks
    EventBlocks =: AllBlocks i.6{"1 Events
)
reuse_analysis =: 3 : 0
    capacities =. (CacheCapacity intdiv 4),(CacheCapacity intdiv 2),CacheCapacity,(2*CacheCapacity),4*CacheCapacity
    ReuseLines =: 0$a:
    for_core. i.NumberCores do.
        ordered =. core{::ByCore
        accesses =. ordered#~2~:4{"1 ordered{Events
        blocks =. accesses{EventBlocks
        stack =. i.0
        cold =. 0
        histogram =. 6$0
        curve =. 5$0
        for_event_index. accesses do.
            block =. event_index{EventBlocks
            position =. stack i.block
            distance =. 0
            if. position=#stack do.
                cold =. cold+1
            else.
                distance =. position+1
                bucket =. +/distance>1 4 16 64 256
                histogram =. ((bucket{histogram)+1)bucket}histogram
                stack =. stack#~stack~:block
            end.
            Events =: distance(<event_index,8)}Events
            curve =. curve+(distance=0)+.distance>capacities
            stack =. block,stack
        end.
        next_positions =. (#accesses)$0
        future =. NumberBlocks$1+#accesses
        for_i. |.i.#accesses do.
            block =. i{blocks
            next_positions =. (block{future)i}next_positions
            future =. i block}future
        end.
        resident =. i.0
        opt =. 0
        for_i. i.#accesses do.
            block =. i{blocks
            future =. (i{next_positions)block}future
            if. block e.resident do.
                continue.
            end.
            opt =. opt+1
            if. CacheCapacity=#resident do.
                nexts =. resident{future
                victims =. resident#~nexts=>./nexts
                victim =. <./victims
                resident =. resident#~resident~:victim
            end.
            resident =. resident,block
        end.
        label =. 'c',integer core
        line =. 'reuse ',label,' accesses ',(integer #accesses),' lines ',integer #~.blocks
        line =. line,' distance ',((;:'1 2-4 5-16 17-64 65-256 257+')range_counts histogram),' cold ',integer cold
        ReuseLines =: ReuseLines,<line
        line =. 'mrc ',label,' lru ',((integer&.>capacities)range_counts curve)
        line =. line,' opt ',(integer CacheCapacity),':',integer opt
        ReuseLines =: ReuseLines,<line
    end.
)
static_sharing =: 3 : 0
    StaticReaders =: (NumberBlocks,WordsPerLine)$0
    StaticWriters =: (NumberBlocks,WordsPerLine)$0
    StaticReadCounts =: NumberBlocks$0
    StaticWriteCounts =: NumberBlocks$0
    for_i. i.#Events do.
        event =. i{Events
        operation =. 4{event
        if. operation=2 do.
            continue.
        end.
        core =. 3{event
        block =. i{EventBlocks
        word =. 7{event
        position =. <block,word
        bit =. 2^core
        if. operation=0 do.
            value =. bit(23 b.)position{StaticReaders
            StaticReaders =: value position}StaticReaders
            StaticReadCounts =: ((block{StaticReadCounts)+1)block}StaticReadCounts
        else.
            value =. bit(23 b.)position{StaticWriters
            StaticWriters =: value position}StaticWriters
            StaticWriteCounts =: ((block{StaticWriteCounts)+1)block}StaticWriteCounts
        end.
    end.
)
line_states =: 3 : 0
    result =. ''
    for_cache. i.NumberCores+1 do.
        result =. result,cache cache_state y
    end.
    result
)
initialize_scenario =: 3 : 0
    'ScenarioName Protocol L1Policy L2Policy' =: y
    IsPrimary =: ScenarioName-:PrimaryName
    cache_initialize }.y
    bus_initialize ''
    initialize_counters ''
    CoreIndices =: NumberCores$0
    Ready =: NumberCores$0
    WriteCompletion =: NumberCores$0
    Seen =: (NumberCores,NumberBlocks)$0
    InvalidationWords =: (NumberCores*NumberBlocks)$<i.0
    L2Counters =: 7$0
    Processed =: 0 10$0
    WatchLines =: 0$a:
    Handoffs =: NumberBlocks$0
    LastWriter =: NumberBlocks$_1
    WordWriters =: (NumberBlocks,WordsPerLine)$_1
    WordReaders =: (NumberBlocks,WordsPerLine)$0
    Communications =: (NumberCores,NumberCores)$0
    SharingMisses =: (NumberBlocks,2)$0
)
issue_transaction =: 3 : 0
    'core kind block requested' =. y
    tx =. bus_assign y
    core counter_add (22+kind),1
    if. kind=4 do.
        L2Counters =: ((4{L2Counters)+1)4}L2Counters
    end.
    tx
)
snoop_others =: 4 : 0
    tx =. x
    word =. y
    block =. tx{TxBlock
    requester_core =. tx{TxCore
    kind =. tx{TxKind
    for_core. i.NumberCores do.
        if. core=requester_core do.
            continue.
        end.
        old =. core cache_state block
        if. old='I' do.
            continue.
        end.
        'new supplies flushed' =. Protocol snoop old;kind
        item =. 'c',(integer core),':',old,'>',new
        TxSnoop =: (<(tx{::TxSnoop),<item)tx}TxSnoop
        TxSnoopHits =: ((tx{TxSnoopHits)+1)tx}TxSnoopHits
        if. new='I' do.
            core cache_remove block
            TxInvalidations =: ((tx{TxInvalidations)+1)tx}TxInvalidations
            requester_core counter_add 27 1
            core counter_add 28 1
            index =. (core*NumberBlocks)+AllBlocks i.block
            InvalidationWords =: (<,word)index}InvalidationWords
        else.
            (core,block)cache_change new
        end.
        if. supplies do.
            TxSupplier =: core tx}TxSupplier
            core counter_add 29 1
        end.
        if. flushed do.
            TxFlush =: 1 tx}TxFlush
        end.
    end.
    if. tx{TxFlush do.
        L2Counters =: ((3{L2Counters)+1)3}L2Counters
    end.
)
access_l2 =: 3 : 0
    tx =. y
    block =. tx{TxBlock
    L2Counters =: ((0{L2Counters)+1)0}L2Counters
    if. 'I'~:NumberCores cache_state block do.
        TxL2 =: 1 tx}TxL2
        L2Counters =: ((1{L2Counters)+1)1}L2Counters
        NumberCores cache_touch block
    else.
        TxL2 =: 2 tx}TxL2
        L2Counters =: ((2{L2Counters)+1)2}L2Counters
        'old_block old_state' =. NumberCores cache_fill block;'C'
        if. old_block~:_1 do.
            copies =. 0$a:
            dirty =. old_state='D'
            for_core. i.NumberCores do.
                state =. core cache_state old_block
                if. state='I' do.
                    continue.
                end.
                core cache_remove old_block
                copies =. copies,<'c',(integer core),':',state
                core counter_add 30 1
                dirty =. dirty+.dirty_state state
            end.
            TxEvicted =: old_block tx}TxEvicted
            TxBackCopies =: (<copies)tx}TxBackCopies
            TxDirty =: dirty tx}TxDirty
            L2Counters =: ((5{L2Counters)+1)5}L2Counters
            if. dirty do.
                L2Counters =: ((6{L2Counters)+1)6}L2Counters
            end.
        end.
    end.
    if. (tx{TxFlush)+.3=tx{TxKind do.
        (NumberCores,block)cache_change 'D'
    end.
)
run_transaction =: 3 : 0
    'core kind block word requested' =. y
    tx =. issue_transaction core,kind,block,requested
    tx snoop_others word
    if. kind~:2 do.
        access_l2 tx
    end.
    completion =. TB+tx{TxStart
    if. kind=2 do.
        completion,tx return.
    elseif. kind=3 do.
        completion =. completion+T2+TM*2=tx{TxL2
    elseif. _1~:tx{TxSupplier do.
        TxSource =: (<'c',integer tx{TxSupplier)tx}TxSource
    elseif. 1=tx{TxL2 do.
        completion =. completion+T2
        TxSource =: (<'L2')tx}TxSource
    else.
        completion =. completion+T2+TM
        TxSource =: (<'mem')tx}TxSource
    end.
    completion,tx
)
write_back =: 4 : 0
    tx =. issue_transaction x,4,y,BusFree
    NumberCores cache_touch y
    (NumberCores,y)cache_change 'D'
)
communicate =: 3 : 0
    'block word core operation' =. y
    position =. <block,word
    previous =. position{WordWriters
    readers =. position{WordReaders
    if. operation=1 do.
        old =. block{LastWriter
        if. (old~:_1)*.old~:core do.
            Handoffs =: ((block{Handoffs)+1)block}Handoffs
        end.
        LastWriter =: core block}LastWriter
        WordWriters =: core position}WordWriters
        WordReaders =: 0 position}WordReaders
    elseif. (previous~:_1)*.previous~:core do.
        bit =. 2^core
        if. 0=bit(17 b.)readers do.
            pair =. <previous,core
            Communications =: (1+pair{Communications)pair}Communications
            WordReaders =: (bit(23 b.)readers)position}WordReaders
        end.
    end.
)

render_watch =: 3 : 0
    'event issue before' =. y
    'number source cycle core operation address block word distance' =. event
    for_i. i.#WatchBlocks do.
        watched =. i{WatchBlocks
        after =. line_states watched
        if. (watched~:block)*.after-:i{::before do.
            continue.
        end.
        line =. (integer number),' ',(integer issue),' c',(integer core),' ',(operation{'RW'),' ',hex_address address
        line =. line,' line ',hex_address watched*LineSize
        for_k. i.NumberCores do.
            line =. line,' c',(integer k),':',k{after
        end.
        line =. line,' L2:',{:after
        WatchLines =: WatchLines,<line
    end.
)
handle_access =: 4 : 0
    event_index =. x
    issue =. y
    event =. event_index{Events
    'number source cycle core operation address block word distance' =. event
    block_index =. event_index{EventBlocks
    before =. 0$a:
    if. IsPrimary do.
        for_watched. WatchBlocks do.
            before =. before,<line_states watched
        end.
    end.
    old =. core cache_state block
    hit =. old~:'I'
    core counter_add 0 1
    core counter_add (1+operation),1
    core counter_add (4-hit),1
    other_copy =. 0
    for_other. (i.NumberCores)-.core do.
        other_copy =. other_copy+.'I'~:other cache_state block
    end.
    'kind new' =. Protocol requester old;operation;other_copy
    miss =. _1
    sharing =. _1
    key =. block_index+NumberBlocks*core
    if. hit do.
        core cache_touch block
    else.
        record =. key{::InvalidationWords
        if. 0=(<core,block_index){Seen do.
            miss =. 0
        elseif. #record do.
            miss =. 3
            sharing =. -.word e.record
        elseif. distance>CacheCapacity do.
            miss =. 1
        else.
            miss =. 2
        end.
        core counter_add (10+miss),1
        if. sharing~:_1 do.
            core counter_add (14+sharing),1
            position =. <block_index,sharing
            SharingMisses =: (1+position{SharingMisses)position}SharingMisses
        end.
    end.
    Seen =: 1(<core,block_index)}Seen
    if. operation=1 do.
        for_other. (i.NumberCores)-.core do.
            index =. block_index+NumberBlocks*other
            record =. index{::InvalidationWords
            if. #record do.
                InvalidationWords =: (<~.record,word)index}InvalidationWords
            end.
        end.
    end.
    if. IsPrimary do.
        communicate block_index,word,core,operation
    end.
    if. kind=_1 do.
        completion =. issue+T1
        service =. 0
    else.
        'completion tx' =. run_transaction core,kind,block,word,issue+T1
        if. kind=2 do.
            service =. 1
        elseif. kind=3 do.
            service =. 2
        elseif. _1~:tx{TxSupplier do.
            service =. 3
        elseif. 1=tx{TxL2 do.
            service =. 4
        else.
            service =. 5
        end.
    end.
    if. old~:'I' do.
        (core,block)cache_change new
    elseif. new~:'I' do.
        'evicted evicted_state' =. core cache_fill block;new
        InvalidationWords =: (<i.0)key}InvalidationWords
        if. (evicted~:_1)*.dirty_state evicted_state do.
            core write_back evicted
        end.
    end.
    latency =. completion-issue
    core counter_add (16+service),1
    core counter_add 6,latency
    if. operation=0 do.
        core counter_add 8,latency
        Ready =: completion core}Ready
    else.
        core counter_add 9,latency
        Ready =: (issue+T1)core}Ready
        WriteCompletion =: (completion>.core{WriteCompletion)core}WriteCompletion
    end.
    finish =. completion>.(<core,31){CoreCounters
    CoreCounters =: finish(<core,31)}CoreCounters
    row =. number,issue,core,operation,address,block_index,word,latency,service,miss
    Processed =: Processed,row
    if. IsPrimary do.
        render_watch(<event),(<issue),<before
    end.
)
handle_fence =: 4 : 0
    core =. 3{x{Events
    completion =. y>.core{WriteCompletion
    core counter_add 5 1
    core counter_add 7,completion-y
    finish =. completion>.(<core,31){CoreCounters
    CoreCounters =: finish(<core,31)}CoreCounters
    Ready =: completion core}Ready
)
simulate =: 3 : 0
    initialize_scenario y
    while. 1 do.
        chosen =. _1
        chosen_issue =. _1
        chosen_core =. _1
        for_core. i.NumberCores do.
            index =. core{CoreIndices
            ordered =. core{::ByCore
            if. index=#ordered do.
                continue.
            end.
            event_index =. index{ordered
            issue =. (core{Ready)>.(<event_index,2){Events
            if. (chosen=_1)+.issue<chosen_issue do.
                chosen =. event_index
                chosen_issue =. issue
                chosen_core =. core
            end.
        end.
        if. chosen=_1 do.
            break.
        end.
        CoreIndices =: (1+chosen_core{CoreIndices)chosen_core}CoreIndices
        if. 2=(<chosen,4){Events do.
            chosen handle_fence chosen_issue
        else.
            chosen handle_access chosen_issue
        end.
    end.
    TotalCounters =: total_counters CoreCounters
    Finish =: 31{TotalCounters
)
trace_config_lines =: 3 : 0
    line =. 'trace lines ',(integer #TraceLines),' accepted ',(integer #Events),' rejected ',integer #Rejected
    lines =. ,<line
    for_rejected. Rejected do.
        'number reason' =. >rejected
        lines =. lines,<'reject line ',(integer number),' ',reason
    end.
    line =. 'geometry cores ',(integer NumberCores),' line ',(integer LineSize),' l1 ',(integer L1Size),' ',integer L1Ways
    line =. line,' sets ',(integer L1Sets),' l2 ',(integer L2Size),' ',(integer L2Ways),' sets ',integer L2Sets
    lines =. lines,<line
    line =. 'latency l1 ',(integer T1),' l2 ',(integer T2),' memory ',(integer TM),' bus ',integer TB
    lines,<line
)
scenario_report =: 3 : 0
    lines =. <'scenario ',ScenarioName,' ',Protocol,' ',L1Policy,' ',L2Policy
    for_core. i.NumberCores do.
        lines =. lines,('c',integer core)six_lines core{CoreCounters
    end.
    lines =. lines,'total'six_lines TotalCounters
    lines =. lines,<'l2 ',(;:'lookups hits misses flushes writebacks evictions dirty_evictions')paired_counts L2Counters
    transactions =. #TxStart
    busy =. TB*transactions
    line =. 'bus transactions ',(integer transactions),' busy ',(integer busy),' wait ',integer BusWait
    lines =. lines,<line,' utilization ',(100*busy)decimal Finish
    kinds =. 5{.22}.TotalCounters
    data_bytes =. (LineSize*+/(0 1 4{kinds))+4*3{kinds
    memory_bytes =. LineSize*+/(2 6{L2Counters)
    line =. 'traffic command_bytes ',(integer 8*transactions),' data_bytes ',(integer data_bytes),' memory_bytes ',integer memory_bytes
    lines =. lines,<line
    snoops =. I.TxKind~:4
    invalidating =. I.TxKind e.1 2 3
    fanout =. NumberCores$0
    for_count. invalidating{TxInvalidations do.
        fanout =. ((count{fanout)+1)count}fanout
    end.
    line =. 'snoops probes ',(integer (NumberCores-1)*#snoops),' hits ',integer +/snoops{TxSnoopHits
    lines =. lines,<line,' fanout ',(integer&.>i.NumberCores)range_counts fanout
    histogram =. 6$0
    for_latency. 7{"1 Processed do.
        bucket =. +/latency>1 9 29 99 299
        histogram =. ((bucket{histogram)+1)bucket}histogram
    end.
    line =. 'latencies reads ',(integer 8{TotalCounters),' writes ',integer 9{TotalCounters
    lines,<line,' histogram ',(;:'1 2-9 10-29 30-99 100-299 300+')range_counts histogram
)
hot_lines =: 3 : 0
    counts =. (NumberBlocks,8)$0
    cores =. NumberBlocks$0
    for_tx. i.#TxStart do.
        block =. AllBlocks i.tx{TxBlock
        kind =. tx{TxKind
        position =. <block,kind
        counts =. (1+position{counts)position}counts
        position =. <block,7
        counts =. ((tx{TxInvalidations)+position{counts)position}counts
        cores =. ((block{cores)(23 b.)2^tx{TxCore)block}cores
    end.
    for_access. Processed do.
        block =. 5{access
        miss =. 9{access
        if. miss~:_1 do.
            position =. <block,5
            counts =. (1+position{counts)position}counts
            if. miss=3 do.
                position =. <block,6
                counts =. (1+position{counts)position}counts
            end.
        end.
    end.
    totals =. +/"1 (i.5){"1 counts
    active =. I.totals>0
    keys =. (-active{totals),.active{AllBlocks
    ordered =. active{~/:keys
    ordered =. (Top<.#ordered){.ordered
    lines =. <'hot ',ScenarioName
    for_rank. i.#ordered do.
        block =. rank{ordered
        row =. block{counts
        line =. (integer rank+1),' ',(hex_address LineSize*block{AllBlocks),' transactions ',integer block{totals
        line =. line,' ',Transactions paired_counts 5{.row
        line =. line,' misses ',(integer 5{row),' coherence ',(integer 6{row),' invalidations ',integer 7{row
        lines =. lines,<line,' cores ',core_string mask_cores block{cores
    end.
    lines
)
interval_lines =: 3 : 0
    count =. 1+Finish intdiv IntervalWidth
    accesses =. (count,NumberCores)$0
    misses =. count$0
    transactions =. count$0
    busy =. count$0
    for_access. Processed do.
        bucket =. (1{access)intdiv IntervalWidth
        core =. 2{access
        position =. <bucket,core
        accesses =. (1+position{accesses)position}accesses
        if. _1~:9{access do.
            misses =. ((bucket{misses)+1)bucket}misses
        end.
    end.
    for_start. TxStart do.
        bucket =. start intdiv IntervalWidth
        transactions =. ((bucket{transactions)+1)bucket}transactions
        last =. start+TB
        final_bucket =. (last-1)intdiv IntervalWidth
        for_k. bucket+i.1+final_bucket-bucket do.
            if. k<count do.
                left =. start>.k*IntervalWidth
                right =. last<.(k+1)*IntervalWidth
                busy =. ((k{busy)+0>.right-left)k}busy
            end.
        end.
    end.
    lines =. <'intervals ',ScenarioName,' ',integer IntervalWidth
    for_k. i.count do.
        start =. k*IntervalWidth
        end =. (start+IntervalWidth)-1
        line =. (integer k),' ',(integer start),'-',(integer end),' accesses ',numbers k{accesses
        line =. line,' misses ',(integer k{misses),' transactions ',(integer k{transactions),' busy ',integer k{busy
        lines =. lines,<line,' utilization ',(100*k{busy)decimal IntervalWidth
    end.
    lines
)
slowest_lines =: 3 : 0
    keys =. (-7{"1 Processed),.0{"1 Processed
    ordered =. (Top<.#Processed){./:keys
    lines =. <'slowest ',ScenarioName
    for_rank. i.#ordered do.
        'number issue core operation address block word latency service miss' =. (rank{ordered){Processed
        line =. (integer rank+1),' event ',(integer number),' cycle ',(integer issue),' c',integer core
        line =. line,' ',(operation{'RW'),' ',(hex_address address),' latency ',(integer latency),' service ',service{::Services
        lines =. lines,<line
    end.
    lines
)
region_for =: 3 : 0
    found =. I.(y>:RegionStarts)*.y<:RegionEnds
    if. #found do.
        {.found
    else.
        #RegionNames
    end.
)
region_lines =: 3 : 0
    counters =. ((1+#RegionNames),10)$0
    for_access. Processed do.
        region =. region_for 4{access
        operation =. 3{access
        miss =. 9{access
        row =. region{counters
        row =. (1+0{row)0}row
        index =. 1+operation
        row =. (1+index{row)index}row
        row =. ((9{row)+7{access)9}row
        if. miss=_1 do.
            row =. (1+3{row)3}row
        else.
            index =. 4+miss
            row =. (1+index{row)index}row
        end.
        counters =. row region}counters
    end.
    for_block. TxBlock do.
        region =. region_for LineSize*block
        position =. <region,8
        counters =. (1+position{counters)position}counters
    end.
    lines =. <'regions ',ScenarioName
    names =. RegionNames,<'other'
    for_i. i.#names do.
        row =. i{counters
        amat =. '-'
        if. 0{row do.
            amat =. ((9{row)fraction 0{row),' ',(9{row)decimal 0{row
        end.
        line =. (i{::names),' ',(;:'accesses reads writes hits')paired_counts 4{.row
        line =. line,' ',MissKinds paired_counts 4{.4}.row
        line =. line,' transactions ',(integer 8{row),' latency ',(integer 9{row),' amat ',amat
        lines =. lines,<line
    end.
    lines
)

sharing_output =: 3 : 0
    lines =. 0$a:
    shared_count =. 0
    true_lines =. 0
    totals =. 2$0
    for_block. i.NumberBlocks do.
        reader_masks =. block{StaticReaders
        writer_masks =. block{StaticWriters
        readers =. 23 b./reader_masks
        writers =. 23 b./writer_masks
        cores =. readers(23 b.)writers
        if. (0=writers)+.2>#mask_cores cores do.
            continue.
        end.
        shared_count =. shared_count+1
        true_line =. 0
        word_descriptions =. 0$a:
        for_word. i.WordsPerLine do.
            r =. word{reader_masks
            w =. word{writer_masks
            if. 0=r(23 b.)w do.
                continue.
            end.
            if. (w~:0)*.2<:#mask_cores r(23 b.)w do.
                true_line =. 1
            end.
            item =. 'w',(integer word),'=',(core_string mask_cores r),'/',core_string mask_cores w
            word_descriptions =. word_descriptions,<item
        end.
        true_lines =. true_lines+true_line
        counts =. block{SharingMisses
        totals =. totals+counts
        'true_miss false_miss' =. counts
        quality =. true_line{::'false';'true'
        line =. (hex_address LineSize*block{AllBlocks),' ',quality,' cores ',core_string mask_cores cores
        line =. line,' writers ',(core_string mask_cores writers),' reads ',(integer block{StaticReadCounts),' writes ',integer block{StaticWriteCounts
        line =. line,' handoffs ',(integer block{Handoffs),' coherence ',(integer +/counts),' true ',(integer true_miss),' false ',integer false_miss
        lines =. lines,<line,' words ',' 'join word_descriptions
    end.
    line =. 'lines ',(integer shared_count),' true_lines ',(integer true_lines),' false_lines ',integer shared_count-true_lines
    line =. line,' coherence ',(integer +/totals),' true ',(integer 0{totals),' false ',integer 1{totals
    lines =. lines,(<line),<'communication'
    for_core. i.NumberCores do.
        lines =. lines,<'c',(integer core),' ',numbers core{Communications
    end.
    lines
)
cache_set_line =: 4 : 0
    'cache row' =. x
    ways =. cache{CacheWays
    positions =. (row*ways)+i.ways
    blocks =. positions{cache{::CacheBlocks
    states =. positions{cache{::CacheStates
    values =. 0$a:
    for_way. i.ways do.
        block =. way{blocks
        if. block=_1 do.
            item =. '-'
        else.
            item =. (hex_address LineSize*block),':',way{states
        end.
        values =. values,<item
    end.
    policy =. cache{::CachePolicies
    lower =. (65+i.26){a.
    policy =. (lower i.policy){(97+i.26){a.
    line =. y,' ',(integer row),' ',(' 'join values),' ',policy,' ',cache cache_order row
    line =. line,' fills ',(integer row{cache{::CacheFills),' evictions ',integer row{cache{::CacheEvictions
    line
)
final_state_output =: 3 : 0
    lines =. 0$a:
    for_core. i.NumberCores do.
        label =. 'c',integer core
        for_row. i.L1Sets do.
            lines =. lines,<(core,row)cache_set_line label
        end.
        states =. core{::CacheStates
        total =. +/states~:'I'
        line =. label,' lines ',integer total
        for_state. 'MOESV' do.
            line =. line,' ',state,' ',integer +/state=states
        end.
        lines =. lines,<line
    end.
    for_row. i.L2Sets do.
        lines =. lines,<(NumberCores,row)cache_set_line 'L2'
    end.
    states =. NumberCores{::CacheStates
    held =. i.0
    for_core. i.NumberCores do.
        blocks =. core{::CacheBlocks
        held =. held,blocks#~blocks~:_1
    end.
    line =. 'L2 lines ',(integer +/states~:'I'),' dirty ',(integer +/states='D'),' clean ',integer +/states='C'
    lines,<line,' in_l1 ',integer #~.held
)
rank_scenarios =: 3 : 0
    ordered =. /:RankingKeys
    lines =. ,<'ranking'
    for_rank. i.#ordered do.
        index =. rank{ordered
        'finish transactions latency accesses' =. index{RankingValues
        name =. 0{::index{::Scenarios
        line =. (integer rank+1),' ',name,' finish ',(integer finish),' transactions ',integer transactions
        lines =. lines,<line,' amat ',(latency fraction accesses),' ',latency decimal accesses
    end.
    lines
)
run =: 3 : 0
    read_config ''
    validate_trace ''
    reuse_analysis ''
    static_sharing ''
    ScenarioReports =: 0$a:
    RankingKeys =: 0 3$0
    RankingValues =: 0 4$0
    for_i. i.#Scenarios do.
        simulate i{::Scenarios
        ScenarioReports =: ScenarioReports,<scenario_report ''
        RankingKeys =: RankingKeys,Finish,(#TxStart),i
        RankingValues =: RankingValues,Finish,(#TxStart),(6{TotalCounters),0{TotalCounters
        if. IsPrimary do.
            PrimaryHot =: hot_lines ''
            PrimaryIntervals =: interval_lines ''
            PrimarySlowest =: slowest_lines ''
            PrimaryRegions =: region_lines ''
            PrimaryBus =: bus_line&.>i.#TxStart
            PrimaryWatch =: WatchLines
            PrimarySharing =: sharing_output ''
            PrimaryFinal =: final_state_output ''
        end.
    end.
    sections =. (<trace_config_lines ''),(<ReuseLines),ScenarioReports
    sections =. sections,(<rank_scenarios ''),(<PrimaryHot),(<PrimaryIntervals),(<PrimarySlowest),<PrimaryRegions
    try.
        1!:5 <'output'
    catch.
    end.
    'stats.txt'write_lines join_sections sections
    'bus_log.txt'write_lines PrimaryBus
    'watch.txt'write_lines PrimaryWatch
    'sharing.txt'write_lines PrimarySharing
    'final_state.txt'write_lines PrimaryFinal
)
run ''
