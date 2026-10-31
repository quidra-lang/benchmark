local Auctions = {}

function Auctions.size(mask)
    local count = 0
    while mask ~= 0 do mask = mask & (mask - 1); count = count + 1 end
    return count
end

function Auctions.candidates(bids, xor)
    local result = {}
    for number = 1, (1 << #bids) - 1 do
        if not xor or Auctions.size(number) == 1 then
            local bundle, value, valid = 0, 0, true
            for i, bid in ipairs(bids) do
                if number & (1 << (i - 1)) ~= 0 then
                    if bundle & bid.bundle ~= 0 then valid = false; break end
                    bundle, value = bundle | bid.bundle, value + bid.amount
                end
            end
            if valid then result[#result + 1] = {number = number, bundle = bundle, value = value} end
        end
    end
    return result
end

function Auctions.value_of(candidates, mask)
    local value = 0
    for _, candidate in ipairs(candidates) do
        if candidate.bundle & mask == candidate.bundle then value = math.max(value, candidate.value) end
    end
    return value
end

function Auctions.english(participants, reserve, increment)
    local price, steps, remaining, winner, paid = reserve, 0, {}, nil, 0
    for i, bidder in ipairs(participants) do if bidder.value >= price then remaining[#remaining + 1] = i end end
    while #remaining >= 2 do
        local previous = remaining
        price, steps, remaining = price + increment, steps + 1, {}
        for i, bidder in ipairs(participants) do if bidder.value >= price then remaining[#remaining + 1] = i end end
        if #remaining == 0 then winner, paid = previous[1], price - increment; break end
    end
    if not winner and #remaining > 0 then winner, paid = remaining[1], price end
    local drops = {}
    for i, bidder in ipairs(participants) do
        local drop = bidder.value < reserve and reserve or reserve + ((bidder.value - reserve) // increment + 1) * increment
        drops[i] = drop <= price and drop or false
    end
    return {winner = winner, price = paid, steps = steps, drops = drops}
end

function Auctions.dutch(participants, reserve, start, decrement)
    local price, steps = start, 0
    while price >= reserve do
        local winner
        for i, bidder in ipairs(participants) do
            if bidder.bid >= price and (not winner or bidder.bid > participants[winner].bid) then winner = i end
        end
        if winner then return {winner = winner, price = price, steps = steps} end
        price, steps = price - decrement, steps + 1
    end
    return {price = 0, steps = steps}
end

return Auctions
