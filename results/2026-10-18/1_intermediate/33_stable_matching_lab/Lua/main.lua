local function fail(message) error("ERROR " .. message, 0) end
local function copy(values)
    local result = {}
    for i, value in ipairs(values) do result[i] = value end
    return result
end
local function filled(count, value)
    local result = {}
    for i = 1, count do result[i] = value end
    return result
end
local function slice(values, first, last)
    local result = {}
    for i = first, last or #values do result[#result + 1] = values[i] end
    return result
end
local function indexOf(values, value)
    for i, item in ipairs(values) do if item == value then return i end end
    return 0
end
local function sameValues(first, second)
    if #first ~= #second then return false end
    for i, value in ipairs(first) do if value ~= second[i] then return false end end
    return true
end
local function splitPair(text, separator)
    local position = text:find(separator, 1, true)
    return text:sub(1, position - 1), text:sub(position + 1)
end
local function listText(values) return #values == 0 and "-" or table.concat(values, " ") end
local function rankOf(preference, partner)
    local position = indexOf(preference, partner)
    return position == 0 and #preference + 1 or position
end

local Market = {}
Market.__index = Market
function Market.new(name, kind, agents, proposerCount, houses)
    local preferences = {}
    for a = 1, #agents do preferences[a] = {} end
    return setmetatable({name = name, kind = kind, agents = agents, count = #agents,
        proposerCount = proposerCount or 0, houses = houses or {}, preferences = preferences,
        capacities = filled(#agents, 1), current = false, source = "-"}, Market)
end
function Market:agent(name)
    local agent = indexOf(self.agents, name)
    if agent == 0 then fail("UNKNOWN AGENT " .. name) end
    return agent
end
function Market:proposer(name)
    local agent = self:agent(name)
    if agent > self.proposerCount then fail("NOT PROPOSER " .. name) end
    return agent
end
function Market:receiver(name)
    local agent = self:agent(name)
    if agent <= self.proposerCount then fail("NOT RECEIVER " .. name) end
    return agent
end
function Market:choice(agent, name)
    local choice = indexOf(self.kind == "HOUSES" and self.houses or self.agents, name)
    local valid = choice > 0
    if self.kind == "MARKET" then
        valid = valid and ((agent <= self.proposerCount) ~= (choice <= self.proposerCount))
    elseif self.kind == "ROOMS" then
        valid = valid and choice ~= agent
    end
    if not valid then fail("BAD CHOICE " .. name) end
    return choice
end
function Market:clearMatching() self.current, self.source = false, "-" end
function Market:setMatching(partners, source) self.current, self.source = copy(partners), source end
function Market:partner(agent) return agent == 0 and "*" or self.agents[agent] end
function Market:pairs(partners)
    local parts = {}
    for p = 1, self.proposerCount do parts[p] = self.agents[p] .. "-" .. self:partner(partners[p]) end
    return table.concat(parts, " ")
end
function Market:allocation(allocation)
    local parts = {}
    for a, house in ipairs(allocation) do
        parts[a] = self.agents[a] .. "-" .. (house == 0 and "*" or self.houses[house])
    end
    return table.concat(parts, " ")
end
function Market:effective(agent)
    local preference = self.preferences[agent]
    local own = indexOf(preference, agent)
    if own > 0 then return slice(preference, 1, own) end
    local result = copy(preference)
    result[#result + 1] = agent
    return result
end

local function acceptable(preferences, a, b)
    return indexOf(preferences[a], b) > 0 and indexOf(preferences[b], a) > 0
end
local function residents(market, partners, receiver)
    local result = {}
    for p = 1, market.proposerCount do if partners[p] == receiver then result[#result + 1] = p end end
    return result
end
local function deferred(market, reverse, verbose, preferences)
    local lists = preferences or market.preferences
    local positions, counts = filled(market.count, 1), filled(market.count, 0)
    local holding, queued, queue = {}, filled(market.count, false), {}
    for a = 1, market.count do holding[a] = {} end
    local function enqueue(agent)
        if not queued[agent] and counts[agent] < market.capacities[agent] and positions[agent] <= #lists[agent] then
            queue[#queue + 1], queued[agent] = agent, true
        end
    end
    local first = reverse and market.proposerCount + 1 or 1
    local last = reverse and market.count or market.proposerCount
    for a = first, last do enqueue(a) end
    local proposals, log, head = 0, {}, 1
    while head <= #queue do
        local x = queue[head]
        head, queued[x] = head + 1, false
        local y = lists[x][positions[x]]
        positions[x], proposals = positions[x] + 1, proposals + 1
        local action = "REJECT"
        if indexOf(lists[y], x) > 0 then
            if #holding[y] < market.capacities[y] then
                holding[y][#holding[y] + 1] = x
                counts[x] = counts[x] + 1
                action = "HOLD"
            else
                local worst = 1
                for i = 2, #holding[y] do
                    if rankOf(lists[y], holding[y][i]) > rankOf(lists[y], holding[y][worst]) then worst = i end
                end
                local rejected = holding[y][worst]
                if rankOf(lists[y], x) < rankOf(lists[y], rejected) then
                    holding[y][worst] = x
                    counts[rejected], counts[x] = counts[rejected] - 1, counts[x] + 1
                    action = "HOLD REJECT " .. market.agents[rejected]
                    enqueue(rejected)
                end
            end
        end
        if verbose then log[#log + 1] = "PROPOSE " .. market.agents[x] .. " " .. market.agents[y] .. " " .. action end
        enqueue(x)
    end
    local partners = filled(market.proposerCount, 0)
    first = reverse and 1 or market.proposerCount + 1
    last = reverse and market.proposerCount or market.count
    for y = first, last do
        for _, x in ipairs(holding[y]) do partners[reverse and y or x] = reverse and x or y end
    end
    return {partners = partners, count = proposals, log = log}
end
local function boston(market, preferences)
    local lists = preferences or market.preferences
    local partners, remaining = filled(market.proposerCount, 0), copy(market.capacities)
    local rounds, applications = 0, 0
    for p = 1, market.proposerCount do rounds = math.max(rounds, #lists[p]) end
    for round = 1, rounds do
        local applied = filled(market.proposerCount, 0)
        for p = 1, market.proposerCount do
            if partners[p] == 0 and round <= #lists[p] then
                applied[p], applications = lists[p][round], applications + 1
            end
        end
        for r = market.proposerCount + 1, market.count do
            for _, p in ipairs(lists[r]) do
                if remaining[r] == 0 then break end
                if applied[p] == r then
                    partners[p], remaining[r] = r, remaining[r] - 1
                end
            end
        end
    end
    return {partners = partners, count = applications}
end
local function checkMatching(market, partners)
    local unacceptable, blocking, lists = {}, {}, market.preferences
    if market.kind == "ROOMS" then
        for a = 1, market.count do
            for b = a + 1, market.count do
                local mutual = acceptable(lists, a, b)
                if partners[a] == b then
                    if not mutual then unacceptable[#unacceptable + 1] = {a, b} end
                elseif mutual and rankOf(lists[a], b) < rankOf(lists[a], partners[a])
                    and rankOf(lists[b], a) < rankOf(lists[b], partners[b]) then
                    blocking[#blocking + 1] = {a, b}
                end
            end
        end
    else
        for p = 1, market.proposerCount do
            if partners[p] > 0 and not acceptable(lists, p, partners[p]) then
                unacceptable[#unacceptable + 1] = {p, partners[p]}
            end
            for r = market.proposerCount + 1, market.count do
                if partners[p] ~= r and acceptable(lists, p, r) and rankOf(lists[p], r) < rankOf(lists[p], partners[p]) then
                    local held, worst = residents(market, partners, r), 0
                    for _, a in ipairs(held) do worst = math.max(worst, rankOf(lists[r], a)) end
                    if #held < market.capacities[r] or rankOf(lists[r], p) < worst then
                        blocking[#blocking + 1] = {p, r}
                    end
                end
            end
        end
    end
    return unacceptable, blocking
end
local function candidateFor(market, partners, origin, via)
    local cost, regret = 0, 0
    for p, r in ipairs(partners) do
        if r > 0 then
            local a, b = rankOf(market.preferences[p], r), rankOf(market.preferences[r], p)
            cost, regret = cost + a + b, math.max(regret, a, b)
        end
    end
    return {partners = partners, origin = origin, via = via, cost = cost, regret = regret}
end
local function exposedRotations(market, partners)
    local owners, successors = filled(market.count, 0), filled(market.proposerCount, 0)
    for p, r in ipairs(partners) do if r > 0 then owners[r] = p end end
    for p, r in ipairs(partners) do
        if r > 0 then
            local preference = market.preferences[p]
            for i = indexOf(preference, r) + 1, #preference do
                local w = preference[i]
                local owner = owners[w]
                if indexOf(market.preferences[w], p) > 0 and (owner == 0
                    or rankOf(market.preferences[w], p) < rankOf(market.preferences[w], owner)) then
                    successors[p] = owner
                    break
                end
            end
        end
    end
    local rotations, covered = {}, filled(market.proposerCount, false)
    for start = 1, market.proposerCount do
        if not covered[start] then
            local path, seen, current = {}, filled(market.proposerCount, false), start
            while current > 0 and not seen[current] do
                seen[current], path[#path + 1] = true, current
                current = successors[current]
            end
            if current == start then
                rotations[#rotations + 1] = path
                for _, p in ipairs(path) do covered[p] = true end
            end
        end
    end
    return rotations
end
local function enumerateStable(market)
    for r = market.proposerCount + 1, market.count do if market.capacities[r] ~= 1 then fail("NOT ONE TO ONE") end end
    local matchings = {candidateFor(market, deferred(market).partners, 0, 0)}
    local rotations, numbers, index = {}, {}, 1
    while index <= #matchings do
        local partners = matchings[index].partners
        for _, rotation in ipairs(exposedRotations(market, partners)) do
            local parts = {}
            for i, p in ipairs(rotation) do parts[i] = market.agents[p] .. "-" .. market.agents[partners[p]] end
            local notation = table.concat(parts, " ")
            if not numbers[notation] then
                rotations[#rotations + 1] = notation
                numbers[notation] = #rotations
            end
            local following = copy(partners)
            for i, p in ipairs(rotation) do following[p] = partners[rotation[i % #rotation + 1]] end
            local duplicate = false
            for _, candidate in ipairs(matchings) do
                if sameValues(candidate.partners, following) then duplicate = true; break end
            end
            if not duplicate then
                if #matchings == 50 then fail("TOO MANY MATCHINGS") end
                matchings[#matchings + 1] = candidateFor(market, following, index, numbers[notation])
            end
        end
        index = index + 1
    end
    return matchings, rotations
end
local function removePair(lists, a, b)
    local position = indexOf(lists[a], b)
    if position > 0 then table.remove(lists[a], position) end
    position = indexOf(lists[b], a)
    if position > 0 then table.remove(lists[b], position) end
end
local function firstEmpty(lists)
    for a, list in ipairs(lists) do if #list == 0 then return a end end
    return 0
end
local function addTable(output, market, lists)
    for a, list in ipairs(lists) do
        local names = {}
        for i, b in ipairs(list) do names[i] = market.agents[b] end
        output[#output + 1] = "TABLE " .. market.agents[a] .. " " .. listText(names)
    end
end
local function roommates(market, verbose)
    local lists = {}
    for a, list in ipairs(market.preferences) do
        if #list < market.count - 1 then fail("INCOMPLETE " .. market.agents[a]) end
        lists[a] = copy(list)
    end
    local held, queue = filled(market.count, 0), {}
    for a = 1, market.count do queue[a] = a end
    local proposals, head, failure, rotations = 0, 1, 0, 0
    local trace = {}
    while head <= #queue do
        local x = queue[head]
        head = head + 1
        local y = lists[x][1]
        proposals = proposals + 1
        if held[y] > 0 then queue[#queue + 1] = held[y] end
        held[y] = x
        local removed = slice(lists[y], indexOf(lists[y], x) + 1)
        for _, w in ipairs(removed) do removePair(lists, y, w) end
        failure = firstEmpty(lists)
        if failure > 0 then break end
    end
    if failure == 0 then
        if verbose then addTable(trace, market, lists) end
        while true do
            local p = 0
            for a, list in ipairs(lists) do if #list > 1 then p = a; break end end
            if p == 0 then break end
            local seen, path = filled(market.count, 0), {}
            while seen[p] == 0 do
                path[#path + 1] = p
                seen[p] = #path
                local q = lists[p][2]
                p = lists[q][#lists[q]]
            end
            local xs, ys, parts = slice(path, seen[p]), {}, {}
            for i, x in ipairs(xs) do
                ys[i] = lists[x][1]
                parts[i] = market.agents[x] .. "-" .. market.agents[ys[i]]
            end
            rotations = rotations + 1
            trace[#trace + 1] = "ROTATION " .. rotations .. " " .. table.concat(parts, " ")
            local removals = {}
            for i, x in ipairs(xs) do
                local u = ys[i % #ys + 1]
                for j = indexOf(lists[u], x) + 1, #lists[u] do removals[#removals + 1] = {u, lists[u][j]} end
            end
            for _, pair in ipairs(removals) do removePair(lists, pair[1], pair[2]) end
            if verbose then addTable(trace, market, lists) end
            failure = firstEmpty(lists)
            if failure > 0 then break end
        end
    end
    local output = {"ROOMMATES " .. market.name .. " proposals=" .. proposals}
    for _, line in ipairs(trace) do output[#output + 1] = line end
    if failure > 0 then output[#output + 1] = "NO STABLE MATCHING " .. market.agents[failure]
    else
        local pairs = {}
        for a, list in ipairs(lists) do
            if a < list[1] then pairs[#pairs + 1] = market.agents[a] .. "-" .. market.agents[list[1]] end
        end
        output[#output + 1] = "MATCHING " .. table.concat(pairs, " ")
    end
    return output
end
local function tradingCycles(market)
    local remaining, allocation = filled(market.count, true), filled(market.count, 0)
    local effective, cycles, left = {}, {}, market.count
    for a = 1, market.count do effective[a] = market:effective(a) end
    while left > 0 do
        local pointers = filled(market.count, 0)
        for a = 1, market.count do
            if remaining[a] then
                for _, h in ipairs(effective[a]) do if remaining[h] then pointers[a] = h; break end end
            end
        end
        local seen, path, current = filled(market.count, 0), {}, indexOf(remaining, true)
        while seen[current] == 0 do
            path[#path + 1] = current
            seen[current] = #path
            current = pointers[current]
        end
        local cycle, parts = slice(path, seen[current]), {}
        for i, a in ipairs(cycle) do
            allocation[a], remaining[a], left = pointers[a], false, left - 1
            parts[i] = market.agents[a] .. ":" .. market.houses[allocation[a]]
        end
        cycles[#cycles + 1] = "CYCLE " .. (#cycles + 1) .. " " .. table.concat(parts, " ")
    end
    local output = {"TTC " .. market.name .. " cycles=" .. #cycles}
    for _, line in ipairs(cycles) do output[#output + 1] = line end
    output[#output + 1] = "ALLOCATION " .. market:allocation(allocation)
    return output
end

local function show(market)
    local output = {}
    if market.kind == "MARKET" then
        output[1] = "SHOW " .. market.name .. " MARKET proposers=" .. market.proposerCount
            .. " receivers=" .. (market.count - market.proposerCount)
    else
        output[1] = "SHOW " .. market.name .. " " .. market.kind .. " agents=" .. market.count
    end
    for a, name in ipairs(market.agents) do
        local prefix = "AGENT " .. name
        if market.kind == "MARKET" then
            prefix = a <= market.proposerCount and "PROPOSER " .. name
                or "RECEIVER " .. name .. " cap=" .. market.capacities[a]
        elseif market.kind == "HOUSES" then prefix = prefix .. " house=" .. market.houses[a] end
        local names = {}
        for i, choice in ipairs(market.preferences[a]) do
            names[i] = market.kind == "HOUSES" and market.houses[choice] or market.agents[choice]
        end
        output[#output + 1] = prefix .. " " .. listText(names)
    end
    if market.kind == "MARKET" then output[#output + 1] = "CURRENT " .. market.source end
    return output
end
local function check(market, words)
    if market.kind == "HOUSES" then fail("WRONG TYPE " .. market.name) end
    local partners = filled(market.kind == "MARKET" and market.proposerCount or market.count, 0)
    local used, counts = filled(market.count, false), filled(market.count, 0)
    for i = 3, #words do
        local first, second = splitPair(words[i], "-")
        if market.kind == "MARKET" then
            local p = market:proposer(first)
            local r = market:receiver(second)
            if used[p] then fail("DUPLICATE AGENT " .. first) end
            if counts[r] + 1 > market.capacities[r] then fail("OVER CAPACITY " .. second) end
            used[p], counts[r], partners[p] = true, counts[r] + 1, r
        else
            local a = market:agent(first)
            local b = market:agent(second)
            if used[a] then fail("DUPLICATE AGENT " .. first) end
            if a == b or used[b] then fail("DUPLICATE AGENT " .. second) end
            used[a], used[b], partners[a], partners[b] = true, true, b, a
        end
    end
    local unacceptable, blocking = checkMatching(market, partners)
    if #unacceptable == 0 and #blocking == 0 then return {"CHECK " .. market.name .. " STABLE"} end
    local output = {"CHECK " .. market.name .. " UNSTABLE unacceptable=" .. #unacceptable .. " blocking=" .. #blocking}
    for _, pair in ipairs(unacceptable) do
        output[#output + 1] = "UNACCEPTABLE " .. market.agents[pair[1]] .. " " .. market.agents[pair[2]]
    end
    for _, pair in ipairs(blocking) do
        output[#output + 1] = "BLOCKING " .. market.agents[pair[1]] .. " " .. market.agents[pair[2]]
    end
    return output
end
local function hospitals(market)
    local a, h = deferred(market).partners, deferred(market, true).partners
    local unmatched, rural = {}, true
    for p = 1, market.proposerCount do
        if a[p] == 0 then unmatched[#unmatched + 1] = market.agents[p] end
        if (a[p] > 0) ~= (h[p] > 0) then rural = false end
    end
    local output = {"HR " .. market.name .. " residents=" .. market.proposerCount .. " hospitals=" .. (market.count - market.proposerCount),
        "RESIDENT-OPTIMAL " .. market:pairs(a), "HOSPITAL-OPTIMAL " .. market:pairs(h), "UNMATCHED " .. listText(unmatched)}
    for r = market.proposerCount + 1, market.count do
        local first, second = residents(market, a, r), residents(market, h, r)
        local same = sameValues(first, second)
        output[#output + 1] = "HOSPITAL " .. market.agents[r] .. " cap=" .. market.capacities[r]
            .. " resident=" .. #first .. " hospital=" .. #second .. " same=" .. (same and "YES" or "NO")
        rural = rural and #first == #second and (#first == market.capacities[r] or same)
    end
    output[#output + 1] = rural and "RURAL HOLDS" or "RURAL FAILS"
    return output
end
local function serial(market, words)
    local order, seen = {}, {}
    for i = 3, #words do
        local a = market:agent(words[i])
        if seen[a] then fail("DUPLICATE AGENT " .. words[i]) end
        seen[a], order[#order + 1] = true, a
    end
    if #order ~= market.count then fail("BAD ORDER") end
    local allocation, remaining, assigned = filled(market.count, 0), filled(market.count, true), 0
    for _, a in ipairs(order) do
        for _, house in ipairs(market.preferences[a]) do
            if remaining[house] then
                allocation[a], remaining[house], assigned = house, false, assigned + 1
                break
            end
        end
    end
    local worse = {}
    for a, house in ipairs(allocation) do
        if house == 0 or indexOf(market:effective(a), house) == 0 then worse[#worse + 1] = market.agents[a] end
    end
    return {"SERIAL " .. market.name .. " assigned=" .. assigned,
        "ALLOCATION " .. market:allocation(allocation), "WORSE " .. listText(worse)}
end
local function manipulate(market, agent)
    local truth = market.preferences[agent]
    local b0, g0 = boston(market).partners[agent], deferred(market).partners[agent]
    local output = {"MANIPULATE " .. market.name .. " " .. market.agents[agent] .. " boston=" .. market:partner(b0)
        .. " gs=" .. market:partner(g0) .. " swaps=" .. math.max(0, #truth - 1)}
    for i = 1, #truth - 1 do
        local preferences = copy(market.preferences)
        preferences[agent] = copy(truth)
        preferences[agent][i], preferences[agent][i + 1] = truth[i + 1], truth[i]
        local b = boston(market, preferences).partners[agent]
        local g = deferred(market, false, false, preferences).partners[agent]
        local swap = i .. " " .. market.agents[truth[i]] .. " " .. market.agents[truth[i + 1]]
        if rankOf(truth, b) < rankOf(truth, b0) then output[#output + 1] = "IMPROVE BOSTON " .. swap .. " result=" .. market:partner(b) end
        if rankOf(truth, g) < rankOf(truth, g0) then output[#output + 1] = "IMPROVE GS " .. swap .. " result=" .. market:partner(g) end
    end
    if #output == 1 then output[#output + 1] = "NO IMPROVEMENT" end
    return output
end
local function rankSummary(ranks)
    local sum, first = 0, 0
    for _, rank in ipairs(ranks) do
        sum = sum + rank
        if rank == 1 then first = first + 1 end
    end
    local average, truncated = "-", "-"
    if #ranks > 0 then
        local a, b = sum, #ranks
        while b ~= 0 do a, b = b, a % b end
        average = string.format("%d/%d", sum // a, #ranks // a)
        local cents = sum * 100 // #ranks
        truncated = string.format("%d.%02d", cents // 100, cents % 100)
    end
    return "sum=" .. sum .. " average=" .. average .. " truncated=" .. truncated .. " first=" .. first
end
local function stats(market)
    if not market.current then fail("NO MATCHING") end
    local proposerRanks, receiverRanks, occupied = {}, {}, filled(market.count, false)
    local hospitalCount = 0
    for p, r in ipairs(market.current) do
        if r > 0 then
            proposerRanks[#proposerRanks + 1] = rankOf(market.preferences[p], r)
            receiverRanks[#receiverRanks + 1] = rankOf(market.preferences[r], p)
            if not occupied[r] then occupied[r], hospitalCount = true, hospitalCount + 1 end
        end
    end
    return {"STATS " .. market.name .. " source=" .. market.source .. " pairs=" .. #proposerRanks,
        "PROPOSERS " .. rankSummary(proposerRanks) .. " unmatched=" .. (market.proposerCount - #proposerRanks),
        "RECEIVERS " .. rankSummary(receiverRanks) .. " unmatched=" .. (market.count - market.proposerCount - hospitalCount)}
end

local markets = {}
local function getMarket(name, kind)
    local market = markets[name]
    if not market then fail("UNKNOWN MARKET " .. name) end
    if kind and market.kind ~= kind then fail("WRONG TYPE " .. name) end
    return market
end
local function newName(name) if markets[name] then fail("DUPLICATE MARKET " .. name) end end
local function distinctAgents(agents)
    local seen = {}
    for _, agent in ipairs(agents) do
        if seen[agent] then fail("DUPLICATE AGENT " .. agent) end
        seen[agent] = true
    end
end
local function execute(line)
    local words = {}
    for word in line:gmatch("%S+") do words[#words + 1] = word end
    local command, name = words[1], words[2]
    if command == "MARKET" then
        newName(name)
        local bar = indexOf(words, "|")
        local agents = slice(words, 3, bar - 1)
        local proposers = #agents
        for i = bar + 1, #words do agents[#agents + 1] = words[i] end
        distinctAgents(agents)
        markets[name] = Market.new(name, "MARKET", agents, proposers)
        return {"MARKET " .. name .. " proposers=" .. proposers .. " receivers=" .. (#agents - proposers)}
    elseif command == "ROOMS" then
        newName(name)
        local agents = slice(words, 3)
        distinctAgents(agents)
        markets[name] = Market.new(name, "ROOMS", agents)
        return {"ROOMS " .. name .. " agents=" .. #agents}
    elseif command == "HOUSES" then
        newName(name)
        local agents, houses = {}, {}
        for i = 3, #words do
            local agent, house = splitPair(words[i], ":")
            if indexOf(agents, agent) > 0 then fail("DUPLICATE AGENT " .. agent) end
            if indexOf(houses, house) > 0 then fail("DUPLICATE HOUSE " .. house) end
            agents[#agents + 1], houses[#houses + 1] = agent, house
        end
        markets[name] = Market.new(name, "HOUSES", agents, 0, houses)
        return {"HOUSES " .. name .. " agents=" .. #agents}
    elseif command == "RANDOM" then
        newName(name)
        local n, seed = tonumber(words[3], 10), tonumber(words[4], 10)
        local agents = {}
        for i = 1, n do agents[i], agents[n + i] = "P" .. i, "R" .. i end
        local market, state = Market.new(name, "MARKET", agents, n), seed
        for a = 1, market.count do
            local preference = {}
            for i = 1, n do preference[i] = a <= n and n + i or i end
            for i = n, 2, -1 do
                state = 48271 * state % 2147483647
                local j = state % i + 1
                preference[i], preference[j] = preference[j], preference[i]
            end
            market.preferences[a] = preference
        end
        markets[name] = market
        return {"RANDOM " .. name .. " n=" .. n .. " seed=" .. seed}
    elseif command == "PREF" then
        local market = getMarket(name)
        local agent, choices = market:agent(words[3]), {}
        for i = 4, #words do
            local choice = market:choice(agent, words[i])
            if indexOf(choices, choice) > 0 then fail("DUPLICATE CHOICE " .. words[i]) end
            choices[#choices + 1] = choice
        end
        market.preferences[agent] = choices
        if market.kind == "MARKET" then market:clearMatching() end
        return {"PREF " .. name .. " " .. words[3] .. " length=" .. #choices}
    elseif command == "CAPACITY" then
        local market = getMarket(name, "MARKET")
        local receiver = market:receiver(words[3])
        local capacity = tonumber(words[4], 10)
        market.capacities[receiver] = capacity
        market:clearMatching()
        return {"CAPACITY " .. name .. " " .. words[3] .. " " .. capacity}
    elseif command == "SHOW" then return show(getMarket(name))
    elseif command == "GS" or command == "GSR" then
        local market = getMarket(name, "MARKET")
        local result = deferred(market, command == "GSR", #words == 3)
        market:setMatching(result.partners, command)
        local output = {command .. " " .. name .. " proposals=" .. result.count}
        for _, proposal in ipairs(result.log) do output[#output + 1] = proposal end
        output[#output + 1] = "MATCHING " .. market:pairs(result.partners)
        return output
    elseif command == "CHECK" then return check(getMarket(name), words)
    elseif command == "LATTICE" or command == "EGALITARIAN" or command == "MINREGRET" then
        local market = getMarket(name, "MARKET")
        local matchings, rotations = enumerateStable(market)
        if command == "LATTICE" then
            local output = {"LATTICE " .. name .. " matchings=" .. #matchings .. " rotations=" .. #rotations}
            for i, candidate in ipairs(matchings) do
                local origin = candidate.origin == 0 and "-" or tostring(candidate.origin)
                local via = candidate.via == 0 and "-" or tostring(candidate.via)
                output[#output + 1] = "MATCHING " .. i .. " from=" .. origin .. " via=" .. via .. " cost=" .. candidate.cost
                    .. " regret=" .. candidate.regret .. " " .. market:pairs(candidate.partners)
            end
            for i, notation in ipairs(rotations) do output[#output + 1] = "ROTATION " .. i .. " " .. notation end
            return output
        end
        local field, best = command == "EGALITARIAN" and "cost" or "regret", 1
        for i, candidate in ipairs(matchings) do if candidate[field] < matchings[best][field] then best = i end end
        local chosen = matchings[best]
        market:setMatching(chosen.partners, command)
        return {command .. " " .. name .. " matching=" .. best .. " " .. field .. "=" .. chosen[field],
            "MATCHING " .. market:pairs(chosen.partners)}
    elseif command == "HR" then return hospitals(getMarket(name, "MARKET"))
    elseif command == "ROOMMATES" then return roommates(getMarket(name, "ROOMS"), #words == 3)
    elseif command == "TTC" then return tradingCycles(getMarket(name, "HOUSES"))
    elseif command == "SERIAL" then return serial(getMarket(name, "HOUSES"), words)
    elseif command == "BOSTON" then
        local market = getMarket(name, "MARKET")
        local result = boston(market)
        market:setMatching(result.partners, command)
        return {"BOSTON " .. name .. " applications=" .. result.count, "MATCHING " .. market:pairs(result.partners)}
    elseif command == "MANIPULATE" then
        local market = getMarket(name, "MARKET")
        return manipulate(market, market:proposer(words[3]))
    elseif command == "STATS" then return stats(getMarket(name, "MARKET")) end
end

local count = tonumber(io.read("*l"), 10)
for _ = 1, count do
    local line = io.read("*l"):gsub("\r$", "")
    local ok, result = pcall(execute, line)
    if ok then io.write(table.concat(result, "\n"), "\n") else io.write(result, "\n") end
end
