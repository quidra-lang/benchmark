local tasks, dependencies, capacities, holidays = {}, {}, {}, {}
local start_date, deadline, baseline
local output = {}
local function emit(pattern, ...)
    output[#output + 1] = string.format(pattern, ...)
end
local function fail(pattern, ...)
    error(string.format(pattern, ...), 0)
end
local function keys(items)
    local result = {}
    for name in pairs(items) do
        result[#result + 1] = name
    end
    table.sort(result)
    return result
end
local function copy(values)
    return {table.unpack(values)}
end
local function get(name)
    if not tasks[name] then
        fail("unknown task %s", name)
    end
    return tasks[name]
end
local function leap(year)
    return year % 4 == 0 and year % 100 ~= 0 or year % 400 == 0
end
local function month_days(year, month)
    local days = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
    return month == 2 and leap(year) and 29 or days[month]
end
local function date_value(text)
    local year, month, day = tonumber(text:sub(1, 4)), tonumber(text:sub(6, 7)), tonumber(text:sub(9, 10))
    if month < 1 or month > 12 or day < 1 or day > month_days(year, month) then
        return nil
    end
    local total = day - 1
    for y = 2000, year - 1 do
        total = total + (leap(y) and 366 or 365)
    end
    for m = 1, month - 1 do
        total = total + month_days(year, m)
    end
    return total
end
local function date_text(ordinal)
    local original, year, month = ordinal, 2000, 1
    while ordinal >= (leap(year) and 366 or 365) do
        ordinal = ordinal - (leap(year) and 366 or 365)
        year = year + 1
    end
    while ordinal >= month_days(year, month) do
        ordinal = ordinal - month_days(year, month)
        month = month + 1
    end
    local weekdays = {"Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"}
    return string.format("%04d-%02d-%02d %s", year, month, ordinal + 1, weekdays[(original + 5) % 7 + 1])
end
local function decimal(numerator, denominator)
    local value = numerator * 100 // denominator
    return string.format("%d.%02d", value // 100, value % 100)
end
local function predecessors(name)
    local result = {}
    for _, dep in pairs(dependencies) do
        if dep.to == name then
            result[#result + 1] = dep
        end
    end
    table.sort(result, function(a, b) return a.from < b.from end)
    return result
end
local function successors(name)
    local result = {}
    for _, dep in pairs(dependencies) do
        if dep.from == name then
            result[#result + 1] = dep
        end
    end
    table.sort(result, function(a, b) return a.to < b.to end)
    return result
end
local function topology()
    local names, removed, order = keys(tasks), {}, {}
    while true do
        local selected
        for _, name in ipairs(names) do
            if not removed[name] then
                local ready = true
                for _, dep in ipairs(predecessors(name)) do
                    if not removed[dep.from] then
                        ready = false
                        break
                    end
                end
                if ready then
                    selected = name
                    break
                end
            end
        end
        if not selected then
            break
        end
        removed[selected], order[#order + 1] = true, selected
    end
    if #order == #names then
        return order, nil
    end
    local current
    for _, name in ipairs(names) do
        if not removed[name] then
            current = name
            break
        end
    end
    local visited, chain = {}, {}
    while true do
        if visited[current] then
            local at, cycle = visited[current], {current}
            for i = #chain, at + 1, -1 do
                cycle[#cycle + 1] = chain[i]
            end
            local first = 1
            for i, name in ipairs(cycle) do
                if name < cycle[first] then
                    first = i
                end
            end
            local rotated = {}
            for i = first, #cycle do
                rotated[#rotated + 1] = cycle[i]
            end
            for i = 1, first - 1 do
                rotated[#rotated + 1] = cycle[i]
            end
            rotated[#rotated + 1] = rotated[1]
            return order, table.concat(rotated, " -> ")
        end
        chain[#chain + 1], visited[current] = current, #chain + 1
        for _, dep in ipairs(predecessors(current)) do
            if not removed[dep.from] then
                current = dep.from
                break
            end
        end
    end
end
local function duration(name, override)
    if override and override[name] ~= nil then
        return override[name]
    end
    return tasks[name].base - tasks[name].crashed
end
local function margin(dep, schedule)
    local a, b = schedule.times[dep.from], schedule.times[dep.to]
    if dep.kind == "SS" then
        return b.es - a.es - dep.lag
    elseif dep.kind == "FF" then
        return b.ef - a.ef - dep.lag
    end
    return b.es - a.ef - dep.lag
end
local function compute(order, override)
    local result = {times = {}, total = 0}
    for _, name in ipairs(order) do
        local start, d = tasks[name].not_before, duration(name, override)
        for _, dep in ipairs(predecessors(name)) do
            local a = result.times[dep.from]
            local value = a.ef + dep.lag
            if dep.kind == "SS" then
                value = a.es + dep.lag
            elseif dep.kind == "FF" then
                value = value - d
            end
            start = math.max(start, value)
        end
        result.times[name] = {es = start, ef = start + d}
        result.total = math.max(result.total, start + d)
    end
    for i = #order, 1, -1 do
        local name = order[i]
        local value, d, finish = result.times[name], duration(name, override), result.total
        for _, dep in ipairs(successors(name)) do
            local b = result.times[dep.to]
            local candidate = b.ls - dep.lag
            if dep.kind == "SS" then
                candidate = candidate + d
            elseif dep.kind == "FF" then
                candidate = b.lf - dep.lag
            end
            finish = math.min(finish, candidate)
        end
        value.lf, value.ls = finish, finish - d
        value.tf, value.free = value.ls - value.es, result.total - value.ef
    end
    for _, name in ipairs(order) do
        local value = result.times[name]
        for _, dep in ipairs(successors(name)) do
            value.free = math.min(value.free, margin(dep, result))
        end
    end
    return result
end
local function critical(schedule)
    local result = {}
    for _, name in ipairs(keys(tasks)) do
        if schedule.times[name].tf == 0 then
            result[#result + 1] = name
        end
    end
    return result
end
local function critical_paths(schedule)
    local following, incoming = {}, {}
    for _, name in ipairs(keys(tasks)) do
        following[name] = {}
        for _, dep in ipairs(successors(name)) do
            if schedule.times[name].tf == 0 and schedule.times[dep.to].tf == 0 and margin(dep, schedule) == 0 then
                following[name][#following[name] + 1], incoming[dep.to] = dep.to, true
            end
        end
    end
    local result = {}
    local function visit(name, prefix)
        local path = copy(prefix)
        path[#path + 1] = name
        if #following[name] == 0 then
            result[#result + 1] = path
        else
            for _, next_name in ipairs(following[name]) do
                visit(next_name, path)
            end
        end
    end
    for _, name in ipairs(critical(schedule)) do
        if not incoming[name] then
            visit(name, {})
        end
    end
    return result
end
local function resources()
    local all = {}
    for _, task in pairs(tasks) do
        all[task.resource] = true
    end
    return keys(all)
end
local function usage(schedule, resource)
    local result = {}
    for day = 0, schedule.total - 1 do
        result[day + 1] = 0
    end
    for name, task in pairs(tasks) do
        if task.resource == resource then
            local value = schedule.times[name]
            for day = value.es, value.ef - 1 do
                result[day + 1] = result[day + 1] + task.units
            end
        end
    end
    return result
end
local function peak(values)
    local result = 0
    for _, value in ipairs(values) do
        result = math.max(result, value)
    end
    return result
end
local function working_day(day)
    return (day + 5) % 7 < 5 and not holidays[day]
end
local function start_order(schedule)
    local names = keys(tasks)
    table.sort(names, function(a, b)
        if schedule.times[a].es ~= schedule.times[b].es then
            return schedule.times[a].es < schedule.times[b].es
        end
        return a < b
    end)
    return names
end
local function calendar(schedule)
    local days, day = {}, start_date
    while #days < schedule.total do
        if working_day(day) then
            days[#days + 1] = day
        end
        day = day + 1
    end
    for _, name in ipairs(start_order(schedule)) do
        local value = schedule.times[name]
        emit("%s %s - %s", name, date_text(days[value.es + 1]), date_text(days[value.ef]))
    end
    local first, last = days[1], days[#days]
    emit("project %s - %s, %d working days, %d calendar days", date_text(first), date_text(last), schedule.total, last - first + 1)
    if deadline then
        local a, b, count = math.min(last, deadline), math.max(last, deadline), 0
        for date = a + 1, b do
            if working_day(date) then
                count = count + 1
            end
        end
        if last <= deadline then
            emit("deadline %s met, %d working days to spare", date_text(deadline), count)
        else
            emit("deadline %s missed by %d working days", date_text(deadline), count)
        end
    end
    local selected, text = {}, {}
    for date in pairs(holidays) do
        if date >= first and date <= last and (date + 5) % 7 < 5 then
            selected[#selected + 1] = date
        end
    end
    table.sort(selected)
    for _, date in ipairs(selected) do
        text[#text + 1] = date_text(date)
    end
    emit("holidays in span: %s", #text > 0 and table.concat(text, ", ") or "none")
end
local function level(order, schedule, limit)
    local function capacity(resource)
        return capacities[resource] or limit
    end
    for _, name in ipairs(keys(tasks)) do
        local task = tasks[name]
        if task.units > capacity(task.resource) then
            fail("capacity %d too small for %s", capacity(task.resource), name)
        end
    end
    local decided, loads, sequence, total = {}, {}, {}, 0
    while #sequence < #order do
        local selected
        for _, name in ipairs(keys(tasks)) do
            if not decided[name] then
                local ready = true
                for _, dep in ipairs(predecessors(name)) do
                    if not decided[dep.from] then
                        ready = false
                        break
                    end
                end
                if ready and (not selected or schedule.times[name].ls < schedule.times[selected].ls) then
                    selected = name
                end
            end
        end
        local task = tasks[selected]
        local start, d = task.not_before, duration(selected)
        for _, dep in ipairs(predecessors(selected)) do
            local a = decided[dep.from]
            local value = a.ef + dep.lag
            if dep.kind == "SS" then
                value = a.es + dep.lag
            elseif dep.kind == "FF" then
                value = value - d
            end
            start = math.max(start, value)
        end
        local load = loads[task.resource] or {}
        while true do
            local valid = true
            for day = start, start + d - 1 do
                if (load[day + 1] or 0) + task.units > capacity(task.resource) then
                    valid = false
                    break
                end
            end
            if valid then
                break
            end
            start = start + 1
        end
        while #load < start + d do
            load[#load + 1] = 0
        end
        for day = start, start + d - 1 do
            load[day + 1] = load[day + 1] + task.units
        end
        loads[task.resource], decided[selected] = load, {es = start, ef = start + d}
        sequence[#sequence + 1], total = selected, math.max(total, start + d)
    end
    emit("level capacity %d: duration %d -> %d", limit, schedule.total, total)
    for _, name in ipairs(sequence) do
        local value = decided[name]
        emit("%s start %d finish %d shift %d", name, value.es, value.ef, value.es - schedule.times[name].es)
    end
    for _, resource in ipairs(resources()) do
        emit("resource %s capacity %d peak %d -> %d", resource, capacity(resource), peak(usage(schedule, resource)), peak(loads[resource]))
    end
end

local function command(w)
    local cmd = w[1]
    if cmd == "TASK" then
        if tasks[w[2]] then
            fail("task %s already exists", w[2])
        end
        tasks[w[2]] = {name = w[2], base = tonumber(w[3]), resource = w[4], units = tonumber(w[5]), not_before = 0, crashed = 0}
        emit("task %s added", w[2])
        return
    elseif cmd == "DEP" or cmd == "UNDEP" then
        get(w[2])
        get(w[3])
        local key = w[2] .. "\0" .. w[3]
        if cmd == "DEP" then
            if w[2] == w[3] then
                fail("self dependency %s", w[2])
            end
            if dependencies[key] then
                fail("dependency %s -> %s already exists", w[2], w[3])
            end
            dependencies[key] = {from = w[2], to = w[3], kind = w[4], lag = tonumber(w[5])}
            emit("dependency %s -> %s %s%+d added", w[2], w[3], w[4], tonumber(w[5]))
        else
            if not dependencies[key] then
                fail("no dependency %s -> %s", w[2], w[3])
            end
            dependencies[key] = nil
            emit("dependency %s -> %s removed", w[2], w[3])
        end
        return
    elseif cmd == "REMOVE" or cmd == "NOTBEFORE" or cmd == "CRASHCOST" or cmd == "UNCRASH" or
        cmd == "PERT" or cmd == "SHOW" or cmd == "IMPACT" then
        local task = get(w[2])
        if cmd == "REMOVE" then
            local count = 0
            for key, dep in pairs(dependencies) do
                if dep.from == task.name or dep.to == task.name then
                    dependencies[key], count = nil, count + 1
                end
            end
            tasks[task.name] = nil
            emit("task %s removed with %d dependencies", task.name, count)
        elseif cmd == "NOTBEFORE" then
            task.not_before = tonumber(w[3])
            emit("notbefore %s %s", task.name, w[3])
        elseif cmd == "CRASHCOST" then
            local limit = tonumber(w[3])
            if limit >= task.base then
                fail("crash limit too large for %s", task.name)
            end
            if limit < task.crashed then
                fail("crash limit below used days for %s", task.name)
            end
            task.crash_limit, task.cost = limit, tonumber(w[4])
            emit("crash %s max %d cost %d", task.name, limit, task.cost)
        elseif cmd == "UNCRASH" then
            emit("uncrash %s restored %d days", task.name, task.crashed)
            task.crashed = 0
        elseif cmd == "PERT" then
            local o, m, p = tonumber(w[3]), tonumber(w[4]), tonumber(w[5])
            if o > m or m > p then
                fail("invalid estimate")
            end
            task.estimate = {o, m, p}
            emit("pert %s expected %s variance %s", task.name, decimal(o + 4 * m + p, 6), decimal((p - o) * (p - o), 36))
        elseif cmd == "IMPACT" then
            local reached, queue, at = {[task.name] = true}, {task.name}, 1
            while at <= #queue do
                local name = queue[at]
                at = at + 1
                for _, dep in ipairs(successors(name)) do
                    if not reached[dep.to] then
                        reached[dep.to], queue[#queue + 1] = true, dep.to
                    end
                end
            end
            reached[task.name] = nil
            local names = keys(reached)
            emit("impact %s: %s", task.name, #names > 0 and table.concat(names, " ") or "none")
        elseif cmd == "SHOW" then
            emit("task %s duration %d resource %s units %d%s", task.name, duration(task.name), task.resource,
                task.units, task.not_before ~= 0 and " notbefore " .. task.not_before or "")
            for _, relation in ipairs({"preds", "succs"}) do
                local deps = relation == "preds" and predecessors(task.name) or successors(task.name)
                local parts = {}
                for _, dep in ipairs(deps) do
                    parts[#parts + 1] = string.format("%s %s%+d", relation == "preds" and dep.from or dep.to, dep.kind, dep.lag)
                end
                emit("%s: %s", relation, #parts > 0 and table.concat(parts, ", ") or "none")
            end
            if task.crash_limit ~= nil then
                emit("crash: max %d used %d cost %d", task.crash_limit, task.crashed, task.cost)
            else
                emit("crash: none")
            end
            if task.estimate then
                emit("pert: %d %d %d", table.unpack(task.estimate))
            else
                emit("pert: none")
            end
            local order, cycle = topology()
            if cycle then
                emit("schedule: unavailable")
            else
                local value = compute(order).times[task.name]
                emit("schedule: ES %d EF %d LS %d LF %d TF %d FF %d%s", value.es, value.ef, value.ls,
                    value.lf, value.tf, value.free, value.tf == 0 and " critical" or "")
            end
        end
        return
    elseif cmd == "CAPACITY" then
        capacities[w[2]] = tonumber(w[3])
        emit("capacity %s %s", w[2], w[3])
        return
    elseif cmd == "START" or cmd == "HOLIDAY" or cmd == "DEADLINE" then
        local date = date_value(w[2])
        if not date then
            fail("invalid date %s", w[2])
        end
        if cmd == "HOLIDAY" then
            if holidays[date] then
                fail("duplicate holiday %s", w[2])
            end
            holidays[date] = true
        elseif cmd == "START" then
            start_date = date
        else
            deadline = date
        end
        emit("%s %s", cmd:lower(), date_text(date))
        return
    elseif cmd == "LIST" then
        local names = keys(tasks)
        emit("tasks %d, dependencies %d, holidays %d", #names, #keys(dependencies), #keys(holidays))
        for _, name in ipairs(names) do
            local task, previous = tasks[name], {}
            for _, dep in ipairs(predecessors(name)) do
                previous[#previous + 1] = dep.from
            end
            emit("%s duration %d resource %s units %d preds %s", name, duration(name), task.resource,
                task.units, #previous > 0 and table.concat(previous, " ") or "none")
        end
        return
    end
    if not next(tasks) then
        fail("no tasks")
    end
    local order, cycle = topology()
    if cycle then
        fail("cycle %s", cycle)
    end
    if cmd == "CALENDAR" and not start_date then
        fail("no start date")
    end
    if cmd == "WHATIF" then
        get(w[2])
    end
    if cmd == "VARIANCE" and not baseline then
        fail("no baseline")
    end
    if cmd == "LOAD" then
        local found = false
        for _, task in pairs(tasks) do
            if task.resource == w[2] then
                found = true
            end
        end
        if not found then
            fail("unknown resource %s", w[2])
        end
    end
    local schedule = compute(order)
    if cmd == "CPM" then
        local width = 4
        for name in pairs(tasks) do
            width = math.max(width, #name)
        end
        local header = string.format("%-" .. width .. "s", "TASK")
        for _, column in ipairs({"DUR", "ES", "EF", "LS", "LF", "TF", "FF"}) do
            header = header .. string.format("%5s", column)
        end
        emit("%s", header)
        for _, name in ipairs(keys(tasks)) do
            local value = schedule.times[name]
            emit("%-" .. width .. "s%5d%5d%5d%5d%5d%5d%5d%s", name, duration(name), value.es,
                value.ef, value.ls, value.lf, value.tf, value.free, value.tf == 0 and " *" or "")
        end
        emit("project duration %d", schedule.total)
    elseif cmd == "CRITICAL" or cmd == "PERTSUM" then
        local paths = critical_paths(schedule)
        if cmd == "CRITICAL" then
            emit("critical paths: %d", #paths)
        end
        for _, path in ipairs(paths) do
            local text = table.concat(path, " -> ")
            if cmd == "CRITICAL" then
                emit("%s", text)
            else
                local expected, variance = 0, 0
                for _, name in ipairs(path) do
                    local d = duration(name)
                    local values = tasks[name].estimate or {d, d, d}
                    expected = expected + values[1] + 4 * values[2] + values[3]
                    variance = variance + (values[3] - values[1]) * (values[3] - values[1])
                end
                emit("%s: expected %s variance %s", text, decimal(expected, 6), decimal(variance, 36))
            end
        end
    elseif cmd == "SLACK" then
        local groups = {}
        for _, name in ipairs(keys(tasks)) do
            local value = schedule.times[name].tf
            groups[value] = groups[value] or {}
            groups[value][#groups[value] + 1] = name
        end
        for _, value in ipairs(keys(groups)) do
            emit("float %d: %s", value, table.concat(groups[value], " "))
        end
    elseif cmd == "DRAG" then
        for _, name in ipairs(critical(schedule)) do
            emit("%s drag %d", name, schedule.total - compute(order, {[name] = 0}).total)
        end
    elseif cmd == "STATS" then
        local counts = {FS = 0, SS = 0, FF = 0}
        for _, dep in pairs(dependencies) do
            counts[dep.kind] = counts[dep.kind] + 1
        end
        local critical_count, names = #critical(schedule), keys(tasks)
        emit("tasks %d, critical %d, dependencies %d (FS %d, SS %d, FF %d)", #names, critical_count,
            #keys(dependencies), counts.FS, counts.SS, counts.FF)
        local work = {}
        for _, resource in ipairs(resources()) do
            local total = 0
            for name, task in pairs(tasks) do
                if task.resource == resource then
                    total = total + duration(name) * task.units
                end
            end
            work[#work + 1] = resource .. " " .. total
        end
        emit("work %s", table.concat(work, ", "))
        local total = 0
        for _, value in pairs(schedule.times) do
            total = total + value.tf
        end
        emit("float total %d, average %s", total, decimal(total, #names))
        emit("duration %d, critical share %s%%", schedule.total, decimal(100 * critical_count, #names))
    elseif cmd == "CALENDAR" then
        calendar(schedule)
    elseif cmd == "GANTT" then
        if schedule.total > 60 then
            fail("chart too wide (%d days)", schedule.total)
        end
        local width = 0
        for name in pairs(tasks) do
            width = math.max(width, #name)
        end
        local header = string.rep(" ", width) .. " |"
        for day = 0, schedule.total - 1 do
            header = header .. day % 10
        end
        emit("%s|", header)
        for _, name in ipairs(start_order(schedule)) do
            local value, bar = schedule.times[name], {}
            for day = 0, schedule.total - 1 do
                if value.es <= day and day < value.ef then
                    bar[#bar + 1] = value.tf == 0 and "=" or "-"
                elseif value.ef <= day and day < value.lf then
                    bar[#bar + 1] = "."
                else
                    bar[#bar + 1] = " "
                end
            end
            emit("%-" .. width .. "s |%s|", name, table.concat(bar))
        end
    elseif cmd == "LEVEL" then
        level(order, schedule, tonumber(w[2]))
    elseif cmd == "LOAD" then
        local values = usage(schedule, w[2])
        local highest, first = peak(values), 1
        while values[first] ~= highest do
            first = first + 1
        end
        emit("load %s: %s", w[2], table.concat(values, " "))
        emit("peak %d on day %d", highest, first - 1)
        if capacities[w[2]] then
            local count = 0
            for _, value in ipairs(values) do
                if value > capacities[w[2]] then
                    count = count + 1
                end
            end
            emit("capacity %d exceeded on %d days", capacities[w[2]], count)
        end
    elseif cmd == "CRASH" then
        local initial, remaining, steps, spent, reason = schedule.total, tonumber(w[2]), 0, 0, nil
        while true do
            schedule = compute(order)
            local chosen
            for _, name in ipairs(critical(schedule)) do
                local task = tasks[name]
                if task.crash_limit and task.crashed < task.crash_limit and
                    compute(order, {[name] = duration(name) - 1}).total < schedule.total then
                    if not chosen or task.cost < tasks[chosen].cost then
                        chosen = name
                    end
                end
            end
            if not chosen then
                reason = "no candidate"
                break
            end
            local task = tasks[chosen]
            if task.cost > remaining then
                reason = "insufficient budget"
                break
            end
            local before = duration(chosen)
            task.crashed, remaining, spent, steps = task.crashed + 1, remaining - task.cost, spent + task.cost, steps + 1
            emit("step %d: %s %d -> %d, cost %d, project %d", steps, chosen, before, before - 1, task.cost, compute(order).total)
        end
        emit("crash done: %d days, cost %d, project %d -> %d, budget left %d, %s", steps, spent,
            initial, schedule.total, remaining, reason)
    elseif cmd == "WHATIF" then
        local after = compute(order, {[w[2]] = tonumber(w[3])})
        emit("whatif %s %d -> %s: project %d -> %d", w[2], duration(w[2]), w[3], schedule.total, after.total)
        for _, name in ipairs(keys(tasks)) do
            local a, b, changes = schedule.times[name], after.times[name], {}
            for _, field in ipairs({"es", "ef", "tf"}) do
                if a[field] ~= b[field] then
                    changes[#changes + 1] = string.format("%s %d->%d", field:upper(), a[field], b[field])
                end
            end
            if #changes > 0 then
                emit("%s %s", name, table.concat(changes, " "))
            end
        end
        local before_names, after_names = table.concat(critical(schedule), " "), table.concat(critical(after), " ")
        if before_names ~= after_names then
            emit("critical %s -> %s", before_names, after_names)
        end
    elseif cmd == "BASELINE" then
        baseline = {total = schedule.total, times = {}}
        for name, value in pairs(schedule.times) do
            baseline.times[name] = {es = value.es, ef = value.ef}
        end
        emit("baseline saved: %d tasks, duration %d", #keys(tasks), schedule.total)
    elseif cmd == "VARIANCE" then
        emit("variance: duration %d -> %d (%+d)", baseline.total, schedule.total, schedule.total - baseline.total)
        local names, count = {}, 0
        for name in pairs(baseline.times) do
            names[name] = true
        end
        for name in pairs(tasks) do
            names[name] = true
        end
        for _, name in ipairs(keys(names)) do
            local a, b = baseline.times[name], schedule.times[name]
            if not b then
                emit("%s removed", name)
                count = count + 1
            elseif not a then
                emit("%s new", name)
                count = count + 1
            elseif a.es ~= b.es or a.ef ~= b.ef then
                emit("%s start %+d finish %+d", name, b.es - a.es, b.ef - a.ef)
                count = count + 1
            end
        end
        if count == 0 then
            emit("no task changes")
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    local words = {}
    for word in io.read("*l"):gmatch("[^ ]+") do
        words[#words + 1] = word
    end
    local ok, message = pcall(command, words)
    if not ok then
        emit("error: %s", message)
    end
end
io.write(table.concat(output, "\n"), "\n")
