struct Block
    height::Int
    previous::String
    merkle::String
    timestamp::Int
    difficulty::Int
    nonce::Int
    transactions::Vector{Transaction}
    hash::String
end
header_text(h,p,m,t,d,n) = "$h|$p|$m|$t|$d|$n"
Block(h,p,m,t,d,n,txs) = Block(h,p,m,t,d,n,txs,digest(header_text(h,p,m,t,d,n)))
block_size(block) = sum((tx.size for tx in block.transactions[2:end]); init=0)
meets_difficulty(hash,difficulty) = startswith(hash, repeat("0",difficulty))
function parse_block_event(fields,texts)
    Block(
        parse(Int,fields[4]),
        fields[5],
        fields[6],
        parse(Int,fields[7]),
        parse(Int,fields[8]),
        parse(Int,fields[9]),
        parse_transaction.(texts)
    )
end
function mine_block(height, previous, txs, timestamp, difficulty)
    root = merkle_root([tx.txid for tx in txs])
    nonce = 0
    while !meets_difficulty(digest(header_text(height,previous,root,timestamp,difficulty,nonce)),difficulty)
        nonce += 1
    end
    Block(height,previous,root,timestamp,difficulty,nonce,txs)
end
function context_free_error(block,max_size)
    !meets_difficulty(block.hash,block.difficulty) && return "bad-pow"
    merkle_root([tx.txid for tx in block.transactions]) != block.merkle && return "bad-merkle"
    first = block.transactions[1]
    (!is_coinbase(first) || first.coinbase_height != block.height || any(
        is_coinbase,
        block.transactions[2:end]
    )) && return "bad-structure"
    block_size(block) > max_size && return "too-large"
    nothing
end
