local function fail(message)
    error({message = message}, 0)
end

local function emit(...)
    local parts = {...}
    for i, value in ipairs(parts) do parts[i] = tostring(value) end
    io.write(table.concat(parts, " "), "\n")
end

local function split(text, pattern)
    local parts = {}
    for part in text:gmatch(pattern or "%S+") do parts[#parts + 1] = part end
    return parts
end

local function slice(values, first)
    return table.move(values, first, #values, 1, {})
end

local function gcd(a, b)
    a, b = math.abs(a), math.abs(b)
    while b ~= 0 do a, b = b, a % b end
    return a
end

local Fraction = {}
Fraction.__index = Fraction

local function fraction(numerator, denominator)
    denominator = denominator or 1
    if denominator < 0 then numerator, denominator = -numerator, -denominator end
    local divisor = gcd(numerator, denominator)
    return setmetatable({n = numerator // divisor, d = denominator // divisor}, Fraction)
end

local function as_fraction(value)
    return type(value) == "number" and fraction(value) or value
end

function Fraction.__add(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d + b.n * a.d, a.d * b.d)
end

function Fraction.__sub(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d - b.n * a.d, a.d * b.d)
end

function Fraction.__mul(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.n, a.d * b.d)
end

function Fraction.__div(a, b)
    a, b = as_fraction(a), as_fraction(b)
    return fraction(a.n * b.d, a.d * b.n)
end

function Fraction.__eq(a, b) return a.n == b.n and a.d == b.d end
function Fraction.__lt(a, b) return a.n * b.d < b.n * a.d end
function Fraction.__le(a, b) return a.n * b.d <= b.n * a.d end
function Fraction.__tostring(value) return value.n .. "/" .. value.d end

local ZERO, ONE = fraction(0), fraction(1)
local function delta(i, j) return i == j and ONE or ZERO end
local function yes(value) return value and "yes" or "no" end

local function value_text(value)
    local whole = value.n // value.d
    local digits = (value.n % value.d) * 1000000 // value.d
    return string.format("%s(%d.%06d)", tostring(value), whole, digits)
end

local function probability(text)
    local parts = split(text, "[^/]+")
    local numerator = tonumber(parts[1])
    local denominator = parts[2] and tonumber(parts[2]) or 1
    if denominator == 0 or numerator > denominator then fail("BAD PROBABILITY") end
    return fraction(numerator, denominator)
end

local function vector(size, value)
    local result = {}
    for i = 1, size do result[i] = value or ZERO end
    return result
end

local function matrix(rows, columns)
    local result = {}
    for i = 1, rows do result[i] = vector(columns) end
    return result
end

local function identity(size)
    local result = matrix(size, size)
    for i = 1, size do result[i][i] = ONE end
    return result
end

local function sum(values)
    local total = ZERO
    for _, value in ipairs(values) do total = total + value end
    return total
end

local function multiply(left, right)
    local result = matrix(#left, #right[1])
    for i = 1, #left do
        for j = 1, #right[1] do
            for k = 1, #right do result[i][j] = result[i][j] + left[i][k] * right[k][j] end
        end
    end
    return result
end

local function eliminate(rows, size)
    for column = 1, size do
        local pivot_row = column
        while rows[pivot_row][column].n == 0 do pivot_row = pivot_row + 1 end
        rows[column], rows[pivot_row] = rows[pivot_row], rows[column]
        local pivot = rows[column][column]
        for j = 1, #rows[column] do rows[column][j] = rows[column][j] / pivot end
        for i = 1, size do
            local factor = rows[i][column]
            if i ~= column and factor.n ~= 0 then
                for j = 1, #rows[i] do rows[i][j] = rows[i][j] - factor * rows[column][j] end
            end
        end
    end
    local result = {}
    for i = 1, size do result[i] = slice(rows[i], size + 1) end
    return result
end

local Chain = {}
Chain.__index = Chain

function Chain.new(names)
    local positions = {}
    for i, name in ipairs(names) do positions[name] = i end
    return setmetatable({names = names, positions = positions, p = matrix(#names, #names)}, Chain)
end

function Chain:state(name)
    local index = self.positions[name]
    if not index then fail("UNKNOWN STATE " .. name) end
    return index
end

function Chain:states(names)
    local states, seen = {}, {}
    for _, name in ipairs(names) do
        local index = self:state(name)
        if seen[index] then fail("DUPLICATE STATE " .. name) end
        seen[index] = true
        states[#states + 1] = index
    end
    return states
end

function Chain:labels(states)
    local names = {}
    for _, state in ipairs(states) do names[#names + 1] = self.names[state] end
    return names
end

function Chain:block_sum(state, block)
    local total = ZERO
    for _, target in ipairs(block) do total = total + self.p[state][target] end
    return total
end

function Chain:display(values, prefix)
    emit("STATES", table.concat(self.names, " "))
    for i, row in ipairs(values or self.p) do
        local cells = {}
        for j, value in ipairs(row) do cells[j] = tostring(value) end
        emit(prefix or "ROW", self.names[i], table.concat(cells, " "))
    end
end

local function decompose(chain)
    local size = #chain.names
    local reach = matrix(size, size)
    for i = 1, size do
        for j = 1, size do reach[i][j] = i == j or chain.p[i][j].n > 0 end
    end
    for k = 1, size do
        for i = 1, size do
            for j = 1, size do reach[i][j] = reach[i][j] or reach[i][k] and reach[k][j] end
        end
    end
    local classes, class_of = {}, {}
    for i = 1, size do
        if not class_of[i] then
            local members, inside = {}, {}
            for j = 1, size do
                if reach[i][j] and reach[j][i] then
                    members[#members + 1] = j
                    inside[j] = true
                    class_of[j] = #classes + 1
                end
            end
            local closed = true
            for _, u in ipairs(members) do
                for v = 1, size do
                    if chain.p[u][v].n > 0 and not inside[v] then closed = false end
                end
            end
            local levels, queue, head = {[i] = 0}, {i}, 1
            while head <= #queue do
                local u = queue[head]
                head = head + 1
                for _, v in ipairs(members) do
                    if chain.p[u][v].n > 0 and levels[v] == nil then
                        levels[v] = levels[u] + 1
                        queue[#queue + 1] = v
                    end
                end
            end
            local period = 0
            for _, u in ipairs(members) do
                for _, v in ipairs(members) do
                    if chain.p[u][v].n > 0 then period = gcd(period, levels[u] + 1 - levels[v]) end
                end
            end
            classes[#classes + 1] = {members = members, closed = closed, levels = levels, period = period}
        end
    end
    return {reach = reach, classes = classes, class_of = class_of}
end

local function stationary(chain, members)
    local size = #members
    local rows = matrix(size, size + 1)
    for r = 1, size - 1 do
        for k = 1, size do rows[r][k] = chain.p[members[k]][members[r]] - delta(k, r) end
    end
    for k = 1, size + 1 do rows[size][k] = ONE end
    local solution, result = eliminate(rows, size), {}
    for i = 1, size do result[i] = solution[i][1] end
    return result
end

local function irreducible(chain, decomposition)
    if #decomposition.classes ~= 1 then fail("NOT IRREDUCIBLE") end
    return stationary(chain, decomposition.classes[1].members)
end

local function hitting(chain, targets, reach, probability_only)
    local size = #chain.names
    local h, times, inside, unknown = vector(size), {}, {}, {}
    for _, i in ipairs(targets) do inside[i], h[i], times[i] = true, ONE, ZERO end
    for i = 1, size do
        if not inside[i] then
            for _, target in ipairs(targets) do
                if reach[i][target] then unknown[#unknown + 1] = i; break end
            end
        end
    end
    if #unknown > 0 then
        local rows = matrix(#unknown, #unknown + 1)
        for r, i in ipairs(unknown) do
            for k, j in ipairs(unknown) do rows[r][k] = delta(i, j) - chain.p[i][j] end
            rows[r][#unknown + 1] = chain:block_sum(i, targets)
        end
        local values = eliminate(rows, #unknown)
        for r, i in ipairs(unknown) do h[i] = values[r][1] end
    end
    if probability_only then return h end
    local certain = {}
    for _, i in ipairs(unknown) do if h[i] == ONE then certain[#certain + 1] = i end end
    if #certain > 0 then
        local rows = matrix(#certain, #certain + 1)
        for r, i in ipairs(certain) do
            for k, j in ipairs(certain) do rows[r][k] = delta(i, j) - chain.p[i][j] end
            rows[r][#certain + 1] = ONE
        end
        local values = eliminate(rows, #certain)
        for r, i in ipairs(certain) do times[i] = values[r][1] end
    end
    return h, times
end

local function absorption(chain)
    local transient, absorbing = {}, {}
    for i = 1, #chain.names do
        local group = chain.p[i][i] == ONE and absorbing or transient
        group[#group + 1] = i
    end
    local size = #transient
    local rows = matrix(size, 2 * size)
    for r, i in ipairs(transient) do
        for k, j in ipairs(transient) do
            rows[r][k] = delta(i, j) - chain.p[i][j]
            rows[r][size + k] = delta(r, k)
        end
    end
    local fundamental = eliminate(rows, size)
    local means, variances, probabilities = {}, {}, matrix(size, #absorbing)
    for i, row in ipairs(fundamental) do means[i] = sum(row) end
    for i = 1, size do
        local variance = ZERO
        for j = 1, size do variance = variance + (2 * fundamental[i][j] - delta(i, j)) * means[j] end
        variances[i] = variance - means[i] * means[i]
        for j, a in ipairs(absorbing) do
            for k, t in ipairs(transient) do
                probabilities[i][j] = probabilities[i][j] + fundamental[i][k] * chain.p[t][a]
            end
        end
    end
    return {transient = transient, absorbing = absorbing, fundamental = fundamental,
            means = means, variances = variances, probabilities = probabilities}
end

local function reaches_any(reach, state, targets)
    for _, target in ipairs(targets) do if reach[state][target] then return true end end
    return false
end

local function regular_exponent(chain)
    local size, edges = #chain.names, {}
    for i = 1, #chain.names do
        edges[i] = {}
        for j = 1, #chain.names do edges[i][j] = chain.p[i][j].n > 0 end
    end
    local current = edges
    for step = 1, (size - 1) * (size - 1) + 1 do
        local positive = true
        for i = 1, size do
            for j = 1, size do if not current[i][j] then positive = false end end
        end
        if positive then return step end
        local next_matrix = {}
        for i = 1, size do
            next_matrix[i] = {}
            for j = 1, size do
                next_matrix[i][j] = false
                for k = 1, size do
                    if current[i][k] and edges[k][j] then next_matrix[i][j] = true; break end
                end
            end
        end
        current = next_matrix
    end
    return nil
end

local chains = {}
local editing = {P = true, ROW = true, SHOW = true, CHECK = true}

local function create_chain(words)
    local command, name = words[1], words[2]
    if command == "CHAIN" then
        local names, seen = slice(words, 3), {}
        if #names > 10 then fail("TOO MANY STATES") end
        for _, state in ipairs(names) do
            if seen[state] then fail("DUPLICATE STATE " .. state) end
            seen[state] = true
        end
        chains[name] = Chain.new(names)
        emit("CHAIN", name, "states=" .. #names)
    elseif command == "BUILD" then
        local order, tokens = tonumber(words[3]), slice(words, 4)
        if order ~= 1 and order ~= 2 then fail("BAD ORDER") end
        if #tokens <= order then fail("TOO FEW TOKENS") end
        local names, positions, observed = {}, {}, {}
        for i = 1, #tokens - order + 1 do
            local state = order == 1 and tokens[i] or tokens[i] .. "." .. tokens[i + 1]
            if not positions[state] then
                names[#names + 1] = state
                positions[state] = #names
            end
            observed[#observed + 1] = positions[state]
        end
        if #names > 10 then fail("TOO MANY STATES") end
        local chain, counts, totals = Chain.new(names), {}, vector(#names, 0)
        for i = 1, #names do counts[i] = vector(#names, 0) end
        for i = 1, #observed - 1 do
            local from, to = observed[i], observed[i + 1]
            counts[from][to], totals[from] = counts[from][to] + 1, totals[from] + 1
        end
        for i = 1, #names do
            if totals[i] == 0 then chain.p[i][i] = ONE
            else
                for j = 1, #names do chain.p[i][j] = fraction(counts[i][j], totals[i]) end
            end
        end
        chains[name] = chain
        emit("BUILD", name, "order=" .. order, "states=" .. #names, "transitions=" .. (#observed - 1))
        for i, state in ipairs(names) do
            local details = {}
            if totals[i] == 0 then details[1] = "absorbing"
            else
                for j, target in ipairs(names) do
                    if counts[i][j] > 0 then details[#details + 1] = target .. ":" .. counts[i][j] end
                end
            end
            emit("FROM", state, "total=" .. totals[i], table.concat(details, " "))
        end
    else
        local goal, start = tonumber(words[3]), tonumber(words[4])
        if goal == 0 or goal > 9 then fail("BAD SIZE") end
        if start > goal then fail("BAD START") end
        local p = probability(words[5])
        if p == ZERO or p == ONE then fail("BAD PROBABILITY") end
        local names = {}
        for i = 0, goal do names[#names + 1] = "s" .. i end
        local chain = Chain.new(names)
        chain.p[1][1], chain.p[goal + 1][goal + 1] = ONE, ONE
        for i = 2, goal do chain.p[i][i - 1], chain.p[i][i + 1] = ONE - p, p end
        local result = absorption(chain)
        local ruin, duration = {ONE}, {ZERO}
        for i = 1, goal - 1 do ruin[i + 1], duration[i + 1] = result.probabilities[i][1], result.means[i] end
        ruin[goal + 1], duration[goal + 1] = ZERO, ZERO
        chains[name] = chain
        emit("GAMBLER", name, "g=" .. goal, "p=" .. tostring(p), "start=s" .. start,
             "ruin=" .. value_text(ruin[start + 1]), "duration=" .. value_text(duration[start + 1]))
        for i = 1, #names do
            emit("CAPITAL", names[i], "ruin=" .. value_text(ruin[i]),
                 "win=" .. value_text(ONE - ruin[i]), "duration=" .. value_text(duration[i]))
        end
    end
end

local function execute(words)
    local command, name = words[1], words[2]
    if command == "CHAIN" or command == "BUILD" or command == "GAMBLER" then create_chain(words); return end
    local chain = chains[name]
    if not chain then fail("UNKNOWN CHAIN " .. name) end
    local size = #chain.names
    local bad = {}
    if not editing[command] or command == "CHECK" then
        for i = 1, size do if sum(chain.p[i]) ~= ONE then bad[#bad + 1] = i end end
    end
    if not editing[command] and #bad > 0 then fail("NOT STOCHASTIC " .. chain.names[bad[1]]) end
    if command == "P" then
        local from = chain:state(words[3])
        local to = chain:state(words[4])
        local value = probability(words[5])
        chain.p[from][to] = value
        emit("P", name, words[3], words[4], value, "rowsum=" .. tostring(sum(chain.p[from])))
    elseif command == "ROW" then
        local from = chain:state(words[3])
        if #words - 3 ~= size then fail("BAD LENGTH") end
        local values = {}
        for i = 1, size do values[i] = probability(words[i + 3]) end
        chain.p[from] = values
        emit("ROW", name, words[3], "rowsum=" .. tostring(sum(values)))
    elseif command == "SHOW" then
        emit("MATRIX", name, "states=" .. size)
        chain:display()
    elseif command == "CHECK" then
        emit("CHECK", name, #bad == 0 and "ok" or "bad=" .. #bad)
        for _, i in ipairs(bad) do emit("BADROW", chain.names[i], "sum=" .. tostring(sum(chain.p[i]))) end
    elseif command == "STEP" then
        local distribution
        if words[3]:match("^%d") then
            local values = split(words[3], "[^,]+")
            if #values ~= size then fail("BAD LENGTH") end
            distribution = {}
            for i, value in ipairs(values) do distribution[i] = probability(value) end
            if sum(distribution) ~= ONE then fail("BAD DISTRIBUTION") end
        else
            local state = chain:state(words[3])
            distribution = vector(size)
            distribution[state] = ONE
        end
        local steps = tonumber(words[4])
        for _ = 1, steps do distribution = multiply({distribution}, chain.p)[1] end
        emit("STEP", name, "k=" .. steps)
        for i, value in ipairs(distribution) do emit("PROB", chain.names[i], value_text(value)) end
    elseif command == "POWER" then
        local power, steps = identity(size), tonumber(words[3])
        for _ = 1, steps do power = multiply(power, chain.p) end
        emit("POWER", name, "k=" .. steps)
        chain:display(power)
    elseif command == "PATHPROB" then
        local path = {}
        for i = 3, #words do path[#path + 1] = chain:state(words[i]) end
        local product, zero_at = ONE, nil
        for i = 1, #path - 1 do
            product = product * chain.p[path[i]][path[i + 1]]
            if product.n == 0 and not zero_at then zero_at = i end
        end
        local text = "PATHPROB " .. name .. " steps=" .. (#path - 1) .. " prob=" .. value_text(product)
        emit(text .. (zero_at and " zero_at=" .. zero_at or ""))
    elseif command == "MOSTLIKELY" then
        local start, steps = chain:state(words[3]), tonumber(words[4])
        if steps == 0 then fail("BAD STEPS") end
        local best = {[steps + 1] = vector(size, ONE)}
        for t = steps, 1, -1 do
            best[t] = vector(size)
            for i = 1, size do
                for j = 1, size do
                    local value = chain.p[i][j] * best[t + 1][j]
                    if best[t][i] < value then best[t][i] = value end
                end
            end
        end
        local path, state = {start}, start
        for t = 1, steps do
            for j = 1, size do
                if chain.p[state][j] * best[t + 1][j] == best[t][state] then
                    state = j
                    path[#path + 1] = state
                    break
                end
            end
        end
        emit("MOSTLIKELY", name, words[3], "k=" .. steps, "prob=" .. value_text(best[1][start]))
        emit("PATH", table.concat(chain:labels(path), " "))
    elseif command == "FIRSTPASSAGE" then
        local from = chain:state(words[3])
        local target = chain:state(words[4])
        local steps = tonumber(words[5])
        if steps == 0 then fail("BAD STEPS") end
        local current, entries, total = {}, {}, ZERO
        for i = 1, size do current[i] = chain.p[i][target] end
        for t = 1, steps do
            total = total + current[from]
            entries[t] = {value = current[from], cumulative = total}
            if t < steps then
                local next_values = vector(size)
                for i = 1, size do
                    for j = 1, size do
                        if j ~= target then next_values[i] = next_values[i] + chain.p[i][j] * current[j] end
                    end
                end
                current = next_values
            end
        end
        emit("FIRSTPASSAGE", name, words[3], words[4], "k=" .. steps, "total=" .. value_text(total))
        for t, entry in ipairs(entries) do emit("FP", t, value_text(entry.value), "cum=" .. value_text(entry.cumulative)) end
    elseif command == "SIMULATE" then
        local state = chain:state(words[3])
        local steps, seed = tonumber(words[4]), tonumber(words[5])
        if steps == 0 then fail("BAD STEPS") end
        if seed == 0 or seed >= 2147483647 then fail("BAD SEED") end
        local random, path, visits = seed, {state}, vector(size, 0)
        visits[state] = 1
        for _ = 1, steps do
            local denominator = 1
            for _, value in ipairs(chain.p[state]) do denominator = denominator // gcd(denominator, value.d) * value.d end
            random = 48271 * random % 2147483647
            local sample, cumulative = random % denominator, ZERO
            for j = 1, size do
                cumulative = cumulative + chain.p[state][j]
                if cumulative.n * (denominator // cumulative.d) > sample then state = j; break end
            end
            path[#path + 1] = state
            visits[state] = visits[state] + 1
        end
        emit("SIMULATE", name, words[3], "steps=" .. steps, "seed=" .. seed, "end=" .. chain.names[state])
        emit("PATH", table.concat(chain:labels(path), " "))
        for i, count in ipairs(visits) do emit("VISIT", chain.names[i], count) end
    else
        local graph = decompose(chain)
        if command == "CLASSES" then
            emit("CLASSES", name, "count=" .. #graph.classes)
            for i, class in ipairs(graph.classes) do
                emit("CLASS", i, class.closed and "RECURRENT" or "TRANSIENT", "period=" .. class.period,
                     "size=" .. #class.members, table.concat(chain:labels(class.members), " "))
                if class.period >= 2 then
                    for r = 0, class.period - 1 do
                        local members = {}
                        for _, state in ipairs(class.members) do
                            if class.levels[state] % class.period == r then members[#members + 1] = state end
                        end
                        emit("CYCLIC", r, table.concat(chain:labels(members), " "))
                    end
                end
            end
        elseif command == "CLASSIFY" then
            local absorbing = {}
            for i = 1, size do if chain.p[i][i] == ONE then absorbing[#absorbing + 1] = i end end
            local all = #absorbing > 0
            for i = 1, size do if not reaches_any(graph.reach, i, absorbing) then all = false end end
            local exponent = regular_exponent(chain)
            emit("CLASSIFY", name, "absorbing_states=" .. #absorbing, "absorbing=" .. yes(all),
                 "ergodic=" .. yes(#graph.classes == 1), "regular=" .. yes(exponent ~= nil), "exponent=" .. (exponent or "-"))
        elseif command == "STATIONARY" then
            local count = 0
            for _, class in ipairs(graph.classes) do if class.closed then count = count + 1 end end
            emit("STATIONARY", name, "count=" .. count)
            local index = 0
            for number, class in ipairs(graph.classes) do
                if class.closed then
                    index = index + 1
                    local values = stationary(chain, class.members)
                    emit("DIST", index, "class=" .. number, "size=" .. #class.members)
                    for i, state in ipairs(class.members) do emit("PI", chain.names[state], value_text(values[i])) end
                end
            end
        elseif command == "RECURRENCE" then
            local state = chain:state(words[3])
            local class = graph.classes[graph.class_of[state]]
            if not class.closed then fail("TRANSIENT STATE " .. words[3]) end
            local values = stationary(chain, class.members)
            for i, member in ipairs(class.members) do
                if member == state then
                    emit("RECURRENCE", name, words[3], "pi=" .. value_text(values[i]),
                         "mean=" .. value_text(ONE / values[i]), "period=" .. class.period)
                end
            end
        elseif command == "ABSORB" then
            local absorbing = {}
            for i = 1, size do if chain.p[i][i] == ONE then absorbing[#absorbing + 1] = i end end
            if #absorbing == 0 then fail("NO ABSORBING STATE") end
            for i = 1, size do
                if not reaches_any(graph.reach, i, absorbing) then fail("NOT ABSORBING " .. chain.names[i]) end
            end
            local result = absorption(chain)
            emit("ABSORB", name, "transient=" .. #result.transient, "absorbing=" .. #absorbing)
            if #result.transient > 0 then
                emit("TRANSIENT", table.concat(chain:labels(result.transient), " "))
                emit("ABSORBING", table.concat(chain:labels(absorbing), " "))
                for i, state in ipairs(result.transient) do
                    local cells = {}
                    for j, value in ipairs(result.fundamental[i]) do cells[j] = tostring(value) end
                    emit("N", chain.names[state], table.concat(cells, " "))
                end
                for i, state in ipairs(result.transient) do
                    emit("STEPS", chain.names[state], "mean=" .. value_text(result.means[i]), "var=" .. value_text(result.variances[i]))
                end
                for i, state in ipairs(result.transient) do
                    local cells = {}
                    for j, value in ipairs(result.probabilities[i]) do cells[j] = tostring(value) end
                    emit("B", chain.names[state], table.concat(cells, " "))
                end
            end
        elseif command == "HITTING" or command == "RESTRICT" then
            local targets = chain:states(slice(words, command == "HITTING" and 3 or 4))
            table.sort(targets)
            if command == "HITTING" then
                local h, times = hitting(chain, targets, graph.reach)
                emit("HITTING", name, "targets=" .. table.concat(chain:labels(targets), ","))
                for i = 1, size do
                    emit("HIT", chain.names[i], "prob=" .. value_text(h[i]), "time=" .. (times[i] and value_text(times[i]) or "inf"))
                end
            else
                local inside = {}
                for _, i in ipairs(targets) do inside[i] = true end
                for _, i in ipairs(targets) do
                    for j = 1, size do
                        if not inside[j] and chain.p[i][j].n > 0 then fail("NOT CLOSED " .. chain.names[i]) end
                    end
                end
                local restricted = Chain.new(chain:labels(targets))
                for i, from in ipairs(targets) do
                    for j, to in ipairs(targets) do restricted.p[i][j] = chain.p[from][to] end
                end
                chains[words[3]] = restricted
                emit("RESTRICT", name, words[3], "states=" .. #targets)
                restricted:display()
            end
        elseif command == "PASSAGE" then
            local pi = irreducible(chain, graph)
            local passage = matrix(size, size)
            for j = 1, size do
                local _, times = hitting(chain, {j}, graph.reach)
                for i = 1, size do passage[i][j] = i == j and ONE / pi[j] or times[i] end
            end
            local kemeny = ZERO
            for j = 2, size do kemeny = kemeny + pi[j] * passage[1][j] end
            emit("PASSAGE", name, "kemeny=" .. value_text(kemeny))
            chain:display(passage, "M")
        elseif command == "REVERSIBLE" or command == "REVERSE" then
            local pi = irreducible(chain, graph)
            if command == "REVERSIBLE" then
                local violations = {}
                for i = 1, size do
                    for j = i + 1, size do
                        local left, right = pi[i] * chain.p[i][j], pi[j] * chain.p[j][i]
                        if left ~= right then violations[#violations + 1] = {i, j, left, right} end
                    end
                end
                emit("REVERSIBLE", name, #violations == 0 and "yes" or "no violations=" .. #violations)
                for _, pair in ipairs(violations) do
                    emit("VIOLATION", chain.names[pair[1]], chain.names[pair[2]], value_text(pair[3]), value_text(pair[4]))
                end
            else
                local reversed, reversible = Chain.new(slice(chain.names, 1)), true
                for i = 1, size do
                    for j = 1, size do
                        reversed.p[i][j] = pi[j] * chain.p[j][i] / pi[i]
                        if reversed.p[i][j] ~= chain.p[i][j] then reversible = false end
                    end
                end
                chains[words[3]] = reversed
                emit("REVERSE", name, words[3], "reversible=" .. yes(reversible))
                reversed:display()
            end
        elseif command == "MIXING" then
            local steps = tonumber(words[3])
            if steps == 0 then fail("BAD STEPS") end
            local epsilon = probability(words[4])
            local pi = irreducible(chain, graph)
            local power, entries, mixing = identity(size), {}, nil
            for t = 1, steps do
                power = multiply(power, chain.p)
                local distance, from = ZERO, 1
                for i = 1, size do
                    local total = ZERO
                    for j = 1, size do
                        local difference = power[i][j] - pi[j]
                        total = total + fraction(math.abs(difference.n), difference.d)
                    end
                    total = total / 2
                    if distance < total then distance, from = total, i end
                end
                if not mixing and distance <= epsilon then mixing = t end
                entries[t] = {distance = distance, from = from}
            end
            emit("MIXING", name, "k=" .. steps, "eps=" .. tostring(epsilon), "time=" .. (mixing or "none"))
            for t, entry in ipairs(entries) do emit("TV", t, value_text(entry.distance), "from=" .. chain.names[entry.from]) end
        elseif command == "LUMP" then
            local blocks, seen, count = {}, {}, 0
            for _, text in ipairs(split(words[4], "[^|]+")) do
                local block = {}
                for _, state in ipairs(split(text, "[^,]+")) do
                    local index = chain:state(state)
                    if seen[index] then fail("BAD PARTITION") end
                    seen[index], count = true, count + 1
                    block[#block + 1] = index
                end
                table.sort(block)
                blocks[#blocks + 1] = block
            end
            if count ~= size then fail("BAD PARTITION") end
            table.sort(blocks, function(a, b) return a[1] < b[1] end)
            local representatives = {}
            for i, block in ipairs(blocks) do representatives[i] = block[1] end
            local lumped = Chain.new(chain:labels(representatives))
            for i, block in ipairs(blocks) do
                for j, target in ipairs(blocks) do
                    local base = chain:block_sum(block[1], target)
                    for _, state in ipairs(block) do
                        local value = chain:block_sum(state, target)
                        if value ~= base then
                            emit("LUMP", name, "not lumpable", "block=" .. chain.names[block[1]],
                                 "target=" .. chain.names[target[1]], chain.names[block[1]] .. "=" .. value_text(base),
                                 chain.names[state] .. "=" .. value_text(value))
                            return
                        end
                    end
                    lumped.p[i][j] = base
                end
            end
            chains[words[3]] = lumped
            emit("LUMP", name, words[3], "blocks=" .. #blocks)
            lumped:display()
        elseif command == "REWARD" then
            if #words - 3 ~= size then fail("BAD LENGTH") end
            local discount = probability(words[3])
            if discount == ONE then fail("BAD DISCOUNT") end
            local rewards, rows = {}, matrix(size, size + 1)
            for i = 1, size do
                rewards[i] = fraction(tonumber(words[i + 3]))
                for j = 1, size do rows[i][j] = delta(i, j) - discount * chain.p[i][j] end
                rows[i][size + 1] = rewards[i]
            end
            local discounted, gain = eliminate(rows, size), vector(size)
            for _, class in ipairs(graph.classes) do
                if class.closed then
                    local rho, average = stationary(chain, class.members), ZERO
                    for i, state in ipairs(class.members) do average = average + rho[i] * rewards[state] end
                    local h = hitting(chain, class.members, graph.reach, true)
                    for i = 1, size do gain[i] = gain[i] + h[i] * average end
                end
            end
            emit("REWARD", name, "gamma=" .. tostring(discount))
            for i = 1, size do emit("VALUE", chain.names[i], "discounted=" .. value_text(discounted[i][1]), "gain=" .. value_text(gain[i])) end
        end
    end
end

local commands = tonumber(io.read("l"))
for _ = 1, commands do
    local ok, problem = pcall(execute, split(io.read("l")))
    if not ok then
        if type(problem) ~= "table" or not problem.message then error(problem) end
        emit("ERROR", problem.message)
    end
end
