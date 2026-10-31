local Input = {}

function Input.records(name)
    local records = {}
    for line in io.lines("input/" .. name) do
        local fields = {}
        for value in line:gmatch("%S+") do fields[#fields + 1] = value end
        records[#records + 1] = fields
    end
    return records
end

function Input.bid(number, bidder, mask, size, amount, xor)
    return {number = number, bidder = bidder, bundle = mask, size = size, amount = amount, xor = xor}
end

function Input.read()
    local items, by_name, auctions, groups, parameters = {}, {}, {}, {}, {}
    for _, f in ipairs(Input.records("items.txt")) do
        local item = {name = f[1], reserve = tonumber(f[2]), bit = 1 << #items}
        items[#items + 1], by_name[item.name] = item, item
    end
    local auction
    for _, f in ipairs(Input.records("bids.txt")) do
        if f[1] == "auction" then
            auction = {name = f[2], items = {}, lines = {}, mask = 0}
            for i = 3, #f do
                local item = by_name[f[i]]
                auction.items[#auction.items + 1] = item
                auction.mask = auction.mask | item.bit
            end
            auctions[auction.name] = auction
        else
            local bids = {}
            for i = 4, #f do bids[#bids + 1] = f[i] end
            auction.lines[#auction.lines + 1] = {name = f[2], language = f[3], bids = bids}
        end
    end
    local group
    for _, f in ipairs(Input.records("single_item.txt")) do
        if f[1] == "lot" or f[1] == "slots" then
            group = {kind = f[1], name = f[2], arguments = {}, participants = {}}
            for i = 3, #f do group.arguments[#group.arguments + 1] = f[i] end
            groups[#groups + 1] = group
        else
            group.participants[#group.participants + 1] = {name = f[2], value = tonumber(f[3]),
                bid = tonumber(f[4]), index = #group.participants + 1}
        end
    end
    for _, f in ipairs(Input.records("params.txt")) do
        if f[1] == "run" then
            parameters.run = {}
            for i = 2, #f do parameters.run[#parameters.run + 1] = f[i] end
        else parameters[f[1]] = tonumber(f[2]) end
    end
    return items, by_name, auctions, groups, parameters
end

return Input
