local Input = require("bids_io")
local Solver = require("wdp_solver")
local Payments = require("payments")
local Auctions = require("auctions")
local Report = require("report")
local Fraction = Report.Fraction
local Auction = {}
Auction.__index = Auction
local Laboratory = {}
Laboratory.__index = Laboratory
local formats = {"first_price", "second_price", "english", "dutch", "all_pay"}
local outcomes = {"vcg", "greedy", "critical", "saa"}

local function append(items, value)
    items[#items + 1] = value
end

local function extend(items, values)
    for _, value in ipairs(values) do append(items, value) end
end

local function sum(values)
    local result = 0
    for _, value in pairs(values) do result = result + value end
    return result
end

local function add_counts(totals, values)
    for key, value in pairs(values) do totals[key] = (totals[key] or 0) + value end
end

local function numbers(values)
    local sorted = {}
    for i, value in ipairs(values) do sorted[i] = value end
    table.sort(sorted)
    return #sorted == 0 and "-" or table.concat(sorted, "+")
end

local function allocation(bids, items)
    local result = {winning = {}, owners = {}, unsold = {}, accepted = 0, retained = 0}
    for _, bid in ipairs(bids) do append(result.winning, bid); result.accepted = result.accepted + bid.amount end
    table.sort(result.winning, function(a, b) return a.number < b.number end)
    for _, bid in ipairs(result.winning) do
        for _, item in ipairs(items) do if bid.bundle & item.bit ~= 0 then result.owners[item.name] = bid.bidder end end
    end
    for _, item in ipairs(items) do
        if not result.owners[item.name] then append(result.unsold, item.name); result.retained = result.retained + item.reserve end
    end
    result.welfare = result.accepted + result.retained
    return result
end

local function duplicate_name(participants)
    local seen = {}
    for _, participant in ipairs(participants) do
        if seen[participant.name] then return participant.name end
        seen[participant.name] = true
    end
end

function Auction:bid_error(text, bidder)
    local bundle_text, amount_text = text:match("^([^:]+):(%d+)$")
    if not bundle_text or #amount_text > 5 or (#amount_text > 1 and amount_text:sub(1, 1) == "0") then return "malformed bid" end
    local names = {}
    for name in (bundle_text .. "+"):gmatch("(.-)%+") do
        if not name:match("^[a-z]+$") then return "malformed bid" end
        append(names, name)
    end
    local mask = 0
    for _, name in ipairs(names) do
        local item = self.by_name[name]
        if not item then return "unknown item " .. name end
        if self.mask & item.bit == 0 then return "item not offered " .. name end
        if mask & item.bit ~= 0 then return "duplicate item " .. name end
        mask = mask | item.bit
    end
    if #names > self.parameters.max_bundle_size then return "bundle too large" end
    local amount = tonumber(amount_text)
    if amount == 0 then return "zero value" end
    for _, earlier in ipairs(bidder.valid) do if earlier.bundle == mask then return "duplicate bundle " .. earlier.number end end
    if #bidder.valid >= self.parameters.max_bids_per_bidder then return "too many bids" end
    return nil, mask, amount, #names
end

function Auction:validate(lines)
    local seen = {}
    for _, line in ipairs(lines) do
        local error = seen[line.name] and "duplicate bidder" or nil
        seen[line.name] = true
        if not error and line.language ~= "XOR" and line.language ~= "OR" then error = "bad language " .. line.language end
        local bidder
        if not error then
            bidder = {name = line.name, language = line.language, valid = {}, eligible = {}}
            append(self.bidders, bidder)
        end
        for _, text in ipairs(line.bids) do
            self.bid_count = self.bid_count + 1
            if error then append(self.rejected, {self.bid_count, line.name, error})
            else
                local reason, mask, amount, size = self:bid_error(text, bidder)
                if reason then append(self.rejected, {self.bid_count, line.name, reason})
                else
                    local bid = Input.bid(self.bid_count, #self.bidders, mask, size, amount, line.language == "XOR")
                    append(bidder.valid, bid)
                    append(self.valid, bid)
                    local reserve = 0
                    for _, item in ipairs(self.items) do if item.bit & mask ~= 0 then reserve = reserve + item.reserve end end
                    if amount >= reserve then append(bidder.eligible, bid); append(self.eligible, bid)
                    else append(self.below, {bid = bid, reserve = reserve}) end
                end
            end
        end
    end
end

function Auction.new(raw, by_name, parameters)
    local self = setmetatable({name = raw.name, items = raw.items, mask = raw.mask, by_name = by_name,
        parameters = parameters, bidders = {}, valid = {}, eligible = {}, below = {}, rejected = {}, bid_count = 0}, Auction)
    self:validate(raw.lines)
    self.optimal = Solver.solve(self.items, self.eligible)
    self.exact = allocation(self.optimal.winning, self.items)
    self.order = Solver.greedy_order(self.eligible)
    self.greedy = allocation(Solver.greedy_select(self.order), self.items)
    self.critical = Payments.critical(self.order, self.greedy.winning, self.items)
    self.vcg_details = Payments.vcg(self.items, self.eligible, self.optimal, self.bidders)
    self.values, self.greedy_values, self.vcg_paid, self.vcg_utilities, self.critical_paid, self.critical_utilities = {}, {}, {}, {}, {}, {}
    for i = 1, #self.bidders do
        local value, greedy_value, critical = 0, 0, 0
        for _, bid in ipairs(self.exact.winning) do if bid.bidder == i then value = value + bid.amount end end
        for _, bid in ipairs(self.greedy.winning) do
            if bid.bidder == i then greedy_value, critical = greedy_value + bid.amount, critical + self.critical[bid.number].payment end
        end
        local paid = self.vcg_details[i] and self.vcg_details[i].payment or 0
        self.values[i], self.greedy_values[i], self.vcg_paid[i], self.vcg_utilities[i] = value, greedy_value, paid, value - paid
        self.critical_paid[i], self.critical_utilities[i] = critical, greedy_value - critical
    end
    self.vcg_revenue, self.critical_revenue = sum(self.vcg_paid), sum(self.critical_paid)
    self.saa = self:ascending()
    return self
end

function Auction:ascending()
    local increment, choices, eligibility, prices, holders = self.parameters.saa_increment, {}, {}, {}, {}
    local bid_counts, bid_rounds, last_rounds = {}, {}, {}
    for i, bidder in ipairs(self.bidders) do
        choices[i], eligibility[i] = Auctions.candidates(bidder.valid, bidder.language == "XOR"), 0
        for _, candidate in ipairs(choices[i]) do eligibility[i] = math.max(eligibility[i], Auctions.size(candidate.bundle)) end
    end
    for _, item in ipairs(self.items) do prices[item.name] = item.reserve end
    local state, lines, last, reason = self.parameters.seed, {string.format("AUCTION %s increment %d", self.name, increment)}
    for round = 1, self.parameters.round_cap do
        local activities, new_by_bidder, new_by_item, asking_by_item, demand = {}, {}, {}, {}, 0
        for _, item in ipairs(self.items) do new_by_item[item.name] = {} end
        for i = 1, #self.bidders do
            local held, asking = 0, {}
            for _, item in ipairs(self.items) do
                if holders[item.name] == i then held = held | item.bit end
                asking[item.name] = prices[item.name] + ((holders[item.name] and holders[item.name] ~= i) and increment or 0)
            end
            local chosen, surplus = nil, 0
            for _, candidate in ipairs(choices[i]) do
                if Auctions.size(candidate.bundle | held) <= eligibility[i] then
                    local cost = 0
                    for _, item in ipairs(self.items) do if candidate.bundle & item.bit ~= 0 then cost = cost + asking[item.name] end end
                    if candidate.value - cost > surplus then chosen, surplus = candidate, candidate.value - cost end
                end
            end
            local demanded = chosen and chosen.bundle or 0
            activities[i], new_by_bidder[i] = Auctions.size(demanded | held), demanded & ~held
            demand = demand + Auctions.size(new_by_bidder[i])
            for _, item in ipairs(self.items) do
                if new_by_bidder[i] & item.bit ~= 0 then
                    append(new_by_item[item.name], i)
                    asking_by_item[item.name] = asking[item.name]
                end
            end
        end
        if demand > 0 then
            local line = string.format("ROUND %d demand %d", round, demand)
            for i, bidder in ipairs(self.bidders) do
                if new_by_bidder[i] ~= 0 then line = line .. " " .. bidder.name .. ":" .. Report.bundle(new_by_bidder[i], self.items) end
            end
            append(lines, line)
            local standing = "STANDING"
            for _, item in ipairs(self.items) do
                local bidders = new_by_item[item.name]
                if #bidders > 0 then
                    local winner = bidders[1]
                    if #bidders >= 2 then state = (48271 * state) % 2147483647; winner = bidders[state % #bidders + 1] end
                    prices[item.name], holders[item.name] = asking_by_item[item.name], winner
                    bid_counts[item.name] = (bid_counts[item.name] or 0) + #bidders
                    bid_rounds[item.name], last_rounds[item.name] = (bid_rounds[item.name] or 0) + 1, round
                end
                standing = standing .. string.format(" %s=%d@%s", item.name, prices[item.name], holders[item.name] and self.bidders[holders[item.name]].name or "-")
            end
            append(lines, standing)
        else append(lines, "ROUND " .. round .. " none") end
        local changed = {}
        for i, bidder in ipairs(self.bidders) do
            if activities[i] < eligibility[i] then eligibility[i] = activities[i]; append(changed, bidder.name .. "=" .. eligibility[i]) end
        end
        if #changed > 0 then append(lines, "ELIGIBILITY " .. table.concat(changed, " ")) end
        last = round
        if demand == 0 or round == self.parameters.round_cap then reason = demand == 0 and "quiet" or "cap"; break end
    end
    append(lines, string.format("END rounds %d %s", last, reason))
    local retained = 0
    for _, item in ipairs(self.items) do
        local holder = holders[item.name]
        if not holder then append(lines, string.format("ITEM %s unsold reserve %d", item.name, item.reserve)); retained = retained + item.reserve
        else append(lines, string.format("ITEM %s price %d holder %s bids %d rounds %d last %d", item.name, prices[item.name],
            self.bidders[holder].name, bid_counts[item.name], bid_rounds[item.name], last_rounds[item.name])) end
    end
    local paid, utilities, values, exposure, exposed = {}, {}, 0, 0, 0
    for i, bidder in ipairs(self.bidders) do
        local won, payment = 0, 0
        for _, item in ipairs(self.items) do if holders[item.name] == i then won, payment = won | item.bit, payment + prices[item.name] end end
        local value = Auctions.value_of(choices[i], won)
        local utility = value - payment
        paid[i], utilities[i], values = payment, utility, values + value
        if utility < 0 then exposure, exposed = exposure - utility, exposed + 1 end
        append(lines, string.format("BIDDER %s won %s paid %d value %d utility %d eligibility %d%s", bidder.name,
            Report.bundle(won, self.items), payment, value, utility, eligibility[i], utility < 0 and " exposed" or ""))
    end
    local revenue, welfare = sum(paid), values + retained
    append(lines, string.format("TOTAL revenue %d welfare %d efficiency %s exposure %d exposed %d", revenue, welfare,
        Report.fraction(Fraction.new(welfare, self.exact.welfare)), exposure, exposed))
    return {lines = lines, payments = paid, utilities = utilities, revenue = revenue, retained = retained, welfare = welfare,
        rounds = last, reason = reason, exposure = exposure, exposed = exposed}
end

function Auction:wdp_report()
    local lines = {string.format("AUCTION %s items %d bidders %d bids %d valid %d eligible %d", self.name,
        #self.items, #self.bidders, self.bid_count, #self.valid, #self.eligible)}
    for _, bidder in ipairs(self.bidders) do append(lines, string.format("BIDDER %s %s valid %d eligible %d",
        bidder.name, bidder.language, #bidder.valid, #bidder.eligible)) end
    for _, rejected in ipairs(self.rejected) do append(lines, string.format("REJECT %d %s %s", rejected[1], rejected[2], rejected[3])) end
    for _, below in ipairs(self.below) do
        local bid = below.bid
        append(lines, string.format("BELOW_RESERVE %d %s value %d reserve %d", bid.number, self.bidders[bid.bidder].name, bid.amount, below.reserve))
    end
    for _, share in ipairs(self.optimal.shares) do append(lines, "SHARE " .. share.item.name .. " " .. Report.fraction(share.share)
        .. " " .. (share.source and "bid " .. share.source or "reserve")) end
    append(lines, "ROOT_BOUND " .. Report.fraction(self.optimal.bound))
    for _, improvement in ipairs(self.optimal.improvements) do append(lines, string.format("IMPROVE %d welfare %d bids %s",
        improvement.nodes, improvement.welfare, numbers(improvement.numbers))) end
    local exact, greedy = self.exact, self.greedy
    append(lines, string.format("OPTIMAL welfare %d accepted %d retained %d winners %d", exact.welfare, exact.accepted, exact.retained, #exact.winning))
    for _, bid in ipairs(exact.winning) do append(lines, string.format("WIN %d %s %s %d", bid.number, self.bidders[bid.bidder].name,
        Report.bundle(bid.bundle, self.items), bid.amount)) end
    append(lines, "UNSOLD " .. (#exact.unsold == 0 and "-" or table.concat(exact.unsold, " ")))
    append(lines, string.format("SEARCH nodes %d pruned %d leaves %d improvements %d", self.optimal.nodes,
        self.optimal.pruned, self.optimal.leaves, #self.optimal.improvements))
    local order = {}
    for _, bid in ipairs(self.order) do append(order, bid.number) end
    append(lines, "GREEDY_ORDER " .. (#order == 0 and "-" or table.concat(order, " ")))
    append(lines, string.format("GREEDY welfare %d accepted %d retained %d winners %d efficiency %s", greedy.welfare,
        greedy.accepted, greedy.retained, #greedy.winning, Report.fraction(Fraction.new(greedy.welfare, exact.welfare))))
    for _, bid in ipairs(greedy.winning) do
        local critical = self.critical[bid.number]
        append(lines, string.format("GWIN %d %s %s %d critical %d against %s", bid.number, self.bidders[bid.bidder].name,
            Report.bundle(bid.bundle, self.items), bid.amount, critical.payment, critical.rival and tostring(critical.rival.number) or "-"))
    end
    append(lines, "GUNSOLD " .. (#greedy.unsold == 0 and "-" or table.concat(greedy.unsold, " ")))
    for _, item in ipairs(self.items) do
        local demand = 0
        for _, bid in ipairs(self.eligible) do if bid.bundle & item.bit ~= 0 then demand = demand + 1 end end
        append(lines, string.format("ITEM %s reserve %d demand %d optimal %s greedy %s", item.name, item.reserve, demand,
            exact.owners[item.name] and self.bidders[exact.owners[item.name]].name or "-",
            greedy.owners[item.name] and self.bidders[greedy.owners[item.name]].name or "-"))
    end
    return lines
end

function Auction:vcg_report()
    local lines = {string.format("AUCTION %s welfare %d", self.name, self.exact.welfare)}
    for i, bidder in ipairs(self.bidders) do
        local detail = self.vcg_details[i]
        if not detail then append(lines, "BIDDER " .. bidder.name .. " lost")
        else
            local won = {}
            for _, bid in ipairs(self.exact.winning) do if bid.bidder == i then append(won, bid.number) end end
            append(lines, string.format("BIDDER %s won %s value %d without %d alternative %s payment %d utility %d", bidder.name,
                numbers(won), self.values[i], detail.alternative.welfare, numbers(detail.alternative.numbers), detail.payment, self.vcg_utilities[i]))
        end
    end
    append(lines, string.format("TOTAL revenue %d pay_as_bid %d retained %d seller %d bidders %d", self.vcg_revenue,
        self.exact.accepted, self.exact.retained, self.vcg_revenue + self.exact.retained, sum(self.vcg_utilities)))
    for i, bidder in ipairs(self.bidders) do append(lines, string.format("PAYMENTS %s vcg %d pay_as_bid %d greedy %d critical %d saa %d",
        bidder.name, self.vcg_paid[i], self.values[i], self.greedy_values[i], self.critical_paid[i], self.saa.payments[i])) end
    for i, bidder in ipairs(self.bidders) do append(lines, string.format("UTILITIES %s vcg %d critical %d saa %d",
        bidder.name, self.vcg_utilities[i], self.critical_utilities[i], self.saa.utilities[i])) end
    return lines
end

function Auction:coalition_text(coalition)
    local names = {}
    for _, i in ipairs(coalition.members) do append(names, self.bidders[i].name) end
    return #names == 0 and "-" or table.concat(names, "+")
end

function Auction:core_report()
    local lines, counts = {string.format("AUCTION %s bidders %d", self.name, #self.bidders)}, {}
    if #self.bidders > self.parameters.core_max_bidders then append(lines, "SKIPPED"); counts.skipped = 1; return lines, counts end
    counts.checked = 1
    local coalitions = Payments.coalitions(self.items, self.eligible, self.bidders)
    append(lines, "COALITIONS " .. #coalitions)
    local zeros = {}
    for i = 1, #self.bidders do zeros[i] = 0 end
    local values = {{"vcg", self.vcg_revenue + self.exact.retained, self.vcg_utilities}, {"greedy", self.greedy.welfare, zeros},
        {"critical", self.critical_revenue + self.greedy.retained, self.critical_utilities},
        {"saa", self.saa.revenue + self.saa.retained, self.saa.utilities}}
    for _, outcome in ipairs(values) do
        local name, seller, utilities = outcome[1], outcome[2], outcome[3]
        append(lines, string.format("OUTCOME %s seller %d utilities %s", name, seller, table.concat(utilities, " ")))
        local blocking, minimal = Payments.blocking(coalitions, seller, utilities)
        for _, record in ipairs(minimal) do append(lines, string.format("BLOCK %s welfare %d payoff %d deficit %d bids %s",
            self:coalition_text(record.coalition), record.coalition.welfare, record.payoff, record.deficit, numbers(record.coalition.numbers))) end
        if #blocking == 0 then append(lines, "RESULT core"); counts[name] = 1
        else
            local worst = blocking[1]
            for _, record in ipairs(blocking) do if record.deficit > worst.deficit then worst = record end end
            append(lines, string.format("RESULT blocked %d minimal %d max_deficit %d by %s", #blocking, #minimal,
                worst.deficit, self:coalition_text(worst.coalition)))
        end
    end
    return lines, counts
end

function Laboratory.new()
    local items, by_name, auctions, groups, parameters = Input.read()
    return setmetatable({items = items, by_name = by_name, auctions = auctions, groups = groups, parameters = parameters,
        wdp_lines = {}, vcg_lines = {}, core_lines = {}, ascending_lines = {}, single_lines = {},
        summary_lines = {"mechanism,revenue,welfare,efficiency"}, wdp_totals = {}, vcg_totals = {}, core_totals = {},
        ascending_totals = {}, group_totals = {}}, Laboratory)
end

function Laboratory:summary_row(name, mechanism, revenue, welfare, efficiency)
    append(self.summary_lines, name .. "/" .. mechanism .. "," .. Report.fraction(revenue) .. ","
        .. Report.fraction(welfare) .. "," .. Report.fraction(efficiency))
end

function Laboratory:process_auctions()
    for _, name in ipairs(self.parameters.run) do
        local auction = Auction.new(self.auctions[name], self.by_name, self.parameters)
        extend(self.wdp_lines, auction:wdp_report())
        extend(self.vcg_lines, auction:vcg_report())
        local lines, counts = auction:core_report()
        extend(self.core_lines, lines)
        add_counts(self.core_totals, counts)
        extend(self.ascending_lines, auction.saa.lines)
        add_counts(self.wdp_totals, {auctions = 1, bids = auction.bid_count, valid = #auction.valid,
            eligible = #auction.eligible, nodes = auction.optimal.nodes, greedy_optimal = auction.greedy.welfare == auction.exact.welfare and 1 or 0})
        local revenues = {vcg = auction.vcg_revenue, pay_as_bid = auction.exact.accepted, greedy = auction.greedy.accepted,
            critical = auction.critical_revenue, saa = auction.saa.revenue}
        add_counts(self.vcg_totals, revenues)
        add_counts(self.ascending_totals, {auctions = 1, rounds = auction.saa.rounds, capped = auction.saa.reason == "cap" and 1 or 0,
            exposed = auction.saa.exposed, exposure = auction.saa.exposure})
        for _, mechanism in ipairs({"vcg", "pay_as_bid", "greedy", "critical", "saa"}) do
            local welfare = (mechanism == "vcg" or mechanism == "pay_as_bid") and auction.exact.welfare or auction.greedy.welfare
            if mechanism == "saa" then welfare = auction.saa.welfare end
            self:summary_row(name, mechanism, revenues[mechanism], welfare, Fraction.new(welfare, auction.exact.welfare))
        end
    end
end

local function validate_lot(group)
    if #group.participants == 0 then return "no bidders" end
    local duplicate = duplicate_name(group.participants)
    if duplicate then return "duplicate bidder " .. duplicate end
    for _, participant in ipairs(group.participants) do if participant.bid > participant.value then return "bid above value " .. participant.name end end
end

local function validate_slots(group)
    local rates = {}
    for _, text in ipairs(group.arguments) do
        local numerator, denominator = text:match("^([1-9]%d*)/([1-9]%d*)$")
        if not numerator then return "bad ctr " .. text end
        local rate = Fraction.new(tonumber(numerator), tonumber(denominator))
        if Fraction.new(1) < rate or (#rates > 0 and rates[#rates] <= rate) then return "bad ctr " .. text end
        append(rates, rate)
    end
    if #group.participants == 0 then return "no advertisers" end
    local duplicate = duplicate_name(group.participants)
    if duplicate then return "duplicate advertiser " .. duplicate end
    return nil, rates
end

function Laboratory:lot(group)
    local participants, reserve = group.participants, tonumber(group.arguments[1])
    local eligible, first, efficient = {}, nil, 1
    for i, participant in ipairs(participants) do
        if participant.bid >= reserve then
            append(eligible, i)
            if not first or participant.bid > participants[first].bid then first = i end
        end
        if participant.value > participants[efficient].value then efficient = i end
    end
    local optimum = math.max(reserve, participants[efficient].value)
    if participants[efficient].value < reserve then efficient = nil end
    local lines = {string.format("LOT %s reserve %d bidders %d efficient %s optimum %d", group.name, reserve,
        #participants, efficient and participants[efficient].name or "-", optimum)}
    local first_price, second_price = first and participants[first].bid or 0, efficient and reserve or 0
    if efficient then
        for i, participant in ipairs(participants) do if i ~= efficient and participant.value >= reserve then second_price = math.max(second_price, participant.value) end end
    end
    local ascending = Auctions.english(participants, reserve, self.parameters.english_increment)
    local descending = Auctions.dutch(participants, reserve, self.parameters.dutch_start, self.parameters.dutch_decrement)
    local mechanisms = {{winner = first, price = first_price}, {winner = efficient, price = second_price}, ascending,
        descending, {winner = first, price = first_price}}
    local results = {}
    for format, name in ipairs(formats) do
        local mechanism, utilities = mechanisms[format], {}
        for i = 1, #participants do utilities[i] = 0 end
        local revenue, welfare, line = mechanism.price, reserve
        if name == "all_pay" then
            revenue = 0
            for _, i in ipairs(eligible) do revenue, utilities[i] = revenue + participants[i].bid, -participants[i].bid end
        end
        local winner = mechanism.winner
        if winner then
            utilities[winner], welfare = participants[winner].value - mechanism.price, participants[winner].value
            line = string.format("%s winner %s price %d utility %d", name:upper(), participants[winner].name, mechanism.price, utilities[winner])
        else line = name:upper() .. " unsold" end
        if mechanism.steps ~= nil then line = line .. " steps " .. mechanism.steps end
        local efficiency = Fraction.new(welfare, optimum)
        append(lines, line .. string.format(" revenue %d welfare %d efficiency %s", revenue, welfare, Report.fraction(efficiency)))
        if name == "english" then
            local drops = "ENGLISH_DROPS"
            for i, participant in ipairs(participants) do drops = drops .. " " .. participant.name .. "=" .. (ascending.drops[i] and tostring(ascending.drops[i]) or "-") end
            append(lines, drops)
        end
        results[format] = {name = name, utilities = utilities, revenue = revenue, index = format}
        self:summary_row(group.name, name, revenue, welfare, efficiency)
    end
    for i, participant in ipairs(participants) do
        local utilities = {}
        for _, result in ipairs(results) do append(utilities, result.utilities[i]) end
        append(lines, "UTILITY " .. participant.name .. " " .. table.concat(utilities, " "))
    end
    table.sort(results, function(a, b)
        if a.revenue ~= b.revenue then return a.revenue > b.revenue end
        return a.index < b.index
    end)
    local names = {}
    for _, result in ipairs(results) do append(names, result.name) end
    append(lines, "RANKING " .. table.concat(names, " "))
    return lines
end

function Laboratory:slots(group, rates)
    local ranked_bids, ranked_values = {}, {}
    for i, participant in ipairs(group.participants) do ranked_bids[i], ranked_values[i] = participant, participant end
    table.sort(ranked_bids, function(a, b)
        if a.bid ~= b.bid then return a.bid > b.bid end
        return a.index < b.index
    end)
    table.sort(ranked_values, function(a, b)
        if a.value ~= b.value then return a.value > b.value end
        return a.index < b.index
    end)
    local count, slots = #group.participants, #rates
    local lines = {string.format("SLOTS %s slots %d advertisers %d", group.name, slots, count)}
    local gsp_revenue, gsp_welfare, vcg_revenue, optimum = Fraction.new(0), Fraction.new(0), Fraction.new(0), Fraction.new(0)
    for rank = 1, math.min(count, slots) do
        local bidder, rate = ranked_bids[rank], rates[rank]
        local price = Payments.gsp_price(ranked_bids, rank)
        local payment, utility = rate * price, rate * (bidder.value - price)
        gsp_revenue, gsp_welfare = gsp_revenue + payment, gsp_welfare + rate * bidder.value
        optimum = optimum + rate * ranked_values[rank].value
        append(lines, string.format("GSP %d %s ctr %s bid %d price %d payment %s utility %s", rank, bidder.name,
            Report.fraction(rate), bidder.bid, price, Report.fraction(payment), Report.fraction(utility)))
    end
    local efficiency = gsp_welfare / optimum
    append(lines, string.format("GSP_TOTAL revenue %s welfare %s efficiency %s", Report.fraction(gsp_revenue),
        Report.fraction(gsp_welfare), Report.fraction(efficiency)))
    for rank = 1, math.min(count, slots) do
        local bidder, rate = ranked_values[rank], rates[rank]
        local payment = Payments.slot_vcg(ranked_values, rates, rank)
        vcg_revenue = vcg_revenue + payment
        local utility = rate * bidder.value - payment
        append(lines, string.format("VCG %d %s ctr %s value %d payment %s price %s utility %s", rank, bidder.name,
            Report.fraction(rate), bidder.value, Report.fraction(payment), Report.fraction(payment / rate), Report.fraction(utility)))
    end
    append(lines, string.format("VCG_TOTAL revenue %s welfare %s efficiency 1", Report.fraction(vcg_revenue), Report.fraction(optimum)))
    local violations = 0
    for rank = 2, math.min(count, slots + 1) do
        local bidder, rate = ranked_bids[rank], rates[rank] or Fraction.new(0)
        local stay = rate * (bidder.value - Payments.gsp_price(ranked_bids, rank))
        local swap = rates[rank - 1] * (bidder.value - bidder.bid)
        local violated = stay < swap
        if violated then violations = violations + 1 end
        append(lines, string.format("ENVY %d %s stay %s swap %s %s", rank, bidder.name,
            Report.fraction(stay), Report.fraction(swap), violated and "violated" or "ok"))
    end
    append(lines, violations == 0 and "ENVY_FREE yes" or "ENVY_FREE no violations " .. violations)
    local deviations = 0
    for rank, bidder in ipairs(ranked_bids) do
        local rate = rates[rank] or Fraction.new(0)
        local current = rate * (bidder.value - Payments.gsp_price(ranked_bids, rank))
        for target = 1, slots do
            if target ~= rank then
                local price
                if target < rank then price = ranked_bids[target] and ranked_bids[target].bid or 0
                else price = Payments.gsp_price(ranked_bids, target) end
                local payoff = rates[target] * (bidder.value - price)
                if current < payoff then
                    deviations = deviations + 1
                    append(lines, string.format("DEVIATE %s from %d to %d gain %s", bidder.name, rank, target, Report.fraction(payoff - current)))
                end
            end
        end
    end
    append(lines, deviations == 0 and "NASH yes" or "NASH no deviations " .. deviations)
    local equilibrium = violations == 0 and deviations == 0
    append(lines, "EQUILIBRIUM " .. (equilibrium and "yes" or "no"))
    add_counts(self.group_totals, {envy_free = violations == 0 and 1 or 0, nash = deviations == 0 and 1 or 0, equilibria = equilibrium and 1 or 0})
    self:summary_row(group.name, "gsp", gsp_revenue, gsp_welfare, efficiency)
    self:summary_row(group.name, "vcg", vcg_revenue, optimum, Fraction.new(1))
    return lines
end

function Laboratory:process_groups()
    for _, group in ipairs(self.groups) do
        local key = group.kind == "lot" and "lots" or "slot_groups"
        add_counts(self.group_totals, {[key] = 1})
        local error, rates
        if group.kind == "lot" then error = validate_lot(group) else error, rates = validate_slots(group) end
        if error then
            append(self.single_lines, group.kind:upper() .. " " .. group.name .. " ERROR " .. error)
            add_counts(self.group_totals, {errors = 1})
        elseif group.kind == "lot" then extend(self.single_lines, self:lot(group))
        else extend(self.single_lines, self:slots(group, rates)) end
    end
end

function Laboratory:total_lines()
    local t = self.wdp_totals
    append(self.wdp_lines, string.format("TOTAL auctions %d bids %d valid %d eligible %d nodes %d greedy_optimal %d",
        t.auctions or 0, t.bids or 0, t.valid or 0, t.eligible or 0, t.nodes or 0, t.greedy_optimal or 0))
    t = self.vcg_totals
    local line = "OVERALL"
    for _, name in ipairs({"vcg", "pay_as_bid", "greedy", "critical", "saa"}) do line = line .. " " .. name .. " " .. (t[name] or 0) end
    append(self.vcg_lines, line)
    t = self.core_totals
    line = string.format("SUMMARY checked %d skipped %d", t.checked or 0, t.skipped or 0)
    for _, name in ipairs(outcomes) do line = line .. " " .. name .. " " .. (t[name] or 0) end
    append(self.core_lines, line)
    t = self.ascending_totals
    append(self.ascending_lines, string.format("SUMMARY auctions %d rounds %d capped %d exposed %d exposure %d",
        t.auctions or 0, t.rounds or 0, t.capped or 0, t.exposed or 0, t.exposure or 0))
    t = self.group_totals
    append(self.single_lines, string.format("SUMMARY lots %d slot_groups %d errors %d envy_free %d nash %d equilibria %d",
        t.lots or 0, t.slot_groups or 0, t.errors or 0, t.envy_free or 0, t.nash or 0, t.equilibria or 0))
end

function Laboratory:run()
    self:process_auctions()
    self:process_groups()
    self:total_lines()
    Report.write({{"wdp.txt", self.wdp_lines}, {"vcg.txt", self.vcg_lines}, {"core_check.txt", self.core_lines},
        {"ascending_log.txt", self.ascending_lines}, {"single_item.txt", self.single_lines}, {"summary.csv", self.summary_lines}})
end

Laboratory.new():run()
