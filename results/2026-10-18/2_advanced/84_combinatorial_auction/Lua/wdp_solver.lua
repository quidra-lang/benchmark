local Fraction = require("report").Fraction
local Solver = {}

function Solver.lex_less(a, b)
    for i = 1, math.min(#a, #b) do if a[i] ~= b[i] then return a[i] < b[i] end end
    return #a < #b
end

function Solver.shares(items, bids, decided)
    local result, bound = {}, Fraction.new(0)
    for _, item in ipairs(items) do
        if item.bit & (decided or 0) == 0 then
            local share, source = Fraction.new(item.reserve), nil
            for _, bid in ipairs(bids) do
                if bid.bundle & item.bit ~= 0 then
                    local candidate = Fraction.new(bid.amount, bid.size)
                    if share < candidate then share, source = candidate, bid.number end
                end
            end
            result[#result + 1], bound = {item = item, share = share, source = source}, bound + share
        end
    end
    return result, bound
end

function Solver.solve(items, bids)
    local ordered, all, by_number = {}, 0, {}
    for _, item in ipairs(items) do all = all | item.bit end
    for _, bid in ipairs(bids) do ordered[#ordered + 1], by_number[bid.number] = bid, bid end
    table.sort(ordered, function(a, b) return a.number < b.number end)
    local shares, bound = Solver.shares(items, ordered, 0)
    local result = {nodes = 0, pruned = 0, leaves = 0, numbers = {}, improvements = {}, shares = shares, bound = bound}
    local function visit(decided, used, welfare, chosen)
        result.nodes = result.nodes + 1
        if decided == all then
            result.leaves = result.leaves + 1
            local numbers = {}
            for i, bid in ipairs(chosen) do numbers[i] = bid.number end
            table.sort(numbers)
            if result.welfare == nil or welfare > result.welfare or (welfare == result.welfare and Solver.lex_less(numbers, result.numbers)) then
                result.welfare, result.numbers = welfare, numbers
                result.improvements[#result.improvements + 1] = {nodes = result.nodes, welfare = welfare, numbers = numbers}
            end
            return
        end
        local available, first = {}, nil
        for _, bid in ipairs(ordered) do
            if bid.bundle & decided == 0 and (not bid.xor or used & (1 << (bid.bidder - 1)) == 0) then available[#available + 1] = bid end
        end
        local _, remaining = Solver.shares(items, available, decided)
        if result.welfare ~= nil and remaining + welfare < result.welfare then result.pruned = result.pruned + 1; return end
        for _, item in ipairs(items) do if item.bit & decided == 0 then first = item; break end end
        for _, bid in ipairs(available) do
            if bid.bundle & first.bit ~= 0 then
                chosen[#chosen + 1] = bid
                visit(decided | bid.bundle, bid.xor and used | (1 << (bid.bidder - 1)) or used, welfare + bid.amount, chosen)
                chosen[#chosen] = nil
            end
        end
        visit(decided | first.bit, used, welfare + first.reserve, chosen)
    end
    visit(0, 0, 0, {})
    result.winning = {}
    for _, number in ipairs(result.numbers) do result.winning[#result.winning + 1] = by_number[number] end
    return result
end

function Solver.greedy_order(bids)
    local result = {}
    for i, bid in ipairs(bids) do result[i] = bid end
    table.sort(result, function(a, b)
        local left, right = a.amount * a.amount * b.size, b.amount * b.amount * a.size
        if left ~= right then return left > right end
        return a.number < b.number
    end)
    return result
end

function Solver.greedy_select(bids)
    local occupied, used, chosen = 0, 0, {}
    for _, bid in ipairs(bids) do
        local bit = 1 << (bid.bidder - 1)
        if bid.bundle & occupied == 0 and (not bid.xor or used & bit == 0) then
            chosen[#chosen + 1], occupied = bid, occupied | bid.bundle
            if bid.xor then used = used | bit end
        end
    end
    return chosen
end

return Solver
