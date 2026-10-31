local methods = {
    "NEXTFIT", "FIRSTFIT", "BESTFIT", "WORSTFIT", "ALMOSTWORST",
    "HARMONIC", "KBOUNDED", "FFD", "BFD", "WFD"
}
local method_set = {}
for _, method in ipairs(methods) do method_set[method] = true end
local parameterized = {HARMONIC = true, KBOUNDED = true}

local output = {}
local items, capacity = nil, nil

local function emit(...)
    local parts = {...}
    for i, value in ipairs(parts) do parts[i] = tostring(value) end
    output[#output + 1] = table.concat(parts, " ")
end

local function fail(reason)
    error({reason = reason}, 0)
end

local function ceiling(numerator, denominator)
    return math.floor((numerator + denominator - 1) / denominator)
end

local function item_text(item)
    return item[1] .. ":" .. item[2]
end

local function descending(list)
    local sorted = {}
    for _, item in ipairs(list) do sorted[#sorted + 1] = item end
    table.sort(sorted, function(a, b)
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    return sorted
end

local function new_bin(category)
    return {items = {}, load = 0, category = category}
end

local function put(bin, item)
    bin.items[#bin.items + 1] = item
    bin.load = bin.load + item[2]
end

local function copy_bin(bin)
    local result = new_bin(bin.category)
    result.load = bin.load
    for _, item in ipairs(bin.items) do result.items[#result.items + 1] = item end
    return result
end

local function copy_bins(bins)
    local result = {}
    for _, bin in ipairs(bins) do result[#result + 1] = copy_bin(bin) end
    return result
end

local function total_size()
    local amount = 0
    for _, item in ipairs(items) do amount = amount + item[2] end
    return amount
end

local function method_name(result)
    if parameterized[result.method] then
        return result.method .. " k=" .. result.parameter
    end
    return result.method
end

local function header(result, current_capacity, size)
    local text = method_name(result) .. " bins=" .. #result.bins ..
                 " inspections=" .. result.inspections ..
                 " waste=" .. (#result.bins * current_capacity - size)
    if result.method == "KBOUNDED" then
        text = text .. " closes=" .. result.closes
    end
    return text
end

local function pack(current_items, current_capacity, method, parameter)
    parameter = parameter or 0
    local result = {
        method = method, parameter = parameter, bins = {},
        steps = {}, inspections = 0, closes = 0
    }
    local order = (method == "FFD" or method == "BFD" or method == "WFD")
                  and descending(current_items) or current_items
    local active, current = {}, {}
    for _, item in ipairs(order) do
        local size = item[2]
        local before = result.inspections
        local chosen, closed, category = nil, nil, nil
        if method == "NEXTFIT" then
            if #result.bins > 0 then
                result.inspections = result.inspections + 1
                local index = #result.bins
                if result.bins[index].load + size <= current_capacity then
                    chosen = index
                end
            end
        elseif method == "FIRSTFIT" or method == "FFD" or method == "KBOUNDED" then
            local candidates = {}
            if method == "KBOUNDED" then
                candidates = active
            else
                for index = 1, #result.bins do candidates[#candidates + 1] = index end
            end
            for _, index in ipairs(candidates) do
                result.inspections = result.inspections + 1
                if result.bins[index].load + size <= current_capacity then
                    chosen = index
                    break
                end
            end
        elseif method == "HARMONIC" then
            category = math.min(math.floor(current_capacity / size), parameter)
            local index = current[category]
            if index then
                result.inspections = result.inspections + 1
                if result.bins[index].load + size <= current_capacity then
                    chosen = index
                end
            end
        else
            result.inspections = result.inspections + #result.bins
            local fitting = {}
            for index, bin in ipairs(result.bins) do
                if bin.load + size <= current_capacity then
                    fitting[#fitting + 1] = index
                end
            end
            if #fitting > 0 then
                if method == "BESTFIT" or method == "BFD" then
                    chosen = fitting[1]
                    for i = 2, #fitting do
                        local candidate = fitting[i]
                        local candidate_load = result.bins[candidate].load
                        if candidate_load > result.bins[chosen].load then
                            chosen = candidate
                        end
                    end
                else
                    table.sort(fitting, function(a, b)
                        if result.bins[a].load ~= result.bins[b].load then
                            return result.bins[a].load < result.bins[b].load
                        end
                        return a < b
                    end)
                    chosen = method == "ALMOSTWORST" and fitting[2] or fitting[1]
                    if not chosen then chosen = fitting[1] end
                end
            end
        end
        local opened = chosen == nil
        if opened then
            if method == "KBOUNDED" and #active == parameter then
                local index = 1
                for i = 2, #active do
                    if result.bins[active[i]].load > result.bins[active[index]].load then
                        index = i
                    end
                end
                closed = active[index]
                table.remove(active, index)
                result.closes = result.closes + 1
            end
            result.bins[#result.bins + 1] = new_bin(category)
            chosen = #result.bins
            if method == "KBOUNDED" then active[#active + 1] = chosen end
            if method == "HARMONIC" then current[category] = chosen end
        end
        put(result.bins[chosen], item)
        result.steps[#result.steps + 1] = {
            item = item, bin = chosen, inspected = result.inspections - before,
            opened = opened, closed = closed, category = category
        }
    end
    return result
end

local function bounds(current_items, current_capacity)
    local total, thresholds = 0, {[0] = true}
    for _, item in ipairs(current_items) do
        total = total + item[2]
        if item[2] * 2 <= current_capacity then thresholds[item[2]] = true end
    end
    local ordered = {}
    for alpha in pairs(thresholds) do ordered[#ordered + 1] = alpha end
    table.sort(ordered)
    local rows, lower = {}, 0
    for _, alpha in ipairs(ordered) do
        local count1, count2, count3, sum2, sum3 = 0, 0, 0, 0, 0
        for _, item in ipairs(current_items) do
            local size = item[2]
            if size > current_capacity - alpha then
                count1 = count1 + 1
            elseif 2 * size > current_capacity then
                count2 = count2 + 1
                sum2 = sum2 + size
            elseif size >= alpha then
                count3 = count3 + 1
                sum3 = sum3 + size
            end
        end
        local excess = sum3 - (count2 * current_capacity - sum2)
        local bound = count1 + count2 +
                      (excess > 0 and ceiling(excess, current_capacity) or 0)
        lower = math.max(lower, bound)
        rows[#rows + 1] = {alpha, count1, count2, count3, bound}
    end
    return ceiling(total, current_capacity), lower, rows
end

local function exact_search(current_items, current_capacity, limit, lower, incumbent)
    local search = {
        items = descending(current_items),
        capacity = current_capacity, limit = limit, lower = lower,
        best = copy_bins(incumbent), live = {}, nodes = 0,
        status = nil, events = {}
    }
    local remaining = {}
    remaining[#search.items + 1] = 0
    for i = #search.items, 1, -1 do
        remaining[i] = remaining[i + 1] + search.items[i][2]
    end

    local function visit(index)
        if search.nodes == search.limit then
            search.status = "limit"
            return
        end
        search.nodes = search.nodes + 1
        local count = #search.live
        local used = remaining[1] - remaining[index]
        local available = count * current_capacity - used
        local excess = remaining[index] - available
        local bound = count + (excess > 0 and ceiling(excess, current_capacity) or 0)
        if bound >= #search.best then return end
        if index == #search.items + 1 then
            search.best = copy_bins(search.live)
            search.events[#search.events + 1] = "IMPROVE bins=" .. count ..
                                                 " nodes=" .. search.nodes
            if count == lower then search.status = "bound" end
            return
        end
        local item = search.items[index]
        local seen = {}
        for _, bin in ipairs(search.live) do
            local load = bin.load
            if not seen[load] then
                seen[load] = true
                if load + item[2] <= current_capacity then
                    put(bin, item)
                    visit(index + 1)
                    table.remove(bin.items)
                    bin.load = load
                    if search.status then return end
                end
            end
        end
        if count + 1 < #search.best then
            local bin = new_bin()
            put(bin, item)
            search.live[#search.live + 1] = bin
            visit(index + 1)
            table.remove(search.live)
        end
    end
    search.visit = visit
    return search
end

local function bin_line(number, bin, bin_capacity, classes, over)
    local parts = {}
    for _, item in ipairs(bin.items) do parts[#parts + 1] = item_text(item) end
    local text = "BIN " .. number .. " load=" .. bin.load .. "/" .. bin_capacity ..
                 " items=" .. table.concat(parts, " ")
    if classes then text = text .. " class=" .. bin.category end
    if over then text = text .. " OVER" end
    emit(text)
end

local function bin_lines(bins, classes, bin_capacity)
    bin_capacity = bin_capacity or capacity
    for number, bin in ipairs(bins) do
        bin_line(number, bin, bin_capacity, classes)
    end
end

local function run_method(method, arguments)
    local parameter = parameterized[method] and tonumber(arguments[1]) or 0
    if parameterized[method] and parameter == 0 then fail("BAD PARAMETER") end
    return pack(items, capacity, method, parameter)
end

local function cmd_items(arguments)
    local chosen_capacity = tonumber(arguments[1])
    if chosen_capacity == 0 then fail("BAD CAPACITY") end
    local new_items = {}
    for index = 2, #arguments do
        local size = tonumber(arguments[index])
        if size == 0 or size > chosen_capacity then fail("BAD ITEM " .. (index - 1)) end
        new_items[#new_items + 1] = {index - 1, size}
    end
    items, capacity = new_items, chosen_capacity
    emit("ITEMS count=" .. #items .. " capacity=" .. capacity .. " total=" .. total_size())
end

local function cmd_random(arguments)
    local count, chosen_capacity, value = tonumber(arguments[1]),
        tonumber(arguments[2]), tonumber(arguments[3])
    if count == 0 or count > 40 then fail("BAD COUNT") end
    if chosen_capacity == 0 then fail("BAD CAPACITY") end
    if value == 0 or value >= 2147483647 then fail("BAD SEED") end
    local new_items = {}
    local sizes = {}
    for number = 1, count do
        value = (48271 * value) % 2147483647
        local size = value % chosen_capacity + 1
        new_items[#new_items + 1] = {number, size}
        sizes[#sizes + 1] = size
    end
    items, capacity = new_items, chosen_capacity
    emit("RANDOM count=" .. count .. " capacity=" .. capacity .. " total=" .. total_size())
    local text = {}
    for _, size in ipairs(sizes) do text[#text + 1] = tostring(size) end
    emit("SIZES " .. table.concat(text, " "))
end

local function show_method(method, arguments)
    local result = run_method(method, arguments)
    emit(header(result, capacity, total_size()))
    bin_lines(result.bins, method == "HARMONIC")
end

local function cmd_trace(arguments)
    local method = arguments[1]
    local params = {}
    for i = 2, #arguments do params[#params + 1] = arguments[i] end
    local result = run_method(method, params)
    emit("TRACE " .. header(result, capacity, total_size()))
    for index, step in ipairs(result.steps) do
        local text = "STEP " .. index .. " item=" .. item_text(step.item) ..
                     " bin=" .. step.bin .. " inspected=" .. step.inspected
        if step.opened then text = text .. " new" end
        if step.closed then text = text .. " closed=" .. step.closed end
        if step.category then text = text .. " class=" .. step.category end
        emit(text)
    end
end

local function cmd_reduce(arguments)
    local method = arguments[1]
    local params = {}
    for i = 2, #arguments do params[#params + 1] = arguments[i] end
    local result = run_method(method, params)
    local bins = result.bins
    local before = #bins
    local events = {}
    while true do
        local eliminated = false
        local sources = {}
        for i = 1, #bins do sources[i] = i end
        table.sort(sources, function(a, b)
            if bins[a].load ~= bins[b].load then return bins[a].load < bins[b].load end
            return a < b
        end)
        for _, source in ipairs(sources) do
            local loads = {}
            for i, bin in ipairs(bins) do loads[i] = bin.load end
            local moves = {}
            local success = true
            for _, item in ipairs(descending(bins[source].items)) do
                local destination = nil
                for index = 1, #bins do
                    if index ~= source and loads[index] + item[2] <= capacity then
                        if not destination or loads[index] > loads[destination] then
                            destination = index
                        end
                    end
                end
                if not destination then
                    success = false
                    break
                end
                loads[destination] = loads[destination] + item[2]
                moves[#moves + 1] = {item, destination}
            end
            if success then
                local descriptions = {}
                for _, move in ipairs(moves) do
                    descriptions[#descriptions + 1] = item_text(move[1]) .. "->" .. move[2]
                end
                events[#events + 1] = "ELIMINATE bin=" .. source ..
                    " load=" .. bins[source].load .. " moves=" .. table.concat(descriptions, " ")
                for _, move in ipairs(moves) do put(bins[move[2]], move[1]) end
                table.remove(bins, source)
                eliminated = true
                break
            end
        end
        if not eliminated then break end
    end
    emit("REDUCE " .. method_name(result) .. " before=" .. before ..
         " after=" .. #bins .. " eliminated=" .. (before - #bins))
    for _, event in ipairs(events) do emit(event) end
    bin_lines(bins, method == "HARMONIC")
end

local function cmd_bounds()
    local first, second, rows = bounds(items, capacity)
    emit("BOUNDS total=" .. total_size() .. " L1=" .. first .. " L2=" .. second)
    for _, row in ipairs(rows) do
        emit("ALPHA " .. row[1] .. " j1=" .. row[2] .. " j2=" .. row[3] ..
             " j3=" .. row[4] .. " bound=" .. row[5])
    end
end

local function cmd_compare(arguments)
    local parameter = tonumber(arguments[1])
    if parameter == 0 then fail("BAD PARAMETER") end
    local first, second = bounds(items, capacity)
    local results = {}
    for _, method in ipairs(methods) do
        results[#results + 1] = pack(items, capacity, method, parameter)
    end
    table.sort(results, function(a, b)
        if #a.bins ~= #b.bins then return #a.bins < #b.bins end
        return a.method < b.method
    end)
    emit("COMPARE k=" .. parameter .. " L1=" .. first .. " L2=" .. second)
    for _, result in ipairs(results) do
        local count = #result.bins
        emit(result.method .. " bins=" .. count .. " gap=" .. (count - second) ..
             " waste=" .. (count * capacity - total_size()) ..
             " inspections=" .. result.inspections)
    end
end

local function cmd_exact(arguments)
    local limit = tonumber(arguments[1])
    if limit == 0 then fail("BAD PARAMETER") end
    if #items >= 21 then fail("TOO MANY ITEMS") end
    local incumbent = pack(items, capacity, "FFD").bins
    local _, lower = bounds(items, capacity)
    emit("EXACT ffd=" .. #incumbent .. " L2=" .. lower)
    local search = exact_search(items, capacity, limit, lower, incumbent)
    if #incumbent == lower then
        search.status = "bound"
    else
        search.visit(1)
    end
    for _, event in ipairs(search.events) do emit(event) end
    emit("RESULT bins=" .. #search.best .. " nodes=" .. search.nodes ..
         " status=" .. (search.status or "complete"))
    bin_lines(search.best)
end

local function cmd_check(arguments)
    local labels = {}
    for _, label in ipairs(arguments) do labels[#labels + 1] = tonumber(label) end
    if #labels ~= #items then fail("BAD ASSIGNMENT") end
    for _, label in ipairs(labels) do
        if label == 0 then fail("BAD ASSIGNMENT") end
    end
    local bins = {}
    for i, label in ipairs(labels) do
        if not bins[label] then bins[label] = new_bin() end
        put(bins[label], items[i])
    end
    local count, overfull = 0, 0
    local labels_used = {}
    for label, bin in pairs(bins) do
        count = count + 1
        labels_used[#labels_used + 1] = label
        if bin.load > capacity then overfull = overfull + 1 end
    end
    table.sort(labels_used)
    local _, lower = bounds(items, capacity)
    emit("CHECK bins=" .. count .. " over=" .. overfull .. " L2=" .. lower ..
         " status=" .. (overfull == 0 and "valid" or "invalid"))
    for _, label in ipairs(labels_used) do
        bin_line(label, bins[label], capacity, false, bins[label].load > capacity)
    end
end

local function cover_lines(name, bins)
    local covered, rest = {}, nil
    for _, bin in ipairs(bins) do
        if bin.load >= capacity then
            covered[#covered + 1] = bin
        else
            rest = bin
        end
    end
    emit(name .. " covered=" .. #covered .. " rest=" .. (rest and rest.load or 0))
    bin_lines(covered)
    if rest then
        local descriptions = {}
        for _, item in ipairs(rest.items) do
            descriptions[#descriptions + 1] = item_text(item)
        end
        emit("REST items=" .. table.concat(descriptions, " "))
    end
end

local function cmd_cover()
    emit("COVER total=" .. total_size() .. " upper=" .. math.floor(total_size() / capacity))
    local sequential = {}
    for _, item in ipairs(items) do
        if #sequential == 0 or sequential[#sequential].load >= capacity then
            sequential[#sequential + 1] = new_bin()
        end
        put(sequential[#sequential], item)
    end
    cover_lines("DNF", sequential)
    local available = descending(items)
    local paired = {}
    while #available > 0 do
        local bin = new_bin()
        put(bin, table.remove(available, 1))
        while bin.load < capacity and #available > 0 do
            put(bin, table.remove(available))
        end
        paired[#paired + 1] = bin
    end
    cover_lines("BIGSMALL", paired)
end

local function machine_lines(machines)
    for number, bin in ipairs(machines) do
        local described = {}
        for _, item in ipairs(bin.items) do described[#described + 1] = item_text(item) end
        local text = #described > 0 and table.concat(described, " ") or "-"
        emit("MACHINE " .. number .. " load=" .. bin.load .. " items=" .. text)
    end
end

local function cmd_multifit(arguments)
    local count = tonumber(arguments[1])
    if count == 0 then fail("BAD PARAMETER") end
    local total = total_size()
    local largest = 0
    for _, item in ipairs(items) do largest = math.max(largest, item[2]) end
    local lower = math.max(ceiling(total, count), largest)
    local upper = math.max(ceiling(2 * total, count), largest)
    emit("MULTIFIT m=" .. count .. " lower=" .. lower .. " upper=" .. upper)
    while lower < upper do
        local middle = math.floor((lower + upper) / 2)
        local bins = #pack(items, middle, "FFD").bins
        local success = bins <= count
        emit("TRY cap=" .. middle .. " bins=" .. bins .. (success and " ok" or " fail"))
        if success then
            upper = middle
        else
            lower = middle + 1
        end
    end
    local machines = pack(items, upper, "FFD").bins
    while #machines < count do machines[#machines + 1] = new_bin() end
    local makespan = 0
    for _, bin in ipairs(machines) do makespan = math.max(makespan, bin.load) end
    emit("RESULT cap=" .. upper .. " makespan=" .. makespan)
    machine_lines(machines)
    local lpt = {}
    for i = 1, count do lpt[i] = new_bin() end
    for _, item in ipairs(descending(items)) do
        local chosen = 1
        for i = 2, count do
            if lpt[i].load < lpt[chosen].load then chosen = i end
        end
        put(lpt[chosen], item)
    end
    makespan = 0
    for _, bin in ipairs(lpt) do makespan = math.max(makespan, bin.load) end
    emit("LPT makespan=" .. makespan)
    machine_lines(lpt)
end

local function maximal_patterns(bar_length, pieces)
    local patterns = {}
    local function enumerate_prefix(index, remaining, prefix)
        local size = pieces[index][1]
        local maximum = math.floor(remaining / size)
        if index == #pieces then
            local pattern = {}
            for _, value in ipairs(prefix) do pattern[#pattern + 1] = value end
            pattern[#pattern + 1] = maximum
            patterns[#patterns + 1] = {
                counts = pattern, trim = remaining - maximum * size
            }
            return
        end
        for count = maximum, 0, -1 do
            prefix[#prefix + 1] = count
            enumerate_prefix(index + 1, remaining - count * size, prefix)
            prefix[#prefix] = nil
        end
    end
    enumerate_prefix(1, bar_length, {})
    return patterns
end

local function cmd_cutstock(arguments)
    local bar_length = tonumber(arguments[1])
    if bar_length == 0 then fail("BAD CAPACITY") end
    local pieces, seen = {}, {}
    for index = 2, #arguments do
        local token = arguments[index]
        local size_text, demand_text = token:match("^(%d+):(%d+)$")
        local size, demand = tonumber(size_text), tonumber(demand_text)
        if size == 0 or size > bar_length or demand == 0 then
            fail("BAD PIECE " .. (index - 1))
        end
        if seen[size] then fail("DUPLICATE PIECE " .. (index - 1)) end
        seen[size] = true
        pieces[#pieces + 1] = {size, demand}
    end
    table.sort(pieces, function(a, b) return a[1] > b[1] end)
    local patterns = maximal_patterns(bar_length, pieces)
    local remaining, uses, cut = {}, {}, {}
    for i, piece in ipairs(pieces) do
        remaining[i] = piece[2]
        cut[i] = 0
    end
    for index = 1, #patterns do uses[index] = 0 end

    while true do
        local unfinished = false
        for _, amount in ipairs(remaining) do
            if amount > 0 then unfinished = true; break end
        end
        if not unfinished then break end
        local chosen, best_useful = nil, -1
        for index, pattern in ipairs(patterns) do
            local useful = 0
            for j, amount in ipairs(remaining) do
                useful = useful + math.min(pattern.counts[j], amount)
            end
            if useful > best_useful then
                chosen, best_useful = index, useful
            end
        end
        uses[chosen] = uses[chosen] + 1
        for j, amount in ipairs(remaining) do
            remaining[j] = math.max(0, amount - patterns[chosen].counts[j])
        end
    end

    local quantity, bars, trim, total_cut, demanded = 0, 0, 0, 0, 0
    for _, piece in ipairs(pieces) do
        quantity = quantity + piece[1] * piece[2]
        demanded = demanded + piece[2]
    end
    for index, use in ipairs(uses) do
        bars = bars + use
        trim = trim + use * patterns[index].trim
        for j, count in ipairs(patterns[index].counts) do
            cut[j] = cut[j] + use * count
        end
    end
    for _, count in ipairs(cut) do total_cut = total_cut + count end

    emit("CUTSTOCK L=" .. bar_length .. " pieces=" .. #pieces ..
         " patterns=" .. #patterns)
    for index, pattern in ipairs(patterns) do
        local breakdown = {}
        for j, count in ipairs(pattern.counts) do
            if count > 0 then
                breakdown[#breakdown + 1] = count .. "x" .. pieces[j][1]
            end
        end
        emit("PATTERN " .. index .. " " .. table.concat(breakdown, "+") ..
             " rest=" .. pattern.trim)
    end
    for index, use in ipairs(uses) do
        if use > 0 then emit("USE " .. index .. " bars=" .. use) end
    end
    for index, piece in ipairs(pieces) do
        emit("PIECE " .. piece[1] .. " demand=" .. piece[2] ..
             " cut=" .. cut[index])
    end
    emit("TOTAL bars=" .. bars .. " trim=" .. trim ..
         " surplus=" .. (total_cut - demanded) ..
         " waste=" .. (bars * bar_length - quantity))

    local comparison_items = {}
    for _, piece in ipairs(pieces) do
        for _ = 1, piece[2] do
            comparison_items[#comparison_items + 1] = {
                #comparison_items + 1, piece[1]
            }
        end
    end
    local comparison = pack(comparison_items, bar_length, "FIRSTFIT")
    local comparison_bars = #comparison.bins
    emit("FFD bars=" .. comparison_bars ..
         " waste=" .. (comparison_bars * bar_length - quantity))
    emit("LOWER bars=" .. ceiling(quantity, bar_length))
end

local function rectangles(tokens)
    local result = {}
    for number, token in ipairs(tokens) do
        local w, h = token:match("^(%d+)x(%d+)$")
        result[#result + 1] = {number, tonumber(w), tonumber(h)}
    end
    return result
end

local function drawing(width, height, placements)
    local cells = {}
    for row = 1, height do
        cells[row] = {}
        for column = 1, width do cells[row][column] = "." end
    end
    for _, placed in ipairs(placements) do
        local number, x, y, w, h = table.unpack(placed)
        local letter = string.char(64 + number)
        for row = y + 1, y + h do
            for column = x + 1, x + w do
                cells[row][column] = letter
            end
        end
    end
    for row = height, 1, -1 do emit(table.concat(cells[row])) end
end

local function shelf_method(method, strip_width, rects, area)
    local shelves, placements = {}, {}
    for _, rect in ipairs(rects) do
        local number, w, h = table.unpack(rect)
        local chosen = nil
        if method == "NFDH" then
            if #shelves > 0 and shelves[#shelves].used + w <= strip_width then
                chosen = #shelves
            end
        else
            for index, shelf in ipairs(shelves) do
                if shelf.used + w <= strip_width then
                    if method == "FFDH" then
                        chosen = index
                        break
                    end
                    if not chosen or shelf.used > shelves[chosen].used then
                        chosen = index
                    end
                end
            end
        end
        if not chosen then
            local bottom = #shelves == 0 and 0 or
                           shelves[#shelves].bottom + shelves[#shelves].height
            shelves[#shelves + 1] = {
                bottom = bottom, height = h, used = 0, items = {}
            }
            chosen = #shelves
        end
        local shelf = shelves[chosen]
        shelf.items[#shelf.items + 1] = {number, shelf.used}
        placements[#placements + 1] = {
            number, shelf.used, shelf.bottom, w, h, false
        }
        shelf.used = shelf.used + w
    end
    local height = shelves[#shelves].bottom + shelves[#shelves].height
    emit(method .. " height=" .. height .. " shelves=" .. #shelves ..
         " util=" .. math.floor(area * 100 / (strip_width * height)))
    for index, shelf in ipairs(shelves) do
        local parts = {}
        for _, item in ipairs(shelf.items) do
            parts[#parts + 1] = string.char(64 + item[1]) .. "@" .. item[2]
        end
        emit("LEVEL " .. index .. " y=" .. shelf.bottom ..
             " h=" .. shelf.height .. " used=" .. shelf.used ..
             " items=" .. table.concat(parts, " "))
    end
    drawing(strip_width, height, placements)
end

local function cmd_shelf(arguments)
    local strip_width = tonumber(arguments[1])
    if strip_width == 0 then fail("BAD CAPACITY") end
    local tokens = {}
    for i = 2, #arguments do tokens[#tokens + 1] = arguments[i] end
    local rects = rectangles(tokens)
    for _, rect in ipairs(rects) do
        if rect[2] == 0 or rect[3] == 0 or rect[2] > strip_width then
            fail("BAD RECT " .. rect[1])
        end
    end
    table.sort(rects, function(a, b)
        if a[3] ~= b[3] then return a[3] > b[3] end
        if a[2] ~= b[2] then return a[2] > b[2] end
        return a[1] < b[1]
    end)
    local area = 0
    for _, rect in ipairs(rects) do area = area + rect[2] * rect[3] end
    emit("SHELF W=" .. strip_width .. " rects=" .. #rects .. " area=" .. area)
    for _, method in ipairs({"NFDH", "FFDH", "BFDH"}) do
        shelf_method(method, strip_width, rects, area)
    end
    local heights, placements = {}, {}
    for column = 1, strip_width do heights[column] = 0 end
    for _, rect in ipairs(rects) do
        local number, w, h = table.unpack(rect)
        local best_x, best_y = nil, nil
        for x = 0, strip_width - w do
            local y = 0
            for column = x + 1, x + w do
                y = math.max(y, heights[column])
            end
            if not best_y or y < best_y then
                best_x, best_y = x, y
            end
        end
        placements[#placements + 1] = {
            number, best_x, best_y, w, h, false
        }
        for column = best_x + 1, best_x + w do
            heights[column] = best_y + h
        end
    end
    local height = 0
    for _, col_height in ipairs(heights) do
        height = math.max(height, col_height)
    end
    emit("SKYLINE height=" .. height ..
         " util=" .. math.floor(area * 100 / (strip_width * height)))
    for _, rect in ipairs(placements) do
        local number, x, y, w, h = table.unpack(rect)
        emit("PLACE " .. string.char(64 + number) ..
             " x=" .. x .. " y=" .. y .. " w=" .. w .. " h=" .. h)
    end
    drawing(strip_width, height, placements)
end

local function new_sheet(width, height)
    return {
        free = {{0, 0, width, height}},
        placements = {},
        area = 0
    }
end

local function free_rectangle(sheets, width, height, rotate, rule)
    local chosen_sheet, chosen_index, best_area = nil, nil, nil
    for number, sheet in ipairs(sheets) do
        for index, free in ipairs(sheet.free) do
            local fw, fh = free[3], free[4]
            local fits = width <= fw and height <= fh
            local swapped = rotate and height <= fw and width <= fh
            if fits or swapped then
                if rule == "FIRST" then return number, index end
                local area = fw * fh
                if not best_area or area < best_area then
                    chosen_sheet, chosen_index, best_area = number, index, area
                end
            end
        end
    end
    return chosen_sheet, chosen_index
end

local function cmd_guillotine(arguments)
    local sheet_width, sheet_height = tonumber(arguments[1]), tonumber(arguments[2])
    if sheet_width == 0 or sheet_height == 0 then fail("BAD CAPACITY") end
    local mode, rule = arguments[3], arguments[4]
    local rotate = mode == "ROTATE"
    local tokens = {}
    for i = 5, #arguments do tokens[#tokens + 1] = arguments[i] end
    local rects = rectangles(tokens)
    for _, rect in ipairs(rects) do
        local number, w, h = table.unpack(rect)
        local fits = w <= sheet_width and h <= sheet_height
        local swapped = rotate and h <= sheet_width and w <= sheet_height
        if w == 0 or h == 0 or not (fits or swapped) then
            fail("BAD RECT " .. number)
        end
    end
    table.sort(rects, function(a, b)
        local left, right = a[2] * a[3], b[2] * b[3]
        if left ~= right then return left > right end
        return a[1] < b[1]
    end)
    local sheets, rotated_count = {}, 0
    for _, rect in ipairs(rects) do
        local number, w, h = table.unpack(rect)
        local selected_sheet, selected_index =
            free_rectangle(sheets, w, h, rotate, rule)
        if not selected_sheet then
            sheets[#sheets + 1] = new_sheet(sheet_width, sheet_height)
            selected_sheet, selected_index = #sheets, 1
        end
        local sheet = sheets[selected_sheet]
        local free = table.remove(sheet.free, selected_index)
        local x, y, fw, fh = table.unpack(free)
        local rotated = not (w <= fw and h <= fh)
        local pw, ph = w, h
        if rotated then pw, ph = h, w end
        if rotated then rotated_count = rotated_count + 1 end
        sheet.placements[#sheet.placements + 1] = {
            number, x, y, pw, ph, rotated
        }
        sheet.area = sheet.area + w * h

        local rw, rh = fw - pw, fh - ph
        local top, right
        if rw <= rh then
            top = {x, y + ph, fw, rh}
            right = {x + pw, y, rw, ph}
        else
            top = {x, y + ph, pw, rh}
            right = {x + pw, y, rw, fh}
        end
        if top[3] > 0 and top[4] > 0 then
            sheet.free[#sheet.free + 1] = top
        end
        if right[3] > 0 and right[4] > 0 then
            sheet.free[#sheet.free + 1] = right
        end
    end

    local area = 0
    for _, sheet in ipairs(sheets) do area = area + sheet.area end
    local util = math.floor(area * 100 / (#sheets * sheet_width * sheet_height))
    emit("GUILLOTINE W=" .. sheet_width .. " H=" .. sheet_height ..
         " mode=" .. mode .. " rule=" .. rule ..
         " rects=" .. #rects .. " sheets=" .. #sheets ..
         " rotated=" .. rotated_count .. " util=" .. util)
    for number, sheet in ipairs(sheets) do
        emit("SHEET " .. number .. " placed=" .. #sheet.placements ..
             " area=" .. sheet.area)
        for _, placement in ipairs(sheet.placements) do
            local id, x, y, w, h, rotated = table.unpack(placement)
            local text = "PLACE " .. string.char(64 + id) .. " x=" .. x ..
                         " y=" .. y .. " w=" .. w .. " h=" .. h
            if rotated then text = text .. " rotated" end
            emit(text)
        end
        local free = {}
        for _, region in ipairs(sheet.free) do
            local x, y, w, h = table.unpack(region)
            free[#free + 1] = x .. "," .. y .. "," .. w .. "x" .. h
        end
        emit("FREE " .. (#free > 0 and table.concat(free, " ") or "none"))
        drawing(sheet_width, sheet_height, sheet.placements)
    end
end

local function execute(line)
    local words = {}
    for token in line:gmatch("%S+") do
        words[#words + 1] = token
    end
    local command = words[1]
    local arguments = {}
    for i = 2, #words do arguments[#arguments + 1] = words[i] end
    local ok, reason = pcall(function()
        if command ~= "ITEMS" and command ~= "RANDOM" and
           command ~= "CUTSTOCK" and command ~= "SHELF" and
           command ~= "GUILLOTINE" and not items then
            fail("NO ITEMS")
        end
        if method_set[command] then
            show_method(command, arguments)
        elseif command == "ITEMS" then
            cmd_items(arguments)
        elseif command == "RANDOM" then
            cmd_random(arguments)
        elseif command == "TRACE" then
            cmd_trace(arguments)
        elseif command == "REDUCE" then
            cmd_reduce(arguments)
        elseif command == "BOUNDS" then
            cmd_bounds()
        elseif command == "COMPARE" then
            cmd_compare(arguments)
        elseif command == "EXACT" then
            cmd_exact(arguments)
        elseif command == "CHECK" then
            cmd_check(arguments)
        elseif command == "COVER" then
            cmd_cover()
        elseif command == "MULTIFIT" then
            cmd_multifit(arguments)
        elseif command == "CUTSTOCK" then
            cmd_cutstock(arguments)
        elseif command == "SHELF" then
            cmd_shelf(arguments)
        elseif command == "GUILLOTINE" then
            cmd_guillotine(arguments)
        end
    end)
    if not ok then
        if type(reason) == "table" and reason.reason then
            emit("ERROR " .. reason.reason)
        else
            error(reason)
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do execute(io.read("*l")) end
io.write(table.concat(output, "\n"), "\n")
