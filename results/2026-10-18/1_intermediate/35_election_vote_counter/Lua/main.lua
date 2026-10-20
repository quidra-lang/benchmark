local function fail(reason) error("ERROR " .. reason, 0) end
local function copy(values) return {table.unpack(values)} end
local function zeros(count)
    local values = {}
    for i = 1, count do values[i] = 0 end
    return values
end
local function matrix(rows, columns, value)
    local result = {}
    for i = 1, rows do
        result[i] = {}
        for j = 1, columns do result[i][j] = value end
    end
    return result
end
local function contains(values, wanted)
    for _, value in ipairs(values) do if value == wanted then return true end end
    return false
end
local function filtered(values, predicate)
    local result = {}
    for _, value in ipairs(values) do if predicate(value) then result[#result + 1] = value end end
    return result
end
local function without(values, unwanted) return filtered(values, function(value) return value ~= unwanted end) end
local function append(target, values)
    for _, value in ipairs(values) do target[#target + 1] = value end
    return target
end
local function sum(values)
    local total = 0
    for _, value in ipairs(values) do total = total + value end
    return total
end
local function ascii_less(a, b)
    for i = 1, math.min(#a, #b) do
        local x, y = a:byte(i), b:byte(i)
        if x ~= y then return x < y end
    end
    return #a < #b
end
local function split(text, pattern)
    local result = {}
    for word in text:gmatch(pattern or "%S+") do result[#result + 1] = word end
    return result
end
local function tie_text(tie) return tie and " (tie)" or "" end
local function money(value) return string.format("%d.%02d", value // 100, value % 100) end
local function parse_method(words, start)
    start = start or 1
    local kind = words[start]
    return {kind = kind, parameter = tonumber(words[start + 1]),
        minimax = kind == "MINIMAX" and words[start + 1] or "WINNING"}
end
local function method_text(method)
    if method.kind == "MINIMAX" then return method.kind .. " " .. method.minimax end
    if method.kind == "APPROVAL" or method.kind == "STV" then return method.kind .. " " .. method.parameter end
    return method.kind
end
local summary_methods = {
    "PLURALITY", "RUNOFF", "IRV", "COOMBS", "BUCKLIN", "BORDA", "BALDWIN", "NANSON",
    "BLACK", "VETO", "COPELAND", "MINIMAX WINNING", "SCHULZE", "RANKEDPAIRS", "KEMENY",
}

local Election = {}
Election.__index = Election
function Election.new(number, names)
    local self = setmetatable({number = number, names = names, withdrawn = {}, tie_order = {},
        priority = {}, entries = {}, cache = {}}, Election)
    for i = 1, #names do self.withdrawn[i], self.tie_order[i] = false, i end
    table.sort(self.tie_order, function(a, b) return ascii_less(names[a], names[b]) end)
    for position, candidate in ipairs(self.tie_order) do self.priority[candidate] = position end
    return self
end
function Election:active()
    local field = {}
    for candidate = 1, #self.names do if not self.withdrawn[candidate] then field[#field + 1] = candidate end end
    return field
end
function Election:candidate(name)
    for i, candidate in ipairs(self.names) do if name == candidate then return i end end
    fail("unknown candidate " .. name)
end
function Election:checked_names(names)
    local result = {}
    for _, name in ipairs(names) do
        local candidate = self:candidate(name)
        if contains(result, candidate) then fail("duplicate candidate " .. name) end
        result[#result + 1] = candidate
    end
    return result
end
function Election:name_list(field, separator)
    local names = {}
    for _, candidate in ipairs(field) do names[#names + 1] = self.names[candidate] end
    return table.concat(names, separator or ", ")
end
function Election:ordered(field, values, ascending)
    local result = copy(field)
    table.sort(result, function(a, b)
        if values[a] == values[b] then return self.priority[a] < self.priority[b] end
        if ascending then return values[a] < values[b] end
        return values[a] > values[b]
    end)
    return result
end
function Election:preferred(field)
    local result = copy(field)
    table.sort(result, function(a, b) return self.priority[a] < self.priority[b] end)
    return result
end
function Election:value_list(field, values, cents)
    local parts = {}
    for _, candidate in ipairs(field) do
        parts[#parts + 1] = self.names[candidate] .. " " .. (cents and money(values[candidate]) or values[candidate])
    end
    return table.concat(parts, ", ")
end
function Election:aggregate(field)
    local mask = 0
    for _, candidate in ipairs(field) do mask = mask | (1 << (candidate - 1)) end
    if self.cache[mask] then return self.cache[mask] end
    local groups, by_ranking = {}, {}
    for _, entry in ipairs(self.entries) do
        for _, group in ipairs(entry) do
            local ranking = filtered(group.ranking, function(c) return mask & (1 << (c - 1)) ~= 0 end)
            local code = 1
            for _, candidate in ipairs(ranking) do code = 8 * code + candidate end
            if by_ranking[code] then by_ranking[code].votes = by_ranking[code].votes + group.votes
            else
                local merged = {votes = group.votes, ranking = ranking}
                by_ranking[code], groups[#groups + 1] = merged, merged
            end
        end
    end
    local n = #self.names
    local data = {groups = groups, first = zeros(n), last = zeros(n), borda = zeros(n),
        positions = matrix(n, #field, 0), pairwise = matrix(n, n, 0), total = 0, blank = 0}
    for _, group in ipairs(groups) do
        local ranking, votes = group.ranking, group.votes
        data.total = data.total + votes
        if #ranking == 0 then data.blank = data.blank + votes
        else data.first[ranking[1]] = data.first[ranking[1]] + votes end
        local ranks = {}
        for i = 1, n do ranks[i] = #field + 1 end
        for place, candidate in ipairs(ranking) do
            ranks[candidate] = place
            data.positions[candidate][place] = data.positions[candidate][place] + votes
            data.borda[candidate] = data.borda[candidate] + votes * (#field - place)
        end
        for _, candidate in ipairs(field) do
            if (#ranking < #field and ranks[candidate] == #field + 1)
                or (#ranking == #field and candidate == ranking[#ranking]) then
                data.last[candidate] = data.last[candidate] + votes
            end
            for _, other in ipairs(field) do
                if ranks[candidate] < ranks[other] then data.pairwise[candidate][other] = data.pairwise[candidate][other] + votes end
            end
        end
    end
    self.cache[mask] = data
    return data
end

local Tally = {}
Tally.__index = Tally
function Tally.new(election, field)
    field = field or election:active()
    return setmetatable({election = election, field = field, data = election:aggregate(field)}, Tally)
end
function Tally:finish(order, tie, lines, exhaustion)
    lines[#lines + 1] = "winner: " .. self.election.names[order[1]] .. tie_text(tie)
    return {order = order, lines = lines, exhaustion = exhaustion}
end
function Tally:scored(values, label, ascending)
    local order = self.election:ordered(self.field, values, ascending)
    return self:finish(order, values[order[1]] == values[order[2]], {label .. ": " .. self.election:value_list(self.field, values)})
end
function Tally:eliminate(field, values, history)
    local minimum = values[self.election:ordered(field, values, true)[1]]
    local pool = filtered(field, function(c) return values[c] == minimum end)
    local tie = #pool > 1
    for round = #history, 1, -1 do
        local old = history[round]
        minimum = old[self.election:ordered(pool, old, true)[1]]
        pool = filtered(pool, function(c) return old[c] == minimum end)
    end
    pool = self.election:preferred(pool)
    return pool[#pool], tie
end
function Tally:pair_lines(values)
    local lines, names = {}, self.election.names
    values = values or self.data.pairwise
    for i, x in ipairs(self.field) do
        for j = i + 1, #self.field do
            local y = self.field[j]
            local a, b = values[x][y], values[y][x]
            local winner = a == b and "tie" or names[a > b and x or y]
            lines[#lines + 1] = names[x] .. " vs " .. names[y] .. ": " .. a .. "-" .. b .. " (" .. winner .. ")"
        end
    end
    return lines
end
function Tally:runoff()
    local e, first = self.election, self.data.first
    local order = e:ordered(self.field, first)
    local lines = {"round 1: " .. e:value_list(self.field, first)}
    if 2 * first[order[1]] > sum(first) then return self:finish(order, false, lines) end
    local finalists = {order[1], order[2]}
    table.sort(finalists)
    local advance = #order > 2 and first[order[2]] == first[order[3]]
    local second = e:aggregate(finalists).first
    local tie = second[order[1]] == second[order[2]]
    if second[order[2]] > second[order[1]] then order[1], order[2] = order[2], order[1] end
    lines[#lines + 1] = "finalists: " .. e:name_list(finalists) .. tie_text(advance)
    lines[#lines + 1] = "round 2: " .. e:value_list(finalists, second)
    return self:finish(order, tie, lines)
end
function Tally:instant_runoff(coombs)
    local e, remaining = self.election, copy(self.field)
    local removed, history, lines, exhaustion = {}, {}, {}, {}
    for round = 1, #self.field do
        local data = e:aggregate(remaining)
        local first, order = data.first, e:ordered(remaining, data.first)
        local active = sum(first)
        local line = "round " .. round .. ": " .. e:value_list(remaining, first)
        exhaustion[#exhaustion + 1] = "round " .. round .. ": active " .. active .. ", exhausted " .. (data.total - active)
        if #remaining == 1 or 2 * first[order[1]] > active then
            for i = #removed, 1, -1 do order[#order + 1] = removed[i] end
            lines[#lines + 1] = line
            return self:finish(order, false, lines, exhaustion)
        end
        local loser, tie
        if coombs then
            local high = data.last[e:ordered(remaining, data.last)[1]]
            local pool = filtered(remaining, function(c) return data.last[c] == high end)
            pool = e:ordered(pool, first)
            loser, tie = pool[#pool], #pool > 1
            line = line .. "; last " .. e:value_list(remaining, data.last)
        else loser, tie = self:eliminate(remaining, first, history) end
        lines[#lines + 1] = line .. "; eliminated " .. e.names[loser] .. tie_text(tie)
        history[#history + 1], removed[#removed + 1] = first, loser
        remaining = without(remaining, loser)
    end
end
function Tally:approval(depth)
    local values = zeros(#self.election.names)
    for _, candidate in ipairs(self.field) do
        for position = 1, math.min(depth, #self.field) do values[candidate] = values[candidate] + self.data.positions[candidate][position] end
    end
    return values
end
function Tally:bucklin()
    local e, history = self.election, {}
    local majority = (self.data.total - self.data.blank) // 2 + 1
    local lines = {"majority: " .. majority}
    for depth = 1, #self.field do
        local values = self:approval(depth)
        history[#history + 1] = values
        lines[#lines + 1] = "round " .. depth .. ": " .. e:value_list(self.field, values)
        if values[e:ordered(self.field, values)[1]] >= majority then break end
    end
    local order = copy(self.field)
    table.sort(order, function(a, b)
        for round = #history, 1, -1 do
            if history[round][a] ~= history[round][b] then return history[round][a] > history[round][b] end
        end
        return e.priority[a] < e.priority[b]
    end)
    return self:finish(order, history[#history][order[1]] == history[#history][order[2]], lines)
end
function Tally:borda_rounds(nanson)
    local e, remaining = self.election, copy(self.field)
    local tail, history, lines = {}, {}, {}
    while #remaining > 1 do
        local values = e:aggregate(remaining).borda
        local line = "round " .. (#lines + 1) .. ": " .. e:value_list(remaining, values)
        local losers
        if nanson then
            local total = sum(values)
            losers = filtered(remaining, function(c) return values[c] * #remaining < total end)
            if #losers == 0 then lines[#lines + 1] = line; break end
            line = line .. "; eliminated " .. e:name_list(losers)
        else
            local loser, tie = self:eliminate(remaining, values, history)
            losers = {loser}
            line = line .. "; eliminated " .. e.names[loser] .. tie_text(tie)
        end
        lines[#lines + 1], history[#history + 1] = line, values
        tail = append(e:ordered(losers, values), tail)
        remaining = filtered(remaining, function(c) return not contains(losers, c) end)
    end
    return self:finish(append(e:preferred(remaining), tail), nanson and #remaining > 1, lines)
end
function Tally:condorcet(loser)
    for _, x in ipairs(self.field) do
        local all = true
        for _, y in ipairs(self.field) do
            if x ~= y then
                local a, b = self.data.pairwise[x][y], self.data.pairwise[y][x]
                if (loser and a >= b) or (not loser and a <= b) then all = false end
            end
        end
        if all then return x end
    end
end
function Tally:black()
    local e, values = self.election, self.data.borda
    local winner, order = self:condorcet(), e:ordered(self.field, values)
    local tie = not winner and values[order[1]] == values[order[2]]
    if winner then order = append({winner}, without(order, winner)) end
    return self:finish(order, tie, {"condorcet: " .. (winner and e.names[winner] or "NONE"), "scores: " .. e:value_list(self.field, values)})
end
function Tally:closure(edges)
    for _, k in ipairs(self.field) do
        for _, x in ipairs(self.field) do
            for _, y in ipairs(self.field) do edges[x][y] = edges[x][y] or (edges[x][k] and edges[k][y]) end
        end
    end
    return edges
end
function Tally:condorcet_report()
    local n, e = #self.election.names, self.election
    local weak, strong = matrix(n, n, false), matrix(n, n, false)
    for _, x in ipairs(self.field) do
        for _, y in ipairs(self.field) do
            weak[x][y] = self.data.pairwise[x][y] >= self.data.pairwise[y][x]
            strong[x][y] = self.data.pairwise[x][y] > self.data.pairwise[y][x]
        end
    end
    self:closure(weak); self:closure(strong)
    local smith, schwartz = {}, {}
    for _, x in ipairs(self.field) do
        local top, unbeaten = true, true
        for _, y in ipairs(self.field) do
            if not weak[x][y] then top = false end
            if strong[y][x] and not strong[x][y] then unbeaten = false end
        end
        if top then smith[#smith + 1] = x end
        if unbeaten then schwartz[#schwartz + 1] = x end
    end
    local winner, loser = self:condorcet(), self:condorcet(true)
    return {order = {}, lines = {"winner: " .. (winner and e.names[winner] or "NONE"),
        "loser: " .. (loser and e.names[loser] or "NONE"), "smith: " .. e:name_list(smith), "schwartz: " .. e:name_list(schwartz)}}
end
function Tally:copeland()
    local e, values, parts = self.election, zeros(#self.election.names), {}
    for _, x in ipairs(self.field) do
        local wins, draws, losses = 0, 0, 0
        for _, y in ipairs(self.field) do
            if x ~= y then
                local a, b = self.data.pairwise[x][y], self.data.pairwise[y][x]
                if a > b then wins = wins + 1 elseif a == b then draws = draws + 1 else losses = losses + 1 end
            end
        end
        values[x] = 2 * wins + draws
        parts[#parts + 1] = string.format("%s %d.%d (%d-%d-%d)", e.names[x], values[x] // 2, 5 * (values[x] % 2), wins, draws, losses)
    end
    local order = e:ordered(self.field, values)
    return self:finish(order, values[order[1]] == values[order[2]], {"scores: " .. table.concat(parts, ", ")})
end
function Tally:minimax(kind)
    local values = zeros(#self.election.names)
    for _, x in ipairs(self.field) do
        for _, y in ipairs(self.field) do
            if x ~= y then
                local against, support = self.data.pairwise[y][x], self.data.pairwise[x][y]
                if kind == "OPPOSITION" or against > support then
                    values[x] = math.max(values[x], kind == "MARGIN" and against - support or against)
                end
            end
        end
    end
    return self:scored(values, "scores", true)
end
function Tally:dominance_order(dominates)
    local remaining, order, tie = copy(self.field), {}, false
    while #remaining > 0 do
        local eligible = filtered(remaining, function(x)
            for _, y in ipairs(remaining) do if x ~= y and dominates(y, x) then return false end end
            return true
        end)
        if #order == 0 then tie = #eligible > 1 end
        local chosen = self.election:preferred(eligible)[1]
        order[#order + 1] = chosen
        remaining = without(remaining, chosen)
    end
    return order, tie
end
function Tally:schulze()
    local paths, d = matrix(#self.election.names, #self.election.names, 0), self.data.pairwise
    for _, x in ipairs(self.field) do
        for _, y in ipairs(self.field) do if d[x][y] > d[y][x] then paths[x][y] = d[x][y] end end
    end
    for _, i in ipairs(self.field) do
        for _, j in ipairs(self.field) do
            for _, k in ipairs(self.field) do
                if i ~= j and i ~= k and j ~= k then paths[j][k] = math.max(paths[j][k], math.min(paths[j][i], paths[i][k])) end
            end
        end
    end
    local order, tie = self:dominance_order(function(x, y) return paths[x][y] > paths[y][x] end)
    local lines = self:pair_lines(paths)
    lines[#lines + 1] = "ranking: " .. self.election:name_list(order, " > ")
    return self:finish(order, tie, lines)
end
function Tally:ranked_pairs()
    local e, d, pairs = self.election, self.data.pairwise, {}
    for _, x in ipairs(self.field) do
        for _, y in ipairs(self.field) do if d[x][y] > d[y][x] then pairs[#pairs + 1] = {x, y} end end
    end
    table.sort(pairs, function(a, b)
        if d[a[1]][a[2]] ~= d[b[1]][b[2]] then return d[a[1]][a[2]] > d[b[1]][b[2]] end
        if d[a[2]][a[1]] ~= d[b[2]][b[1]] then return d[a[2]][a[1]] < d[b[2]][b[1]] end
        if a[1] ~= b[1] then return e.priority[a[1]] < e.priority[b[1]] end
        return e.priority[a[2]] < e.priority[b[2]]
    end)
    local locked, reached, lines = matrix(#e.names, #e.names, false), matrix(#e.names, #e.names, false), {}
    for _, pair in ipairs(pairs) do
        local x, y = pair[1], pair[2]
        local lock = not reached[y][x]
        if lock then locked[x][y], reached[x][y] = true, true; self:closure(reached) end
        lines[#lines + 1] = (lock and "lock " or "skip ") .. e.names[x] .. ">" .. e.names[y] .. " " .. d[x][y] .. "-" .. d[y][x]
    end
    local order, tie = self:dominance_order(function(x, y) return locked[x][y] end)
    return self:finish(order, tie, lines)
end
function Tally:kemeny()
    local mask = 0
    for _, c in ipairs(self.field) do mask = mask | (1 << (c - 1)) end
    local best, ways, heads = {[0] = 0}, {[0] = 1}, {[0] = {}}
    for subset = 1, mask do
        if subset & mask == subset then
            best[subset], ways[subset], heads[subset] = -1, 0, {}
            for _, candidate in ipairs(self.field) do
                local bit = 1 << (candidate - 1)
                if subset & bit ~= 0 then
                    local rest = subset ~ bit
                    local score = best[rest]
                    for _, other in ipairs(self.field) do
                        if rest & (1 << (other - 1)) ~= 0 then score = score + self.data.pairwise[candidate][other] end
                    end
                    if score > best[subset] then best[subset], ways[subset], heads[subset] = score, 0, {} end
                    if score == best[subset] then
                        ways[subset] = ways[subset] + ways[rest]
                        heads[subset][#heads[subset] + 1] = candidate
                    end
                end
            end
        end
    end
    local remaining, order = mask, {}
    while remaining ~= 0 do
        local candidate = self.election:preferred(heads[remaining])[1]
        order[#order + 1] = candidate
        remaining = remaining ~ (1 << (candidate - 1))
    end
    return self:finish(order, #heads[mask] > 1, {"score: " .. best[mask], "optimal: " .. ways[mask],
        "ranking: " .. self.election:name_list(order, " > ")})
end
function Tally:stv(seats)
    local e = self.election
    local groups = filtered(self.data.groups, function(group) return #group.ranking > 0 end)
    local quota = 100 * (self.data.total - self.data.blank) // (seats + 1) + 1
    local per_vote = {}
    for i = 1, #groups do per_vote[i] = 100 end
    local continuing, elected, history = copy(self.field), {}, {}
    local lines = {"quota: " .. money(quota)}
    for round = 1, #self.field do
        local values, owners, exhausted = zeros(#e.names), {}, 0
        for i, group in ipairs(groups) do
            owners[i] = 0
            for _, candidate in ipairs(group.ranking) do
                if contains(continuing, candidate) then owners[i] = candidate; break end
            end
            local amount = group.votes * per_vote[i]
            if owners[i] == 0 then exhausted = exhausted + amount else values[owners[i]] = values[owners[i]] + amount end
        end
        local line = "round " .. round .. ": " .. e:value_list(continuing, values, true) .. "; exhausted " .. money(exhausted)
        local order = e:ordered(continuing, values)
        if #continuing == seats - #elected then
            append(elected, order)
            lines[#lines + 1] = line .. "; elected " .. e:name_list(order)
            break
        end
        local chosen = order[1]
        if values[chosen] >= quota then
            local surplus = values[chosen] - quota
            elected[#elected + 1] = chosen
            for i, owner in ipairs(owners) do if owner == chosen then per_vote[i] = per_vote[i] * surplus // values[chosen] end end
            line = line .. "; elected " .. e.names[chosen] .. " (surplus " .. money(surplus) .. ")"
        else
            local tie
            chosen, tie = self:eliminate(continuing, values, history)
            line = line .. "; excluded " .. e.names[chosen] .. tie_text(tie)
        end
        lines[#lines + 1], history[#history + 1] = line, values
        continuing = without(continuing, chosen)
        if #elected == seats then break end
    end
    lines[#lines + 1] = "elected: " .. e:name_list(elected)
    return {order = {}, lines = lines}
end
function Tally:run(method)
    local kind = method.kind
    if kind == "PLURALITY" then return self:scored(self.data.first, "votes")
    elseif kind == "RUNOFF" then return self:runoff()
    elseif kind == "IRV" then return self:instant_runoff()
    elseif kind == "COOMBS" then return self:instant_runoff(true)
    elseif kind == "BUCKLIN" then return self:bucklin()
    elseif kind == "BORDA" then return self:scored(self.data.borda, "scores")
    elseif kind == "BALDWIN" then return self:borda_rounds(false)
    elseif kind == "NANSON" then return self:borda_rounds(true)
    elseif kind == "BLACK" then return self:black()
    elseif kind == "VETO" then return self:scored(self.data.last, "vetoes", true)
    elseif kind == "CONDORCET" then return self:condorcet_report()
    elseif kind == "COPELAND" then return self:copeland()
    elseif kind == "MINIMAX" then return self:minimax(method.minimax)
    elseif kind == "SCHULZE" then return self:schulze()
    elseif kind == "RANKEDPAIRS" then return self:ranked_pairs()
    elseif kind == "KEMENY" then return self:kemeny()
    elseif kind == "APPROVAL" then return self:scored(self:approval(method.parameter), "approvals")
    elseif kind == "STV" then return self:stv(method.parameter) end
end
function Tally:ballots_report()
    local e, groups = self.election, {}
    for _, group in ipairs(self.data.groups) do
        groups[#groups + 1] = {votes = group.votes, notation = #group.ranking == 0 and "-" or e:name_list(group.ranking, ">")}
    end
    table.sort(groups, function(a, b)
        if a.votes ~= b.votes then return a.votes > b.votes end
        return ascii_less(a.notation, b.notation)
    end)
    local lines = {"total " .. self.data.total .. ", blank " .. self.data.blank .. ", distinct " .. #groups}
    for _, group in ipairs(groups) do lines[#lines + 1] = group.votes .. " " .. group.notation end
    return lines
end
function Tally:profile()
    local lines = {}
    for _, candidate in ipairs(self.field) do
        local counts = self.data.positions[candidate]
        lines[#lines + 1] = self.election.names[candidate] .. ": " .. table.concat(counts, " ") .. " unranked " .. (self.data.total - sum(counts))
    end
    return lines
end

local current, election_count
election_count = 0
local function execute(line)
    local words = split(line)
    local command = words[1]
    if command == "CANDIDATES" then
        local names = {table.unpack(words, 2)}
        if #names < 2 then fail("too few candidates") end
        local seen = {}
        for _, name in ipairs(names) do
            if seen[name] then fail("duplicate candidate " .. name) end
            seen[name] = true
        end
        election_count = election_count + 1
        current = Election.new(election_count, names)
        return {"election " .. election_count .. ": " .. #names .. " candidates"}
    end
    if not current then fail("no election") end
    local e = current
    if command == "BALLOT" then
        local ranking = words[3] == "-" and {} or e:checked_names(split(words[3], "[^>]+"))
        e.entries[#e.entries + 1] = {{votes = tonumber(words[2]), ranking = ranking}}
        e.cache = {}
        return {}
    elseif command == "RANDOM" then
        local entry, state = {}, tonumber(words[3])
        for _ = 1, tonumber(words[2]) do
            local ranking = e:active()
            for i = #ranking, 2, -1 do
                state = (48271 * state) % 2147483647
                local j = state % i + 1
                ranking[i], ranking[j] = ranking[j], ranking[i]
            end
            state = (48271 * state) % 2147483647
            entry[#entry + 1] = {votes = 1, ranking = {table.unpack(ranking, 1, state % #ranking + 1)}}
        end
        e.entries[#e.entries + 1], e.cache = entry, {}
        return {}
    elseif command == "UNDO" then
        if #e.entries == 0 then fail("nothing to undo") end
        table.remove(e.entries)
        e.cache = {}
        return {}
    elseif command == "WITHDRAW" or command == "RESTORE" then
        local candidate = e:candidate(words[2])
        if command == "WITHDRAW" then
            if e.withdrawn[candidate] then fail("already withdrawn " .. words[2]) end
            if #e:active() <= 2 then fail("too few candidates") end
            e.withdrawn[candidate] = true
        else
            if not e.withdrawn[candidate] then fail("not withdrawn " .. words[2]) end
            e.withdrawn[candidate] = false
        end
        return {}
    elseif command == "TIEBREAK" then
        local order = e:checked_names({table.unpack(words, 2)})
        if #order ~= #e.names then fail("incomplete tiebreak") end
        e.tie_order = order
        for position, candidate in ipairs(order) do e.priority[candidate] = position end
        return {}
    end
    local field = e:active()
    if command ~= "STATUS" and #e.entries == 0 then fail("no ballots") end
    local tally, lines = Tally.new(e, field), {}
    if command == "STATUS" then
        local withdrawn = {}
        for candidate = 1, #e.names do if e.withdrawn[candidate] then withdrawn[#withdrawn + 1] = candidate end end
        lines = {"election " .. e.number, "active: " .. e:name_list(field),
            "withdrawn: " .. (#withdrawn == 0 and "none" or e:name_list(withdrawn)),
            "tiebreak: " .. e:name_list(e.tie_order), "ballots: " .. tally.data.total .. " in " .. #e.entries .. " entries"}
    elseif command == "BALLOTS" then lines = tally:ballots_report()
    elseif command == "PROFILE" then lines = tally:profile()
    elseif command == "PAIRWISE" then lines = tally:pair_lines()
    elseif command == "EXHAUSTED" then lines = tally:instant_runoff().exhaustion
    elseif command == "RANKING" or command == "SPOILERS" then
        local method = parse_method(words, 2)
        if method.kind == "CONDORCET" or method.kind == "STV" then fail("not rankable") end
        if command == "SPOILERS" and #field < 3 then fail("too few candidates") end
        local order = tally:run(method).order
        if command == "RANKING" then lines = {e:name_list(order, " > ")}
        else
            local winner = order[1]
            lines = {"winner: " .. e.names[winner]}
            for _, candidate in ipairs(field) do
                if candidate ~= winner then
                    local other = Tally.new(e, without(field, candidate)):run(method).order[1]
                    lines[#lines + 1] = "without " .. e.names[candidate] .. ": " .. e.names[other] .. (other ~= winner and " (changed)" or "")
                end
            end
        end
    elseif command == "SUMMARY" then
        local wins = zeros(#e.names)
        for _, text in ipairs(summary_methods) do
            local method = parse_method(split(text))
            local winner = tally:run(method).order[1]
            wins[winner] = wins[winner] + 1
            lines[#lines + 1] = method_text(method) .. ": " .. e.names[winner]
        end
        lines[#lines + 1] = "wins: " .. e:value_list(field, wins)
    elseif command == "COMPARE" then
        local x = e:candidate(words[2])
        if e.withdrawn[x] then fail("withdrawn candidate " .. words[2]) end
        local y = e:candidate(words[3])
        if e.withdrawn[y] then fail("withdrawn candidate " .. words[3]) end
        if x == y then fail("same candidate") end
        local ahead = {{}, {}}
        for _, text in ipairs(summary_methods) do
            local order = tally:run(parse_method(split(text))).order
            for _, candidate in ipairs(order) do
                if candidate == x or candidate == y then
                    local side = candidate == x and 1 or 2
                    ahead[side][#ahead[side] + 1] = text
                    break
                end
            end
        end
        local a, b = tally.data.pairwise[x][y], tally.data.pairwise[y][x]
        lines = {e.names[x] .. " " .. a .. ", " .. e.names[y] .. " " .. b .. ", neither " .. (tally.data.total - a - b),
            e.names[x] .. " ahead: " .. (#ahead[1] == 0 and "none" or table.concat(ahead[1], ", ")),
            e.names[y] .. " ahead: " .. (#ahead[2] == 0 and "none" or table.concat(ahead[2], ", "))}
    else
        local method = parse_method(words)
        if method.kind == "STV" and method.parameter >= #field then fail("too many seats") end
        lines = tally:run(method).lines
    end
    table.insert(lines, 1, "[" .. line .. "]")
    return lines
end

local count = tonumber(io.read("l"))
for _ = 1, count do
    local ok, result = pcall(execute, io.read("l"))
    if ok then for _, line in ipairs(result) do io.write(line, "\n") end
    else io.write(result, "\n") end
end
