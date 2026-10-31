include("hashing.jl")
include("wallets.jl")
include("transactions.jl")
include("blocks.jl")
include("chain.jl")

mutable struct Peer
    name::String
    blocks::Int
    rejected_blocks::Int
    orphans::Int
    txs::Int
    rejected_txs::Int
    ignored::Int
    score::Int
end
Peer(name) = Peer(name,0,0,0,0,0,0,0)
struct MempoolEntry
    transaction::Transaction
    fee::Int
    arrival::Int
end
mutable struct Node
    params::Dict{String,Vector{String}}
    wallets::Vector{Wallet}
    owners::Dict{String,Wallet}
    named::Dict{String,Wallet}
    now::Int
    records::Dict{String,BlockRecord}
    mempool::Vector{MempoolEntry}
    orphans::Vector{Tuple{Block,Peer}}
    rejected::Set{String}
    drops::Dict{String,String}
    peers::Dict{String,Peer}
    rejections::Dict{Tuple{String,String},Int}
    reorganizations::Vector{Tuple{Int,Int,Int,Int,String,String}}
    log::Vector{String}
    tip::BlockRecord
    main_chain::Vector{BlockRecord}
    confirmed::Dict{String,Int}
end
setting(node,key,i=1) = parse(Int,node.params[key][i])
height(record) = record.block.height
next_height(node) = height(node.tip)+1
reward(node,h) = block_reward(h,setting(node,"REWARD"),setting(node,"REWARD",2))
difficulty(node,parent=node.tip) = required_difficulty(
    parent,
    setting(node,"DIFFICULTY"),
    setting(node,"RETARGET"),
    setting(node,"RETARGET",2)
)
mature(node,coin) = is_mature(coin,next_height(node),setting(node,"MATURITY"))
node_balance(
    node,
    address
) = sum((coin.amount for coin in values(node.tip.utxo) if coin.address == address);init=0)
locked_references(node) = Set(ref for entry in node.mempool for ref in entry.transaction.inputs)
priority_order(node) = sort(
    node.mempool,
    lt=(
        a,
        b
    )->a.fee*b.transaction.size == b.fee*a.transaction.size ? a.transaction.txid < b.transaction.txid : a.fee*b.transaction.size > b.fee*a.transaction.size
)
find_entry(node,txid) = findfirst(entry->entry.transaction.txid == txid,node.mempool)
log!(node,parts...) = push!(node.log,join((node.now,parts...),' '))
signed(value) = (value < 0 ? "" : "+") * string(value)
function tally!(node,category,reason)
    key = (category,reason)
    node.rejections[key] = get(node.rejections,key,0)+1
end
function refresh_chain!(node)
    node.main_chain = chain_to(node.tip)
    empty!(node.confirmed)
    for record in node.main_chain, tx in record.block.transactions
        node.confirmed[tx.txid] = height(record)
    end
end
function Node(params,wallets)
    named = Dict(w.name=>w for w in wallets)
    genesis = params["GENESIS"]
    outputs = [(named[genesis[i]].address,parse(Int,genesis[i+1])) for i in 1:2:length(genesis)]
    tx = create_coinbase(0,outputs)
    block = Block(0,repeat("0",32),tx.txid,0,0,0,[tx])
    utxo = Dict{Reference,Coin}()
    apply_transaction!(utxo,tx,0)
    record = BlockRecord(block,nothing,utxo,Int[],"genesis")
    node = Node(
        params,
        wallets,
        Dict(w.address=>w for w in wallets),
        named,
        0,
        Dict(record.block.hash=>record),
        MempoolEntry[],
        Tuple{Block,Peer}[],
        Set{String}(),
        Dict{String,String}(),
        Dict{String,Peer}(),
        Dict{Tuple{String,String},Int}(),
        Tuple{Int,Int,Int,Int,String,String}[],
        String[],
        record,
        BlockRecord[],
        Dict{String,Int}()
    )
    refresh_chain!(node)
    node
end
function acceptance(node,tx)
    is_coinbase(tx) && return ("coinbase",0,MempoolEntry[])
    (haskey(node.confirmed,tx.txid) || !isnothing(find_entry(node,tx.txid))) && return (
        "duplicate",
        0,
        MempoolEntry[]
    )
    reason,fee = check_transaction(
        tx,
        node.tip.utxo,
        Set{Reference}(),
        next_height(node),
        node.owners,
        setting(node,"MATURITY")
    )
    !isnothing(reason) && return (reason,0,MempoolEntry[])
    fee*1000 < setting(node,"MINFEERATE")*tx.size && return ("low-fee",0,MempoolEntry[])
    inputs = Set(tx.inputs)
    conflicts = [entry for entry in node.mempool if any(ref in inputs for ref in entry.transaction.inputs)]
    if !isempty(conflicts) && !(fee > sum(entry.fee for entry in conflicts) && all(fee*entry.transaction.size > entry.fee*tx.size for entry in conflicts))
        return ("conflict",0,MempoolEntry[])
    end
    nothing,fee,conflicts
end
function record_drop!(node,txid,reason)
    node.drops[txid] = reason
    log!(node,"DROP",short_hash(txid),reason)
end
function drop!(node,entry,reason)
    filter!(other->other !== entry,node.mempool)
    record_drop!(node,entry.transaction.txid,reason)
end
function register!(node,tx,result,arrival)
    _,fee,conflicts = result
    for entry in conflicts
        drop!(node,entry,"replaced")
    end
    push!(node.mempool,MempoolEntry(tx,fee,arrival))
    length(node.mempool) > setting(node,"MEMPOOL") && drop!(node,priority_order(node)[end],"mempool-full")
end
function rebuild_mempool!(node,returned)
    previous = node.mempool
    node.mempool = MempoolEntry[]
    candidates = vcat(
        [(tx,node.now,true) for tx in returned],
        [(entry.transaction,entry.arrival,false) for entry in previous]
    )
    for (tx,arrival,is_returned) in candidates
        haskey(node.confirmed,tx.txid) && continue
        result = acceptance(node,tx)
        if !isnothing(result[1])
            record_drop!(node,tx.txid,result[1])
        else
            is_returned && log!(node,"RETURN",short_hash(tx.txid))
            register!(node,tx,result,arrival)
        end
    end
end
function switch_tip!(node,target)
    old = node.tip
    fork = fork_point(old,target)
    disconnected,connected = height(old)-height(fork),height(target)-height(fork)
    if disconnected > setting(node,"MAXREORG")
        log!(
            node,
            "REFUSE",
            height(target),
            short_hash(target.block.hash),
            "work",
            target.cumulative_work,
            "fork",
            height(fork),
            "depth",
            disconnected
        )
        return
    end
    returned = [tx for record in node.main_chain[(height(fork)+2):end] for tx in record.block.transactions[2:end]]
    node.tip = target
    refresh_chain!(node)
    if disconnected == 0
        log!(node,"TIP",height(target),short_hash(target.block.hash),"work",target.cumulative_work)
    else
        log!(
            node,
            "REORG",
            height(target),
            short_hash(target.block.hash),
            "work",
            target.cumulative_work,
            "fork",
            height(fork),
            "disconnected",
            disconnected,
            "connected",
            connected
        )
        push!(
            node.reorganizations,
            (node.now,height(fork),disconnected,connected,old.block.hash,target.block.hash)
        )
    end
    rebuild_mempool!(node,returned)
end
function penalize!(node,peer,points)
    before = peer.score
    peer.score += points
    before < setting(node,"BAN") <= peer.score && log!(node,"BAN",peer.name,"score",peer.score)
end
function pay!(node,fields)
    sender = node.named[fields[3]]
    fee = parse(Int,fields[4])
    outputs = [(node.named[fields[i]].address,parse(Int,fields[i+1])) for i in 5:2:length(fields)]
    total = sum(v for (_,v) in outputs)
    need,gathered = total+fee,0
    locked = locked_references(node)
    coins = [(ref,coin) for (ref,coin) in node.tip.utxo if coin.address == sender.address && !(ref in locked) && mature(
        node,
        coin
    )]
    sort!(coins,by=item->(-item[2].amount,item[1]))
    inputs = Reference[]
    for (ref,coin) in coins
        gathered >= need && break
        push!(inputs,ref)
        gathered += coin.amount
    end
    prefix = ("PAY",sender.name,"fee",fee,"total",total)
    if gathered < need
        log!(node,prefix...,"rejected","insufficient-funds")
        tally!(node,"pay","insufficient-funds")
        return
    end
    gathered > need && push!(outputs,(sender.address,gathered-need))
    tx = create_transaction(inputs,outputs,sender.secret)
    result = acceptance(node,tx)
    if !isnothing(result[1])
        log!(node,prefix...,"tx",short_hash(tx.txid),"rejected",result[1])
        tally!(node,"pay",result[1])
    else
        log!(
            node,
            prefix...,
            "tx",
            short_hash(tx.txid),
            "accepted",
            "inputs",
            length(inputs),
            "outputs",
            length(outputs),
            "size",
            tx.size
        )
        register!(node,tx,result,node.now)
    end
end
function bump!(node,txid,fee)
    prefix = ("BUMP",short_hash(txid),"fee",fee)
    index = find_entry(node,txid)
    if isnothing(index)
        log!(node,prefix...,"rejected","unknown")
        tally!(node,"bump","unknown")
        return
    end
    entry = node.mempool[index]
    original = entry.transaction
    addresses = Set(node.tip.utxo[ref].address for ref in original.inputs)
    address,amount = original.outputs[end]
    change = amount-(fee-entry.fee)
    if addresses != Set([address]) || change < 1
        log!(node,prefix...,"rejected","no-change")
        tally!(node,"bump","no-change")
        return
    end
    outputs = copy(original.outputs)
    outputs[end] = (address,change)
    tx = create_transaction(original.inputs,outputs,node.owners[address].secret)
    result = acceptance(node,tx)
    if !isnothing(result[1])
        log!(node,prefix...,"tx",short_hash(tx.txid),"rejected",result[1])
        tally!(node,"bump",result[1])
    else
        log!(node,prefix...,"tx",short_hash(tx.txid),"accepted","size",tx.size)
        register!(node,tx,result,node.now)
    end
end
function receive_transaction!(node,peer,tx)
    result = acceptance(node,tx)
    if !isnothing(result[1])
        peer.rejected_txs += 1
        tally!(node,"tx",result[1])
        log!(node,"TX",peer.name,short_hash(tx.txid),"rejected",result[1])
        result[1] in (
            "coinbase",
            "bad-output",
            "bad-sig",
            "overspend"
        ) && penalize!(node,peer,setting(node,"BAN",3))
    else
        peer.txs += 1
        log!(node,"TX",peer.name,short_hash(tx.txid),"accepted","fee",result[2],"size",tx.size)
        register!(node,tx,result,node.now)
    end
end
function mine!(node,wallet)
    h = next_height(node)
    selected = MempoolEntry[]
    size = 0
    for entry in priority_order(node)
        if size+entry.transaction.size <= setting(node,"MAXBLOCK")
            push!(selected,entry)
            size += entry.transaction.size
        end
    end
    fees = [entry.fee for entry in selected]
    tx = create_coinbase(h,[(wallet.address,reward(node,h)+sum(fees;init=0))])
    txs = vcat([tx],[entry.transaction for entry in selected])
    block = mine_block(h,node.tip.block.hash,txs,max(node.now,median_time(node.tip)+1),difficulty(node))
    utxo = copy(node.tip.utxo)
    for tx in txs
        apply_transaction!(utxo,tx,h)
    end
    record = BlockRecord(block,node.tip,utxo,fees,"local")
    node.records[block.hash] = record
    log!(
        node,
        "MINE",
        wallet.name,
        h,
        short_hash(block.hash),
        "bits",
        block.difficulty,
        "nonce",
        block.nonce,
        "txs",
        length(txs),
        "size",
        size,
        "fees",
        record.fees,
        "work",
        record.cumulative_work
    )
    switch_tip!(node,record)
end
function reject_block!(node,kind,block,peer,reason)
    push!(node.rejected,block.hash)
    peer.rejected_blocks += 1
    tally!(node,"block",String(first(split(reason))))
    log!(node,kind,peer.name,block.height,short_hash(block.hash),"rejected",reason)
    reason != "time-too-new" && penalize!(node,peer,setting(node,"BAN",2))
end
function validate_block(node,block,parent)
    block.height != height(parent)+1 && return ("bad-height",nothing,nothing)
    block.difficulty != difficulty(node,parent) && return ("bad-difficulty",nothing,nothing)
    block.timestamp <= median_time(parent) && return ("time-too-old",nothing,nothing)
    block.timestamp > node.now+setting(node,"DRIFT") && return ("time-too-new",nothing,nothing)
    utxo = copy(parent.utxo)
    spent = Set{Reference}()
    fees = Int[]
    for position in 2:length(block.transactions)
        tx = block.transactions[position]
        reason,fee = check_transaction(tx,utxo,spent,block.height,node.owners,setting(node,"MATURITY"))
        !isnothing(reason) && return ("$reason tx $position",nothing,nothing)
        union!(spent,tx.inputs)
        apply_transaction!(utxo,tx,block.height)
        push!(fees,fee)
    end
    tx = block.transactions[1]
    any(!haskey(node.owners,a) || v == 0 for (a,v) in tx.outputs) && return (
        "bad-output tx 1",
        nothing,
        nothing
    )
    output_total(tx) > reward(node,block.height)+sum(fees;init=0) && return ("bad-coinbase",nothing,nothing)
    apply_transaction!(utxo,tx,block.height)
    nothing,utxo,fees
end
function connect_block!(node,kind,block,peer)
    parent = node.records[block.previous]
    reason,utxo,fees = validate_block(node,block,parent)
    if !isnothing(reason)
        reject_block!(node,kind,block,peer,reason)
        return
    end
    record = BlockRecord(block,parent,utxo,fees,peer.name)
    node.records[block.hash] = record
    peer.blocks += 1
    log!(node,kind,peer.name,block.height,short_hash(block.hash),"accepted","work",record.cumulative_work)
    record.cumulative_work > node.tip.cumulative_work && switch_tip!(node,record)
end
function resolve_orphans!(node,start)
    queue = [start]
    while !isempty(queue)
        parent = popfirst!(queue)
        children = filter(item->item[1].previous == parent,node.orphans)
        for (block,peer) in children
            filter!(item->item[1].hash != block.hash,node.orphans)
            if parent in node.rejected
                reject_block!(node,"UNORPHAN",block,peer,"bad-parent")
            else
                connect_block!(node,"UNORPHAN",block,peer)
            end
            push!(queue,block.hash)
        end
    end
end
function receive_block!(node,peer,block)
    if haskey(
        node.records,
        block.hash
    ) || any(item[1].hash == block.hash for item in node.orphans) || block.hash in node.rejected
        log!(node,"BLOCK",peer.name,block.height,short_hash(block.hash),"rejected","duplicate")
        peer.rejected_blocks += 1
        tally!(node,"block","duplicate")
        return
    end
    reason = context_free_error(block,setting(node,"MAXBLOCK"))
    isnothing(reason) && block.previous in node.rejected && (reason = "bad-parent")
    if !isnothing(reason)
        reject_block!(node,"BLOCK",block,peer,reason)
        resolve_orphans!(node,block.hash)
    elseif !haskey(node.records,block.previous)
        push!(node.orphans,(block,peer))
        peer.orphans += 1
        log!(
            node,
            "BLOCK",
            peer.name,
            block.height,
            short_hash(block.hash),
            "orphan",
            "parent",
            short_hash(block.previous)
        )
        if length(node.orphans) > setting(node,"ORPHANS")
            evicted = popfirst!(node.orphans)
            log!(node,"EVICT",short_hash(evicted[1].hash),"orphan-limit")
        end
    else
        connect_block!(node,"BLOCK",block,peer)
        resolve_orphans!(node,block.hash)
    end
end
function status!(node,txid)
    prefix = ("STATUS",short_hash(txid))
    if haskey(node.confirmed,txid)
        h = node.confirmed[txid]
        log!(node,prefix...,"confirmed",h,"confirmations",next_height(node)-h)
        return
    end
    ranked = priority_order(node)
    index = findfirst(entry->entry.transaction.txid == txid,ranked)
    if !isnothing(index)
        log!(node,prefix...,"mempool","rank",index,"of",length(ranked))
    elseif haskey(node.drops,txid)
        log!(node,prefix...,"dropped",node.drops[txid])
    elseif any(tx.txid == txid for record in values(node.records) for tx in record.block.transactions)
        log!(node,prefix...,"stale")
    else
        log!(node,prefix...,"unknown")
    end
end
function print_state!(node)
    ranked = priority_order(node)
    log!(
        node,
        "PRINT",
        "height",
        height(node.tip),
        "tip",
        short_hash(node.tip.block.hash),
        "work",
        node.tip.cumulative_work,
        "bits",
        difficulty(node),
        "reward",
        reward(node,next_height(node)),
        "mempool",
        length(ranked),
        "size",
        sum((e.transaction.size for e in ranked);init=0),
        "orphans",
        length(node.orphans)
    )
    for (rank,entry) in enumerate(ranked)
        log!(
            node,
            "MEMPOOL",
            rank,
            short_hash(entry.transaction.txid),
            "fee",
            entry.fee,
            "size",
            entry.transaction.size
        )
    end
    for wallet in node.wallets
        log!(node,"BALANCE",wallet.name,node_balance(node,wallet.address))
    end
end
function process!(node,fields,texts)
    node.now = parse(Int,fields[1])
    for entry in copy(node.mempool)
        node.now-entry.arrival >= setting(node,"EXPIRY") && drop!(node,entry,"expired")
    end
    kind = fields[2]
    if kind == "PAY"
        pay!(node,fields)
    elseif kind == "BUMP"
        bump!(node,fields[3],parse(Int,fields[4]))
    elseif kind == "MINE"
        mine!(node,node.named[fields[3]])
    elseif kind == "STATUS"
        status!(node,fields[3])
    elseif kind == "PRINT"
        print_state!(node)
    else
        peer = get!(()->Peer(fields[3]),node.peers,fields[3])
        if peer.score >= setting(node,"BAN")
            peer.ignored += 1
            log!(node,"IGNORE",peer.name,kind)
        elseif kind == "TX"
            receive_transaction!(node,peer,parse_transaction(fields[4]))
        else
            receive_block!(node,peer,parse_block_event(fields,texts))
        end
    end
end
miner_address(record) = record.block.transactions[1].outputs[1][1]
function chain_lines(node)
    tip = node.tip
    lines = ["TIP $(height(tip)) $(tip.block.hash) work $(tip.cumulative_work) stored $(length(node.records)) orphans $(length(node.orphans))"]
    for record in node.main_chain
        b = record.block
        miner = b.height == 0 ? "-" : node.owners[miner_address(record)].name
        push!(
            lines,
            "BLOCK $(b.height) $(b.hash) prev $(short_hash(b.previous)) time $(b.timestamp) bits $(b.difficulty) nonce $(b.nonce) txs $(length(b.transactions)) size $(block_size(b)) fees $(record.fees) miner $miner source $(record.source) work $(record.cumulative_work)"
        )
        for (k,tx) in enumerate(b.transactions)
            if is_coinbase(tx)
                category = b.height == 0 ? "genesis" : "coinbase"
                push!(lines,"TX $k $(tx.txid) $category out $(length(tx.outputs)) amount $(output_total(tx))")
            else
                push!(
                    lines,
                    "TX $k $(tx.txid) payment in $(length(tx.inputs)) out $(length(tx.outputs)) size $(tx.size) fee $(record.transaction_fees[k-1])"
                )
            end
        end
    end
    main_hashes = Set(r.block.hash for r in node.main_chain)
    stale = sort(
        [r for r in values(node.records) if !(r.block.hash in main_hashes)],
        by=r->(height(r),r.block.hash)
    )
    for r in stale
        push!(
            lines,
            "STALE $(height(r)) $(r.block.hash) prev $(short_hash(r.block.previous)) source $(r.source) work $(r.cumulative_work)"
        )
    end
    for (b,p) in node.orphans
        push!(lines,"ORPHAN $(b.height) $(b.hash) prev $(short_hash(b.previous)) source $(p.name)")
    end
    for (t,f,d,c,old,new) in node.reorganizations
        push!(
            lines,
            "REORG $t fork $f disconnected $d connected $c old $(short_hash(old)) new $(short_hash(new))"
        )
    end
    mined = node.main_chain[2:end]
    for wallet in node.wallets
        own = filter(r->miner_address(r) == wallet.address,mined)
        isempty(own) && continue
        push!(
            lines,
            "MINER $(wallet.name) blocks $(length(own)) coinbase $(sum(output_total(r.block.transactions[1]) for r in own)) fees $(sum(r.fees for r in own))"
        )
    end
    i = 1
    while i <= length(mined)
        j = i
        while j < length(mined) && mined[j+1].block.difficulty == mined[i].block.difficulty
            j += 1
        end
        push!(
            lines,
            "BITS $(mined[i].block.difficulty) heights $(height(mined[i]))-$(height(mined[j])) blocks $(j-i+1)"
        )
        i = j+1
    end
    for name in sort(collect(keys(node.peers)))
        p = node.peers[name]
        state = p.score >= setting(node,"BAN") ? "banned" : "ok"
        push!(
            lines,
            "PEER $name blocks $(p.blocks) rejected $(p.rejected_blocks) orphans $(p.orphans) txs $(p.txs) rejected $(p.rejected_txs) ignored $(p.ignored) score $(p.score) $state"
        )
    end
    for (rank,e) in enumerate(priority_order(node))
        push!(
            lines,
            "MEMPOOL $rank $(e.transaction.txid) fee $(e.fee) size $(e.transaction.size) time $(e.arrival)"
        )
    end
    for (category,reason) in sort(collect(keys(node.rejections)))
        push!(lines,"REJECT $category $reason $(node.rejections[(category,reason)])")
    end
    genesis = output_total(node.main_chain[1].block.transactions[1])
    rewards = sum((reward(node,height(r)) for r in mined);init=0)
    fees = sum((r.fees for r in mined);init=0)
    minted = sum((output_total(r.block.transactions[1]) for r in mined);init=0)
    push!(
        lines,
        "SUPPLY genesis $genesis rewards $rewards fees $fees burned $(rewards+fees-minted) utxo $(sum(c.amount for c in values(tip.utxo)))"
    )
    lines
end
function balance_lines(node)
    locked = locked_references(node)
    lines = ["wallet,address,balance,immature,locked,incoming,utxos"]
    for w in node.wallets
        coins = [(ref,c) for (ref,c) in node.tip.utxo if c.address == w.address]
        balance = sum((c.amount for (_,c) in coins);init=0)
        immature = sum((c.amount for (_,c) in coins if !mature(node,c));init=0)
        amount_locked = sum((c.amount for (ref,c) in coins if ref in locked);init=0)
        incoming = sum((v for e in node.mempool for (a,v) in e.transaction.outputs if a == w.address);init=0)
        push!(lines,join((w.name,w.address,balance,immature,amount_locked,incoming,length(coins)),','))
    end
    lines
end
coin_category(c) = c.height == 0 ? "genesis" : c.coinbase ? "coinbase" : "payment"
function utxo_lines(node)
    locked = locked_references(node)
    lines = String[]
    for ref in sort(collect(keys(node.tip.utxo)))
        c = node.tip.utxo[ref]
        state = !mature(node,c) ? "immature" : ref in locked ? "locked" : "free"
        push!(
            lines,
            "$(ref[1]):$(ref[2]) $(node.owners[c.address].name) $(c.amount) height $(c.height) $(coin_category(c)) $state"
        )
    end
    root = merkle_root(digest.(lines))
    push!(lines,"TOTAL $(length(node.tip.utxo)) $(sum(c.amount for c in values(node.tip.utxo)))","ROOT $root")
    lines
end
function history_lines(node)
    confirmed = Dict(tx.txid=>tx for r in node.main_chain for tx in r.block.transactions)
    lines = String[]
    for w in node.wallets
        push!(lines,"WALLET $(w.name) $(w.address)")
        count,spent_total,received_total,balance,pending = 0,0,0,0,0
        for r in node.main_chain, tx in r.block.transactions
            inputs = [confirmed[id].outputs[index+1] for (id,index) in tx.inputs]
            involved = any(a == w.address for (a,_) in inputs) || any(a == w.address for (a,_) in tx.outputs)
            involved || continue
            spent = sum((v for (a,v) in inputs if a == w.address);init=0)
            received = sum((v for (a,v) in tx.outputs if a == w.address);init=0)
            count += 1
            spent_total += spent
            received_total += received
            balance += received-spent
            category = is_coinbase(tx) ? (height(r) == 0 ? "genesis" : "coinbase") : "payment"
            push!(
                lines,
                "$(height(r)) $(short_hash(tx.txid)) $category spent $spent received $received net $(signed(received-spent)) balance $balance"
            )
        end
        for e in priority_order(node)
            tx = e.transaction
            spent = sum((node.tip.utxo[ref].amount for ref in tx.inputs if node.tip.utxo[ref].address == w.address);init=0)
            received = sum((v for (a,v) in tx.outputs if a == w.address);init=0)
            if spent != 0 || received != 0
                pending += 1
                push!(
                    lines,
                    "pending $(short_hash(tx.txid)) spent $spent received $received net $(signed(received-spent))"
                )
            end
        end
        push!(
            lines,
            "END $(w.name) txs $count spent $spent_total received $received_total balance $balance pending $pending"
        )
    end
    lines
end
function main()
    params = Dict{String,Vector{String}}()
    for line in readlines("input/params.txt")
        fields = String.(split(line))
        params[fields[1]] = fields[2:end]
    end
    node = Node(params,read_wallets("input/wallets.txt"))
    lines = readlines("input/events.txt")
    position = 1
    while position <= length(lines)
        fields = String.(split(lines[position]))
        count = fields[2] == "BLOCK" ? parse(Int,fields[10]) : 0
        process!(node,fields,lines[(position+1):(position+count)])
        position += count+1
    end
    mkpath("output")
    for (name,contents) in (
        ("log.txt",node.log),
        ("chain.txt",chain_lines(node)),
        ("balances.csv",balance_lines(node)),
        ("utxo.txt",utxo_lines(node)),
        ("history.txt",history_lines(node))
    )
        open(joinpath("output",name),"w") do io
            for line in contents
                println(io,line)
            end
        end
    end
end
main()
