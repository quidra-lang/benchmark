cache_initialize =: 3 : 0
    CacheSets =: (NumberCores$L1Sets),L2Sets
    CacheWays =: (NumberCores$L1Ways),L2Ways
    CachePolicies =: (NumberCores$1{y),2{y
    CacheBlocks =: 0$a:
    CacheStates =: 0$a:
    CacheTouched =: 0$a:
    CacheBits =: 0$a:
    CacheFills =: 0$a:
    CacheEvictions =: 0$a:
    CacheClock =: (NumberCores+1)$0
    for_cache. i.NumberCores+1 do.
        count =. (cache{CacheSets)*cache{CacheWays
        CacheBlocks =: CacheBlocks,<count$_1
        CacheStates =: CacheStates,<count$'I'
        CacheTouched =: CacheTouched,<count$0
        CacheBits =: CacheBits,<count$0
        CacheFills =: CacheFills,<(cache{CacheSets)$0
        CacheEvictions =: CacheEvictions,<(cache{CacheSets)$0
    end.
)
cache_locate =: 4 : 0
    row =. (x{CacheSets)|y
    ways =. x{CacheWays
    positions =. (row*ways)+i.ways
    found =. I.y=positions{x{::CacheBlocks
    if. #found do.
        ({.found){positions
    else.
        _1
    end.
)
cache_state =: 4 : 0
    position =. x cache_locate y
    if. position=_1 do.
        'I'
    else.
        position{x{::CacheStates
    end.
)
cache_change =: 4 : 0
    'cache block' =. x
    position =. cache cache_locate block
    if. position~:_1 do.
        states =. cache{::CacheStates
        CacheStates =: (<y position}states)cache}CacheStates
    end.
)
cache_remove =: 4 : 0
    position =. x cache_locate y
    if. position~:_1 do.
        blocks =. x{::CacheBlocks
        states =. x{::CacheStates
        CacheBlocks =: (<_1 position}blocks)x}CacheBlocks
        CacheStates =: (<'I'position}states)x}CacheStates
    end.
)
cache_touch_way =: 4 : 0
    'row way fill' =. y
    policy =. x{::CachePolicies
    ways =. x{CacheWays
    position =. (row*ways)+way
    if. (policy-:'LRU')+.((policy-:'FIFO')*.fill) do.
        clock =. 1+x{CacheClock
        CacheClock =: clock x}CacheClock
        touched =. x{::CacheTouched
        CacheTouched =: (<clock position}touched)x}CacheTouched
    elseif. policy-:'PLRU' do.
        lo =. 0
        hi =. ways
        node =. 1
        bits =. x{::CacheBits
        while. 1<hi-lo do.
            middle =. (lo+hi)intdiv 2
            if. way<middle do.
                bits =. 1((row*ways)+node)}bits
                hi =. middle
                node =. 2*node
            else.
                bits =. 0((row*ways)+node)}bits
                lo =. middle
                node =. 1+2*node
            end.
        end.
        CacheBits =: (<bits)x}CacheBits
    end.
)
cache_touch =: 4 : 0
    position =. x cache_locate y
    if. position~:_1 do.
        ways =. x{CacheWays
        x cache_touch_way(position intdiv ways),(ways|position),0
    end.
)
cache_victim =: 4 : 0
    ways =. x{CacheWays
    if. 'PLRU'-:x{::CachePolicies do.
        lo =. 0
        hi =. ways
        node =. 1
        bits =. x{::CacheBits
        while. 1<hi-lo do.
            middle =. (lo+hi)intdiv 2
            if. 0=((y*ways)+node){bits do.
                hi =. middle
                node =. 2*node
            else.
                lo =. middle
                node =. 1+2*node
            end.
        end.
        lo return.
    end.
    touched =. ((y*ways)+i.ways){x{::CacheTouched
    touched i.<./touched
)
cache_fill =: 4 : 0
    'block state' =. y
    row =. (x{CacheSets)|block
    ways =. x{CacheWays
    blocks =. x{::CacheBlocks
    states =. x{::CacheStates
    empty =. I._1=((row*ways)+i.ways){blocks
    if. #empty do.
        way =. {.empty
    else.
        way =. x cache_victim row
    end.
    position =. (row*ways)+way
    old_block =. position{blocks
    old_state =. position{states
    if. old_block~:_1 do.
        evictions =. x{::CacheEvictions
        evictions =. ((row{evictions)+1)row}evictions
        CacheEvictions =: (<evictions)x}CacheEvictions
    end.
    CacheBlocks =: (<block position}blocks)x}CacheBlocks
    CacheStates =: (<state position}states)x}CacheStates
    fills =. x{::CacheFills
    CacheFills =: (<((row{fills)+1)row}fills)x}CacheFills
    x cache_touch_way row,way,1
    (<old_block),<old_state
)
cache_order =: 4 : 0
    ways =. x{CacheWays
    if. 'PLRU'-:x{::CachePolicies do.
        if. ways=1 do.
            '-' return.
        end.
        positions =. (y*ways)+1+i.ways-1
        '01'{~positions{x{::CacheBits return.
    end.
    positions =. (y*ways)+i.ways
    active =. I._1~:positions{x{::CacheBlocks
    if. 0=#active do.
        '-' return.
    end.
    touched =. (active{positions){x{::CacheTouched
    numbers active /:-touched
)
