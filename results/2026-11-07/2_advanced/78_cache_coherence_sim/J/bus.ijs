bus_initialize =: 3 : 0
    BusFree =: 0
    BusWait =: 0
    TxStart =: i.0
    TxCore =: i.0
    TxKind =: i.0
    TxBlock =: i.0
    TxSnoop =: 0$a:
    TxSnoopHits =: i.0
    TxInvalidations =: i.0
    TxSupplier =: i.0
    TxFlush =: i.0
    TxL2 =: i.0
    TxEvicted =: i.0
    TxBackCopies =: 0$a:
    TxDirty =: i.0
    TxSource =: 0$a:
)
bus_assign =: 3 : 0
    'core kind block requested' =. y
    index =. #TxStart
    start =. requested>.BusFree
    BusWait =: BusWait+start-requested
    BusFree =: start+TB
    TxStart =: TxStart,start
    TxCore =: TxCore,core
    TxKind =: TxKind,kind
    TxBlock =: TxBlock,block
    TxSnoop =: TxSnoop,<0$a:
    TxSnoopHits =: TxSnoopHits,0
    TxInvalidations =: TxInvalidations,0
    TxSupplier =: TxSupplier,_1
    TxFlush =: TxFlush,0
    TxL2 =: TxL2,0
    TxEvicted =: TxEvicted,_1
    TxBackCopies =: TxBackCopies,<0$a:
    TxDirty =: TxDirty,0
    TxSource =: TxSource,<''
    index
)
bus_line =: 3 : 0
    kind =. y{TxKind
    line =. (integer y+1),' ',(integer y{TxStart),' c',(integer y{TxCore),' ',(kind{::Transactions),' ',hex_address LineSize*y{TxBlock
    if. kind=4 do.
        line return.
    end.
    snoops =. 'none'
    if. #y{::TxSnoop do.
        snoops =. ' 'join y{::TxSnoop
    end.
    line =. line,' snoop ',snoops
    if. kind=2 do.
        line return.
    end.
    if. kind e.0 1 do.
        line =. line,' data ',y{::TxSource
    end.
    line =. line,' l2 ',(y{TxL2){::'';'hit';'miss'
    if. _1~:y{TxEvicted do.
        copies =. 'none'
        if. #y{::TxBackCopies do.
            copies =. ' 'join y{::TxBackCopies
        end.
        quality =. (y{TxDirty){::'clean';'dirty'
        line =. line,' evict ',(hex_address LineSize*y{TxEvicted),' ',copies,' ',quality
    end.
    line
)
