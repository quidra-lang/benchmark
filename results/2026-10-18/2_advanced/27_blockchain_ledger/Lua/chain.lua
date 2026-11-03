local M = {}
function M.new(block, parent, utxo, fees, source)
    local total = 0
    for _, fee in ipairs(fees) do
        total = total + fee
    end
    local work = 1
    if parent then
        local added = 1
        for _ = 1, block.difficulty do
            added = added * 16
        end
        work = parent.cumulative_work + added
    end
    return {block = block, parent = parent, utxo = utxo, transaction_fees = fees, fees = total, source = source, height = block.height, hash = block.hash, cumulative_work = work}
end
function M.reward(height, initial, interval)
    local amount = initial
    for _ = 1, height // interval do
        amount = amount // 2
    end
    return amount
end
function M.ancestor(record, height)
    while record.height > height do
        record = record.parent
    end
    return record
end
function M.chain_to(record)
    local reverse, records = {}, {}
    while record do
        reverse[#reverse + 1], record = record, record.parent
    end
    for i = #reverse, 1, -1 do
        records[#records + 1] = reverse[i]
    end
    return records
end
function M.fork_point(first, second)
    local height = math.min(first.height, second.height)
    first, second = M.ancestor(first, height), M.ancestor(second, height)
    while first ~= second do
        first, second = first.parent, second.parent
    end
    return first
end
function M.median_time(record)
    local times = {}
    while record and #times < 3 do
        times[#times + 1], record = record.block.timestamp, record.parent
    end
    table.sort(times)
    return times[(#times - 1) // 2 + 1]
end
function M.required_difficulty(parent, initial, interval, target)
    local height, difficulty = parent.height + 1, parent.block.difficulty
    if height == 1 then
        return initial
    end
    if height % interval ~= 0 then
        return difficulty
    end
    local span = parent.block.timestamp - M.ancestor(parent, height - interval).block.timestamp
    local expected = target * (interval - 1)
    if 2 * span < expected then
        return math.min(difficulty + 1, 2)
    end
    if span > 2 * expected then
        return math.max(difficulty - 1, 0)
    end
    return difficulty
end
return M
