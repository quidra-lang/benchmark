struct BlockRecord
    block::Block
    parent::Union{Nothing,BlockRecord}
    utxo::Dict{Reference,Coin}
    transaction_fees::Vector{Int}
    fees::Int
    source::String
    cumulative_work::Int
end
BlockRecord(block,parent,utxo,fees,source) = BlockRecord(
    block,
    parent,
    utxo,
    fees,
    sum(fees;init=0),
    source,
    isnothing(parent) ? 1 : parent.cumulative_work+16^block.difficulty
)
function block_reward(height,initial,interval)
    for _ in 1:(height ÷ interval)
        initial ÷= 2
    end
    initial
end
function ancestor(record,height)
    while record.block.height > height
        record = record.parent
    end
    record
end
function chain_to(record)
    records = BlockRecord[]
    while !isnothing(record)
        push!(records,record)
        record = record.parent
    end
    reverse!(records)
end
function fork_point(first,second)
    h = min(first.block.height,second.block.height)
    first,second = ancestor(first,h),ancestor(second,h)
    while first !== second
        first,second = first.parent,second.parent
    end
    first
end
function median_time(record)
    times = Int[]
    while !isnothing(record) && length(times) < 3
        push!(times,record.block.timestamp)
        record = record.parent
    end
    sort!(times)[(length(times)+1)÷2]
end
function required_difficulty(parent,initial,interval,target)
    height = parent.block.height+1
    height == 1 && return initial
    difficulty = parent.block.difficulty
    height % interval != 0 && return difficulty
    span = parent.block.timestamp-ancestor(parent,height-interval).block.timestamp
    expected = target*(interval-1)
    2span < expected ? min(difficulty+1,2) : span > 2expected ? max(difficulty-1,0) : difficulty
end
