split =: 4 : '<;._1 x,y'
join =: 4 : 0
    result =. ''
    for_i. i.#y do.
        if. i do. result =. result,x end.
        result =. result,i{::y
    end.
    result
)
num =: 3 : 'x: 0".y'
text =: 3 : 0
    if. 2=3!:0 y do. y return. end.
    value =. ":y
    '-'(I.value='_')}value
)
line =: 3 : ''' ''join text&.>y'
load 'hashing.ijs'
load 'wallets.ijs'
load 'transactions.ijs'
load 'blocks.ijs'
load 'chain.ijs'
m_transaction =: 0&{::
m_fee =: 1&{::
m_arrival =: 2&{::
o_block =: 0&{::
o_peer =: 1&{::
current_record =: 3 : 'Tip{::Records'
current_utxo =: r_utxo@current_record
next_height =: 3 : '>:r_height current_record 0'
block_reward =: 3 : 'reward y,InitialReward,HalvingInterval'
difficulty =: 3 : 'Records required_difficulty y,InitialDifficulty,Retarget,Target'
coin_mature =: 3 : 'y is_mature (next_height 0),Maturity'
coin_at =: 4 : '((0{::x)i.<y){::1{::x'
owner =: 3 : '(WalletAddresses i.<y){::Wallets'
named_wallet =: 3 : '(WalletNames i.<y){::Wallets'
log =: 3 : 'Log =: Log,<(":Now),'' '',y'
tally =: 4 : 0
    key =. x,' ',y
    index =. RejectionKeys i.<key
    if. index=#RejectionKeys do.
        RejectionKeys =: RejectionKeys,<key
        RejectionCounts =: RejectionCounts,0
    end.
    RejectionCounts =: (>:index{RejectionCounts)index}RejectionCounts
)
increment_peer =: 3 : 0
    'peer column amount' =. y
    PeerStats =: (amount+(<peer,column){PeerStats)(<peer,column)}PeerStats
)
peer =: 3 : 0
    index =. PeerNames i.<y
    if. index=#PeerNames do.
        PeerNames =: PeerNames,<y
        PeerStats =: PeerStats,1 7$0
    end.
    index
)
penalize =: 3 : 0
    'peer amount' =. y
    before =. (<peer,6){PeerStats
    increment_peer peer,6,amount
    after =. (<peer,6){PeerStats
    if. (before<BanScore)*.after>:BanScore do. log line 'BAN';(peer{::PeerNames);'score';after end.
)
refresh_main =: 3 : 0
    Main =: Records chain_to Tip
    Confirmed =: 0$a:
    ConfirmedHeights =: i.0
    for_index. Main do.
        record =. index{::Records
        ids =. b_txids r_block record
        Confirmed =: Confirmed,ids
        ConfirmedHeights =: ConfirmedHeights,(#ids)#r_height record
    end.
    i.0
)
append_record =: 3 : 0
    'block parent utxo fees source' =. y
    work =. 1
    if. parent>:0 do. work =. (r_work parent{::Records)+16^b_difficulty block end.
    record =. (<block),(<parent),(<utxo),(<fees),(<source),<work
    index =. #Records
    Records =: Records,<record
    RecordHashes =: RecordHashes,<b_hash block
    index
)
locked_references =: 3 : 0
    references =. 0$a:
    for_entry. Mempool do. references =. references,tx_inputs m_transaction >entry end.
    ~.references
)
priority_before =: 4 : 0
    first =. x{::Mempool
    second =. y{::Mempool
    a =. m_transaction first
    b =. m_transaction second
    left =. (m_fee first)*tx_size b
    right =. (m_fee second)*tx_size a
    if. left~:right do. left>right return. end.
    (tx_id a)before tx_id b
)
before =: 4 : 0
    if. x-:y do. 0 return. end.
    x-:0{::/:~x;y
)
priority_order =: 3 : 0
    ranked =. i.0
    for_index. i.#Mempool do.
        position =. #ranked
        ranked =. ranked,index
        while. position>0 do.
            if. -.index priority_before (position-1){ranked do. break. end.
            ranked =. ((position-1){ranked)position}ranked
            position =. position-1
        end.
        ranked =. index position}ranked
    end.
    ranked
)
find_entry =: 3 : '(tx_id@m_transaction&.>Mempool)i.<y'
acceptance =: 3 : 0
    transaction =. y
    if. is_coinbase transaction do. ('coinbase';0),<0$a: return. end.
    if. ((<tx_id transaction)e.Confirmed)+.(find_entry tx_id transaction)<#Mempool do.
        ('duplicate';0),<0$a: return.
    end.
    'reason fee' =. check_transaction (<transaction),(<current_utxo 0),(<0$a:),(<next_height 0),(<Wallets),<Maturity
    if. #reason do. (reason;0),<0$a: return. end.
    if. (fee*1000)<MinFeeRate*tx_size transaction do. ('low-fee';0),<0$a: return. end.
    conflicts =. 0$a:
    total =. 0
    higher =. 1
    inputs =. tx_inputs transaction
    for_entry. Mempool do.
        pending =. >entry
        other =. m_transaction pending
        if. +./(tx_inputs other)e.inputs do.
            conflicts =. conflicts,<tx_id other
            total =. total+m_fee pending
            higher =. higher*.(fee*tx_size other)>(m_fee pending)*tx_size transaction
        end.
    end.
    if. (#conflicts)*.((fee<:total)+.-.higher) do. ('conflict';0),<0$a: return. end.
    ('';fee),<conflicts
)
record_drop =: 4 : 0
    index =. DroppedIds i.<y
    if. index=#DroppedIds do.
        DroppedIds =: DroppedIds,<y
        DroppedReasons =: DroppedReasons,<x
    else.
        DroppedReasons =: (<x)index}DroppedReasons
    end.
    log line 'DROP';(short y);x
)
drop =: 4 : 0
    keep =. -. (tx_id@m_transaction&.>Mempool)e.<y
    Mempool =: keep#Mempool
    x record_drop y
)
register =: 3 : 0
    'transaction fee conflicts arrival' =. y
    for_id. conflicts do. 'replaced'drop >id end.
    Mempool =: Mempool,<(<transaction),(<fee),<arrival
    if. (#Mempool)>MempoolLimit do.
        lowest =. ({:priority_order 0){::Mempool
        'mempool-full'drop tx_id m_transaction lowest
    end.
    i.0
)
rebuild_mempool =: 3 : 0
    previous =. Mempool
    Mempool =: 0$a:
    candidates =. 0$a:
    for_transaction. y do.
        candidates =. candidates,<transaction,(<Now),<1
    end.
    for_entry. previous do.
        value =. >entry
        candidates =. candidates,<(<m_transaction value),(<m_arrival value),<0
    end.
    for_candidate. candidates do.
        'transaction arrival returned' =. >candidate
        if. (<tx_id transaction)e.Confirmed do. continue. end.
        'reason fee conflicts' =. acceptance transaction
        if. #reason do.
            reason record_drop tx_id transaction
        else.
            if. returned do. log line 'RETURN';short tx_id transaction end.
            register (<transaction),(<fee),(<conflicts),<arrival
        end.
    end.
    i.0
)
switch_tip =: 3 : 0
    target =. y
    old =. Tip
    fork =. Records fork_point Tip,target
    forkheight =. r_height fork{::Records
    disconnected =. (r_height old{::Records)-forkheight
    record =. target{::Records
    connected =. (r_height record)-forkheight
    if. disconnected>MaxReorg do.
        log line 'REFUSE';(r_height record);(short r_hash record);'work';(r_work record);'fork';forkheight;'depth';disconnected
        i.0 return.
    end.
    returned =. 0$a:
    for_index. (forkheight+1)}.Main do.
        returned =. returned,}.b_transactions r_block index{::Records
    end.
    Tip =: target
    refresh_main 0
    if. disconnected=0 do.
        log line 'TIP';(r_height record);(short r_hash record);'work';r_work record
    else.
        log line 'REORG';(r_height record);(short r_hash record);'work';(r_work record);'fork';forkheight;'disconnected';disconnected;'connected';connected
        Reorganizations =: Reorganizations,<(<Now),(<forkheight),(<disconnected),(<connected),(<r_hash old{::Records),<r_hash record
    end.
    rebuild_mempool returned
)
reference_key =: 3 : '(33{.y),_2{.''00'',33}.y'
reference_order =: /:@(reference_key&.>)
pay =: 3 : 0
    fields =. y
    sender =. named_wallet 2{::fields
    fee =. num 3{::fields
    addresses =. 0$a:
    amounts =. i.0
    for_i. 4+2*i.((#fields)-4)intdiv 2 do.
        addresses =. addresses,<wallet_address named_wallet i{::fields
        amounts =. amounts,num (i+1){::fields
    end.
    total =. +/amounts
    prefix =. line 'PAY';(wallet_name sender);'fee';fee;'total';total
    'references coins' =. current_utxo 0
    held =. locked_references 0
    selected =. i.0
    for_i. reference_order references do.
        coin =. i{::coins
        if. ((coin_address coin)-:wallet_address sender)*.(-.(i{references)e.held)*.coin_mature coin do.
            selected =. selected,i
        end.
    end.
    selected =. (\:coin_amount&>selected{coins){selected
    gathered =. 0
    inputs =. 0$a:
    for_i. selected do.
        if. gathered>:total+fee do. break. end.
        inputs =. inputs,i{references
        gathered =. gathered+coin_amount i{::coins
    end.
    if. gathered<total+fee do.
        log prefix,' rejected insufficient-funds'
        'pay'tally 'insufficient-funds'
        i.0 return.
    end.
    if. gathered>total+fee do.
        addresses =. addresses,<wallet_address sender
        amounts =. amounts,gathered-(total+fee)
    end.
    transaction =. create_transaction (<inputs),(<addresses),(<amounts),<wallet_secret sender
    'reason acceptedfee conflicts' =. acceptance transaction
    prefix =. prefix,' tx ',short tx_id transaction
    if. #reason do.
        log prefix,' rejected ',reason
        'pay'tally reason
    else.
        log prefix,' ',line 'accepted';'inputs';(#inputs);'outputs';(#addresses);'size';tx_size transaction
        register (<transaction),(<acceptedfee),(<conflicts),<Now
    end.
    i.0
)
bump =: 3 : 0
    'id fee' =. y
    prefix =. line 'BUMP';(short id);'fee';fee
    index =. find_entry id
    if. index=#Mempool do.
        log prefix,' rejected unknown'
        'bump'tally 'unknown'
        i.0 return.
    end.
    pending =. index{::Mempool
    original =. m_transaction pending
    addresses =. tx_addresses original
    amounts =. tx_amounts original
    address =. {:addresses
    change =. ({:amounts)-(fee-m_fee pending)
    valid =. change>:1
    utxo =. current_utxo 0
    for_reference. tx_inputs original do.
        valid =. valid*.address-:<coin_address utxo coin_at >reference
    end.
    if. -.valid do.
        log prefix,' rejected no-change'
        'bump'tally 'no-change'
        i.0 return.
    end.
    amounts =. change(<:#amounts)}amounts
    transaction =. create_transaction (<tx_inputs original),(<addresses),(<amounts),<wallet_secret owner >address
    'reason acceptedfee conflicts' =. acceptance transaction
    prefix =. prefix,' tx ',short tx_id transaction
    if. #reason do.
        log prefix,' rejected ',reason
        'bump'tally reason
    else.
        log prefix,' accepted size ',":tx_size transaction
        register (<transaction),(<acceptedfee),(<conflicts),<Now
    end.
    i.0
)
receive_transaction =: 3 : 0
    'peer transaction' =. y
    'reason fee conflicts' =. acceptance transaction
    prefix =. line 'TX';(peer{::PeerNames);short tx_id transaction
    if. #reason do.
        increment_peer peer,4,1
        'tx'tally reason
        log prefix,' rejected ',reason
        if. (<reason)e.'coinbase';'bad-output';'bad-sig';'overspend' do. penalize peer,TxPenalty end.
    else.
        increment_peer peer,3,1
        log prefix,' ',line 'accepted';'fee';fee;'size';tx_size transaction
        register (<transaction),(<fee),(<conflicts),<Now
    end.
    i.0
)
mine =: 3 : 0
    wallet =. y
    height =. next_height 0
    transactions =. 0$a:
    fees =. i.0
    size =. 0
    for_i. priority_order 0 do.
        entry =. i{::Mempool
        transaction =. m_transaction entry
        if. (size+tx_size transaction)<:MaxBlock do.
            transactions =. transactions,<transaction
            fees =. fees,m_fee entry
            size =. size+tx_size transaction
        end.
    end.
    coinbase =. create_coinbase (<height),(<,<wallet_address wallet),<,(block_reward height)++/fees
    transactions =. (<coinbase),transactions
    timestamp =. Now>.1+Records median_time Tip
    block =. mine_block (<height),(<r_hash current_record 0),(<transactions),(<timestamp),<difficulty Tip
    utxo =. current_utxo 0
    for_transaction. transactions do. utxo =. utxo apply_transaction transaction,<height end.
    index =. append_record (<block),(<Tip),(<utxo),(<fees),<'local'
    record =. index{::Records
    log line 'MINE';(wallet_name wallet);height;(short b_hash block);'bits';(b_difficulty block);'nonce';(b_nonce block);'txs';(#transactions);'size';size;'fees';(+/fees);'work';r_work record
    switch_tip index
)
reject_block =: 3 : 0
    'kind block peer reason' =. y
    Rejected =: ~.Rejected,<b_hash block
    increment_peer peer,1,1
    'block'tally 0{::' 'split reason
    log line kind;(peer{::PeerNames);(b_height block);(short b_hash block);'rejected';reason
    if. -.reason-:'time-too-new' do. penalize peer,BlockPenalty end.
    i.0
)
validate_block =: 3 : 0
    'block parent' =. y
    record =. parent{::Records
    utxo =. r_utxo record
    fees =. i.0
    if. (b_height block)~:1+r_height record do. (<'bad-height'),(<utxo),<fees return. end.
    if. (b_difficulty block)~:difficulty parent do. (<'bad-difficulty'),(<utxo),<fees return. end.
    if. (b_time block)<:Records median_time parent do. (<'time-too-old'),(<utxo),<fees return. end.
    if. (b_time block)>Now+Drift do. (<'time-too-new'),(<utxo),<fees return. end.
    spent =. 0$a:
    transactions =. b_transactions block
    for_i. 1+i.<:#transactions do.
        transaction =. i{::transactions
        'reason fee' =. check_transaction (<transaction),(<utxo),(<spent),(<b_height block),(<Wallets),<Maturity
        if. #reason do. ((<reason,' tx ',":i+1),<utxo),<fees return. end.
        spent =. ~.spent,tx_inputs transaction
        utxo =. utxo apply_transaction (<transaction),<b_height block
        fees =. fees,fee
    end.
    coinbase =. 0{::transactions
    if. (0 e.tx_amounts coinbase)+.-.*./(tx_addresses coinbase)e.WalletAddresses do. (<'bad-output tx 1'),(<utxo),<fees return. end.
    if. (tx_total coinbase)>(block_reward b_height block)++/fees do. (<'bad-coinbase'),(<utxo),<fees return. end.
    utxo =. utxo apply_transaction (<coinbase),<b_height block
    (<''),(<utxo),<fees
)
connect_block =: 3 : 0
    'kind block peer' =. y
    parent =. RecordHashes i.<b_previous block
    'reason utxo fees' =. validate_block (<block),<parent
    if. #reason do. reject_block (<kind),(<block),(<peer),<reason return. end.
    index =. append_record (<block),(<parent),(<utxo),(<fees),peer{PeerNames
    record =. index{::Records
    increment_peer peer,0,1
    log line kind;(peer{::PeerNames);(b_height block);(short b_hash block);'accepted';'work';r_work record
    if. (r_work record)>r_work current_record 0 do. switch_tip index end.
    i.0
)
resolve_orphans =: 3 : 0
    queue =. ,<y
    head =. 0
    while. head<#queue do.
        parent =. head{::queue
        head =. head+1
        children =. Orphans#~(b_previous@o_block&.>Orphans)e.<parent
        Orphans =: Orphans#~-. (b_previous@o_block&.>Orphans)e.<parent
        for_orphan. children do.
            'block peer' =. >orphan
            if. (<parent)e.Rejected do.
                reject_block (<'UNORPHAN'),(<block),(<peer),<'bad-parent'
            else.
                connect_block (<'UNORPHAN'),(<block),<peer
            end.
            queue =. queue,<b_hash block
        end.
    end.
    i.0
)
receive_block =: 3 : 0
    'peer block' =. y
    hash =. b_hash block
    prefix =. line 'BLOCK';(peer{::PeerNames);(b_height block);short hash
    duplicate =. (<hash)e.RecordHashes,Rejected,b_hash@o_block&.>Orphans
    if. duplicate do.
        log prefix,' rejected duplicate'
        increment_peer peer,1,1
        'block'tally 'duplicate'
        i.0 return.
    end.
    reason =. MaxBlock context_free_error block
    if. (0=#reason)*.(<b_previous block)e.Rejected do. reason =. 'bad-parent' end.
    if. #reason do.
        reject_block (<'BLOCK'),(<block),(<peer),<reason
        resolve_orphans hash
        i.0 return.
    end.
    if. -.(<b_previous block)e.RecordHashes do.
        Orphans =: Orphans,<(<block),<peer
        increment_peer peer,2,1
        log prefix,' orphan parent ',short b_previous block
        if. (#Orphans)>OrphanLimit do.
            log 'EVICT ',(short b_hash o_block 0{::Orphans),' orphan-limit'
            Orphans =: }.Orphans
        end.
        i.0 return.
    end.
    connect_block (<'BLOCK'),(<block),<peer
    resolve_orphans hash
)
status =: 3 : 0
    prefix =. 'STATUS ',short y
    position =. Confirmed i.<y
    if. position<#Confirmed do.
        height =. position{ConfirmedHeights
        log prefix,' ',line 'confirmed';height;'confirmations';(next_height 0)-height
        i.0 return.
    end.
    ranked =. priority_order 0
    for_rank. i.#ranked do.
        transaction =. m_transaction (rank{ranked){::Mempool
        if. y-:tx_id transaction do.
            log prefix,' ',line 'mempool';'rank';(rank+1);'of';#ranked
            i.0 return.
        end.
    end.
    position =. DroppedIds i.<y
    if. position<#DroppedIds do. log prefix,' dropped ',position{::DroppedReasons return. end.
    for_record. Records do.
        if. (<y)e.b_txids r_block >record do. log prefix,' stale' return. end.
    end.
    log prefix,' unknown'
)
balance =: 3 : '+/coin_amount&>(1{::current_utxo 0)#~(coin_address&.>1{::current_utxo 0)e.<y'
print_state =: 3 : 0
    ranked =. priority_order 0
    size =. +/tx_size@m_transaction&>Mempool
    record =. current_record 0
    log line 'PRINT';'height';(r_height record);'tip';(short r_hash record);'work';(r_work record);'bits';(difficulty Tip);'reward';(block_reward next_height 0);'mempool';(#ranked);'size';size;'orphans';#Orphans
    for_rank. i.#ranked do.
        entry =. (rank{ranked){::Mempool
        log line 'MEMPOOL';(rank+1);(short tx_id m_transaction entry);'fee';(m_fee entry);'size';tx_size m_transaction entry
    end.
    for_wallet. Wallets do.
        log line 'BALANCE';(wallet_name >wallet);balance wallet_address >wallet
    end.
    i.0
)
process_event =: 3 : 0
    'fields texts' =. y
    Now =: num 0{::fields
    previous =. Mempool
    for_entry. previous do.
        value =. >entry
        if. (Now-m_arrival value)>:Expiry do. 'expired'drop tx_id m_transaction value end.
    end.
    kind =. 1{::fields
    select. kind
    case. 'PAY' do. pay fields
    case. 'BUMP' do. bump (2{fields),<num 3{::fields
    case. 'MINE' do. mine named_wallet 2{::fields
    case. 'STATUS' do. status 2{::fields
    case. 'PRINT' do. print_state 0
    case. do.
        sender =. peer 2{::fields
        if. ((<sender,6){PeerStats)>:BanScore do.
            increment_peer sender,5,1
            log line 'IGNORE';(sender{::PeerNames);kind
        elseif. kind-:'TX' do.
            receive_transaction (<sender),<parse_transaction 3{::fields
        else.
            receive_block (<sender),<parse_block_event (<fields),<texts
        end.
    end.
    i.0
)
miner_address =: 3 : '0{::tx_addresses 0{::b_transactions r_block y'
chain_lines =: 3 : 0
    head =. current_record 0
    lines =. ,<line 'TIP';(r_height head);(r_hash head);'work';(r_work head);'stored';(#Records);'orphans';#Orphans
    rewards =. fees =. minted =. 0
    for_index. Main do.
        record =. index{::Records
        block =. r_block record
        transactions =. b_transactions block
        miner =. '-'
        if. (r_height record)>0 do.
            miner =. wallet_name owner miner_address record
            rewards =. rewards+block_reward r_height record
            fees =. fees+r_fees record
            minted =. minted+tx_total 0{::transactions
        end.
        lines =. lines,<line 'BLOCK';(b_height block);(b_hash block);'prev';(short b_previous block);'time';(b_time block);'bits';(b_difficulty block);'nonce';(b_nonce block);'txs';(#transactions);'size';(b_size block);'fees';(r_fees record);'miner';miner;'source';(r_source record);'work';r_work record
        for_i. i.#transactions do.
            transaction =. i{::transactions
            if. is_coinbase transaction do.
                category =. 'coinbase'
                if. 0=b_height block do. category =. 'genesis' end.
                lines =. lines,<line 'TX';(i+1);(tx_id transaction);category;'out';(#tx_addresses transaction);'amount';tx_total transaction
            else.
                fee =. (i-1){r_txfees record
                lines =. lines,<line 'TX';(i+1);(tx_id transaction);'payment';'in';(#tx_inputs transaction);'out';(#tx_addresses transaction);'size';(tx_size transaction);'fee';fee
            end.
        end.
    end.
    stale =. (i.#Records)-.Main
    hashes =. r_hash&.>stale{Records
    stale =. (/:hashes){stale
    stale =. (/:r_height&>stale{Records){stale
    for_index. stale do.
        record =. index{::Records
        lines =. lines,<line 'STALE';(r_height record);(r_hash record);'prev';(short b_previous r_block record);'source';(r_source record);'work';r_work record
    end.
    for_orphan. Orphans do.
        'block sender' =. >orphan
        lines =. lines,<line 'ORPHAN';(b_height block);(b_hash block);'prev';(short b_previous block);'source';sender{::PeerNames
    end.
    for_change. Reorganizations do.
        'time fork disconnected connected old new' =. >change
        lines =. lines,<line 'REORG';time;'fork';fork;'disconnected';disconnected;'connected';connected;'old';(short old);'new';short new
    end.
    for_wallet. Wallets do.
        wallet =. >wallet
        count =. coinbase =. paid =. 0
        for_index. }.Main do.
            record =. index{::Records
            if. (miner_address record)-:wallet_address wallet do.
                count =. count+1
                coinbase =. coinbase+tx_total 0{::b_transactions r_block record
                paid =. paid+r_fees record
            end.
        end.
        if. count do. lines =. lines,<line 'MINER';(wallet_name wallet);'blocks';count;'coinbase';coinbase;'fees';paid end.
    end.
    first =. 1
    while. first<#Main do.
        last =. first
        bits =. b_difficulty r_block (first{Main){::Records
        while. (last+1)<#Main do.
            if. bits~:b_difficulty r_block ((last+1){Main){::Records do. break. end.
            last =. last+1
        end.
        heights =. (":first),'-',":last
        lines =. lines,<line 'BITS';bits;'heights';heights;'blocks';1+last-first
        first =. last+1
    end.
    for_sender. /:PeerNames do.
        stats =. sender{PeerStats
        state =. 'ok'
        if. (6{stats)>:BanScore do. state =. 'banned' end.
        lines =. lines,<line 'PEER';(sender{::PeerNames);'blocks';(0{stats);'rejected';(1{stats);'orphans';(2{stats);'txs';(3{stats);'rejected';(4{stats);'ignored';(5{stats);'score';(6{stats);state
    end.
    ranked =. priority_order 0
    for_rank. i.#ranked do.
        pending =. (rank{ranked){::Mempool
        transaction =. m_transaction pending
        lines =. lines,<line 'MEMPOOL';(rank+1);(tx_id transaction);'fee';(m_fee pending);'size';(tx_size transaction);'time';m_arrival pending
    end.
    for_index. /:RejectionKeys do.
        lines =. lines,<line 'REJECT';(index{::RejectionKeys);index{RejectionCounts
    end.
    genesis =. tx_total 0{::b_transactions r_block 0{::Records
    total =. +/coin_amount&>1{::r_utxo head
    lines =. lines,<line 'SUPPLY';'genesis';genesis;'rewards';rewards;'fees';fees;'burned';(rewards+fees-minted);'utxo';total
    lines
)
balance_lines =: 3 : 0
    lines =. ,<'wallet,address,balance,immature,locked,incoming,utxos'
    held =. locked_references 0
    'references coins' =. current_utxo 0
    for_wallet. Wallets do.
        wallet =. >wallet
        address =. wallet_address wallet
        total =. immature =. locked =. count =. incoming =. 0
        for_i. i.#references do.
            coin =. i{::coins
            if. -.address-:coin_address coin do. continue. end.
            total =. total+coin_amount coin
            count =. count+1
            if. -.coin_mature coin do. immature =. immature+coin_amount coin end.
            if. (i{references)e.held do. locked =. locked+coin_amount coin end.
        end.
        for_pending. Mempool do.
            transaction =. m_transaction >pending
            incoming =. incoming++/(tx_amounts transaction)#~(tx_addresses transaction)e.<address
        end.
        values =. (wallet_name wallet);address;total;immature;locked;incoming;count
        lines =. lines,<','join text&.>values
    end.
    lines
)
utxo_lines =: 3 : 0
    lines =. hashes =. 0$a:
    held =. locked_references 0
    'references coins' =. current_utxo 0
    total =. 0
    for_i. reference_order references do.
        reference =. i{::references
        coin =. i{::coins
        category =. 'payment'
        if. 0=coin_height coin do. category =. 'genesis'
        elseif. coin_coinbase coin do. category =. 'coinbase' end.
        state =. 'free'
        if. -.coin_mature coin do. state =. 'immature'
        elseif. (<reference)e.held do. state =. 'locked' end.
        value =. line reference;(wallet_name owner coin_address coin);(coin_amount coin);'height';(coin_height coin);category;state
        lines =. lines,<value
        hashes =. hashes,<digest value
        total =. total+coin_amount coin
    end.
    lines,(<line 'TOTAL';(#references);total),<line 'ROOT';merkle_root hashes
)
signed =: 3 : 0
    if. y<0 do. text y else. '+',text y end.
)
history_lines =: 3 : 0
    ids =. confirmed_transactions =. 0$a:
    for_index. Main do.
        transactions =. b_transactions r_block index{::Records
        ids =. ids,tx_id&.>transactions
        confirmed_transactions =. confirmed_transactions,transactions
    end.
    lines =. 0$a:
    for_wallet. Wallets do.
        wallet =. >wallet
        address =. wallet_address wallet
        lines =. lines,<line 'WALLET';(wallet_name wallet);address
        count =. spent_total =. received_total =. running =. 0
        for_index. Main do.
            record =. index{::Records
            height =. r_height record
            for_transaction. b_transactions r_block record do.
                transaction =. >transaction
                spent =. 0
                involved =. 0
                for_reference. tx_inputs transaction do.
                    'id number' =. ':'split >reference
                    earlier =. (ids i.<id){::confirmed_transactions
                    position =. num number
                    if. address-:position{::tx_addresses earlier do.
                        spent =. spent+position{tx_amounts earlier
                        involved =. 1
                    end.
                end.
                own =. (tx_addresses transaction)e.<address
                received =. +/own#tx_amounts transaction
                involved =. involved+.+./own
                if. -.involved do. continue. end.
                count =. count+1
                spent_total =. spent_total+spent
                received_total =. received_total+received
                running =. running+received-spent
                category =. 'payment'
                if. is_coinbase transaction do.
                    category =. 'coinbase'
                    if. height=0 do. category =. 'genesis' end.
                end.
                lines =. lines,<line height;(short tx_id transaction);category;'spent';spent;'received';received;'net';(signed received-spent);'balance';running
            end.
        end.
        pending_count =. 0
        utxo =. current_utxo 0
        for_i. priority_order 0 do.
            transaction =. m_transaction i{::Mempool
            spent =. 0
            for_reference. tx_inputs transaction do.
                coin =. utxo coin_at >reference
                if. address-:coin_address coin do. spent =. spent+coin_amount coin end.
            end.
            received =. +/(tx_amounts transaction)#~(tx_addresses transaction)e.<address
            if. (spent~:0)+.received~:0 do.
                pending_count =. pending_count+1
                lines =. lines,<line 'pending';(short tx_id transaction);'spent';spent;'received';received;'net';signed received-spent
            end.
        end.
        lines =. lines,<line 'END';(wallet_name wallet);'txs';count;'spent';spent_total;'received';received_total;'balance';running;'pending';pending_count
    end.
    lines
)
write_lines =: 4 : 0
    result =. ''
    for_value. y do. result =. result,(>value),LF end.
    result 1!:2 <'output/',x
)
initialize =: 3 : 0
    rows =. 0$a:
    for_row. <;._2 (1!:1 <'input/params.txt') do.
        rows =. rows,<' 'split >row
    end.
    InitialDifficulty =: num 1{::0{::rows
    'Retarget Target' =: num&>}.1{::rows
    'InitialReward HalvingInterval' =: num&>}.2{::rows
    'Maturity MaxBlock MinFeeRate MempoolLimit OrphanLimit Drift Expiry MaxReorg' =: num&>1&{::&.>3 4 5 6 7 8 9 10{rows
    'BanScore BlockPenalty TxPenalty' =: num&>}.11{::rows
    genesis =. }.12{::rows
    Wallets =: read_wallets 'input/wallets.txt'
    WalletNames =: wallet_name&.>Wallets
    WalletAddresses =: wallet_address&.>Wallets
    Now =: 0
    Tip =: 0
    Records =: RecordHashes =: Main =: Confirmed =: ConfirmedHeights =: Mempool =: Orphans =: Rejected =: DroppedIds =: DroppedReasons =: PeerNames =: RejectionKeys =: Reorganizations =: Log =: 0$a:
    RejectionCounts =: i.0
    PeerStats =: 0 7$0
    addresses =. 0$a:
    amounts =. i.0
    for_i. 2*i.(#genesis)intdiv 2 do.
        addresses =. addresses,<wallet_address named_wallet i{::genesis
        amounts =. amounts,num (i+1){::genesis
    end.
    coinbase =. create_coinbase (<0),(<addresses),<amounts
    block =. make_block (<0),(<32#'0'),(<tx_id coinbase),(<0),(<0),(<0),<,<coinbase
    utxo =. ((<0$a:),<0$a:)apply_transaction (<coinbase),<0
    append_record (<block),(<_1),(<utxo),(<i.0),<'genesis'
    refresh_main 0
    i.0
)
run =: 3 : 0
    initialize 0
    events =: <;._2 (1!:1 <'input/events.txt')
    position =: 0
    while. position<#events do.
        fields =. ' 'split position{::events
        count =. 0
        if. 'BLOCK'-:1{::fields do. count =. num 9{::fields end.
        texts =. count{.(position+1)}.events
        process_event (<fields),<texts
        position =: position+count+1
    end.
    try. 1!:5 <'output' catch. end.
    'log.txt'write_lines Log
    'chain.txt'write_lines chain_lines 0
    'balances.csv'write_lines balance_lines 0
    'utxo.txt'write_lines utxo_lines 0
    'history.txt'write_lines history_lines 0
    i.0
)
run 0
