local Solver = require("wdp_solver")
local Fraction = require("report").Fraction
local Payments = {}

function Payments.vcg(items, bids, optimal, bidders)
    local result = {}
    for i = 1, #bidders do
        local value, won, others = 0, false, {}
        for _, bid in ipairs(optimal.winning) do if bid.bidder == i then value, won = value + bid.amount, true end end
        if won then
            for _, bid in ipairs(bids) do if bid.bidder ~= i then others[#others + 1] = bid end end
            local alternative = Solver.solve(items, others)
            result[i] = {payment = alternative.welfare - (optimal.welfare - value), alternative = alternative}
        end
    end
    return result
end

local function reserve_of(mask, items)
    local reserve = 0
    for _, item in ipairs(items) do if item.bit & mask ~= 0 then reserve = reserve + item.reserve end end
    return reserve
end

function Payments.critical(order, winning, items)
    local result = {}
    for _, bid in ipairs(winning) do
        local others, rival = {}, nil
        for _, other in ipairs(order) do if other.number ~= bid.number then others[#others + 1] = other end end
        for _, other in ipairs(Solver.greedy_select(others)) do
            if bid.bundle & other.bundle ~= 0 or (bid.xor and bid.bidder == other.bidder) then rival = other; break end
        end
        local payment = reserve_of(bid.bundle, items)
        if rival then
            local threshold = rival.amount * rival.amount * bid.size
            local function earlier(amount)
                local value = amount * amount * rival.size
                return value > threshold or (value == threshold and bid.number < rival.number)
            end
            local low, high = 1, 1
            while not earlier(high) do high = high * 2 end
            while low < high do
                local middle = (low + high) // 2
                if earlier(middle) then high = middle else low = middle + 1 end
            end
            payment = math.max(payment, low)
        end
        result[bid.number] = {payment = payment, rival = rival}
    end
    return result
end

function Payments.coalitions(items, bids, bidders)
    local result = {}
    local function enumerate(size, first, mask, members)
        if size == 0 then
            local selected, names = {}, {}
            for _, bid in ipairs(bids) do if mask & (1 << (bid.bidder - 1)) ~= 0 then selected[#selected + 1] = bid end end
            for i, member in ipairs(members) do names[i] = member end
            local allocation = Solver.solve(items, selected)
            result[#result + 1] = {members = names, mask = mask, welfare = allocation.welfare, numbers = allocation.numbers}
            return
        end
        for i = first, #bidders - size + 1 do
            members[#members + 1] = i
            enumerate(size - 1, i + 1, mask | (1 << (i - 1)), members)
            members[#members] = nil
        end
    end
    for size = 0, #bidders do enumerate(size, 1, 0, {}) end
    return result
end

function Payments.blocking(coalitions, seller, utilities)
    local blocking, minimal = {}, {}
    for _, coalition in ipairs(coalitions) do
        local payoff = seller
        for _, i in ipairs(coalition.members) do payoff = payoff + utilities[i] end
        if coalition.welfare > payoff then
            local record, is_minimal = {coalition = coalition, payoff = payoff, deficit = coalition.welfare - payoff}, true
            for _, previous in ipairs(blocking) do
                if previous.coalition.mask & coalition.mask == previous.coalition.mask then is_minimal = false; break end
            end
            if is_minimal then minimal[#minimal + 1] = record end
            blocking[#blocking + 1] = record
        end
    end
    return blocking, minimal
end

function Payments.gsp_price(ranking, rank)
    return ranking[rank + 1] and ranking[rank + 1].bid or 0
end

function Payments.slot_vcg(ranking, rates, rank)
    local payment = Fraction.new(0)
    for following = rank + 1, math.min(#ranking, #rates + 1) do
        payment = payment + ranking[following].value * (rates[following - 1] - (rates[following] or Fraction.new(0)))
    end
    return payment
end

return Payments
