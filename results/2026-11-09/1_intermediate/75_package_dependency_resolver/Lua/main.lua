local registry, parsed, installed, held, advisories = {}, {}, {}, {}, {}
local requests, history, output = {}, {}, {}
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
local function split(text, separator, limit)
    local result, start = {}, 1
    while not limit or #result + 1 < limit do
        local at = text:find(separator, start, true)
        if not at then
            break
        end
        result[#result + 1] = text:sub(start, at - 1)
        start = at + #separator
    end
    result[#result + 1] = text:sub(start)
    return result
end
local function copy(items)
    local result = {}
    for key, value in pairs(items) do
        result[key] = value
    end
    return result
end
local function copy_requests(items)
    local result = {}
    for i, pair in ipairs(items) do
        result[i] = {name = pair.name, text = pair.text}
    end
    return result
end
local function numeric(text)
    return text ~= "" and not text:find("[^0-9]")
end
local function number_word(text)
    return #text >= 1 and #text <= 4 and numeric(text) and (#text == 1 or text:sub(1, 1) ~= "0")
end
local function make_version(core, pre)
    local text = table.concat(core, ".")
    if #pre > 0 then
        text = text .. "-" .. table.concat(pre, ".")
    end
    return {core = core, pre = pre, text = text}
end
local function parse_version(text)
    local fields = split(text, "-", 2)
    local parts, core, pre = split(fields[1], "."), {}, {}
    if #parts ~= 3 then
        return nil
    end
    for i, part in ipairs(parts) do
        if not number_word(part) then
            return nil
        end
        core[i] = tonumber(part)
    end
    if fields[2] then
        pre = split(fields[2], ".")
        for _, part in ipairs(pre) do
            if part == "" or part:find("[^a-z0-9]") or numeric(part) and not number_word(part) then
                return nil
            end
        end
    end
    return make_version(core, pre)
end
local function compare(a, b)
    for i = 1, 3 do
        if a.core[i] ~= b.core[i] then
            return a.core[i] < b.core[i] and -1 or 1
        end
    end
    if #a.pre == 0 and #b.pre > 0 then
        return 1
    elseif #b.pre == 0 and #a.pre > 0 then
        return -1
    end
    for i = 1, math.min(#a.pre, #b.pre) do
        local x, y = a.pre[i], b.pre[i]
        if x ~= y then
            local nx, ny = numeric(x), numeric(y)
            if nx and ny then
                return tonumber(x) < tonumber(y) and -1 or 1
            elseif nx ~= ny then
                return nx and -1 or 1
            end
            return x < y and -1 or 1
        end
    end
    return #a.pre == #b.pre and 0 or #a.pre < #b.pre and -1 or 1
end
local function parse_constraint(text)
    local result, forms = {alternatives = {}}, {}
    for _, branch in ipairs(split(text, " || ")) do
        local item = {comparisons = {}, prerelease = {}}
        for _, term in ipairs(split(branch, " ")) do
            if term == "" then
                return nil
            end
            local op, pattern = "", term
            for _, candidate in ipairs({">=", "<=", ">", "<", "=", "^", "~"}) do
                if term:sub(1, #candidate) == candidate then
                    op, pattern = candidate, term:sub(#candidate + 1)
                    break
                end
            end
            local core, pre, count = {0, 0, 0}, {}, 0
            if pattern:find("-", 1, true) then
                local value = parse_version(pattern)
                if not value or #value.pre == 0 then
                    return nil
                end
                core, pre, count = value.core, value.pre, 3
                item.prerelease[table.concat(core, ".")] = true
            else
                local parts, wildcard = split(pattern, "."), false
                if #parts > 3 then
                    return nil
                end
                for i, part in ipairs(parts) do
                    if part == "x" or part == "*" then
                        wildcard = true
                    else
                        if wildcard or not number_word(part) then
                            return nil
                        end
                        core[i], count = tonumber(part), count + 1
                    end
                end
            end
            local lower = make_version(core, pre)
            local function upper(at)
                local next_core = copy(core)
                next_core[at] = next_core[at] + 1
                for i = at + 1, 3 do
                    next_core[i] = 0
                end
                return make_version(next_core, {})
            end
            local function add(operator, value)
                item.comparisons[#item.comparisons + 1] = {op = operator, value = value}
            end
            if count == 0 then
                if op == ">" or op == "<" then
                    add("<", make_version({0, 0, 0}, {"0"}))
                end
            elseif op == "" or op == "=" then
                if count == 3 then
                    add("=", lower)
                else
                    add(">=", lower)
                    add("<", upper(count))
                end
            elseif op == ">" then
                add(count == 3 and ">" or ">=", count == 3 and lower or upper(count))
            elseif op == "<=" then
                add(count == 3 and "<=" or "<", count == 3 and lower or upper(count))
            elseif op == ">=" or op == "<" then
                add(op, lower)
            elseif op == "~" then
                add(">=", lower)
                add("<", upper(count == 1 and 1 or 2))
            elseif op == "^" then
                local at
                if core[1] ~= 0 or count == 1 then
                    at = 1
                elseif core[2] ~= 0 or count == 2 then
                    at = 2
                else
                    at = 3
                end
                add(">=", lower)
                add("<", upper(at))
            end
        end
        local words = {}
        for _, comparator in ipairs(item.comparisons) do
            words[#words + 1] = comparator.op .. comparator.value.text
        end
        forms[#forms + 1] = #words > 0 and table.concat(words, " ") or "*"
        result.alternatives[#result.alternatives + 1] = item
    end
    result.normal = table.concat(forms, " || ")
    return result
end
local function constraint(text)
    if not parsed[text] then
        parsed[text] = parse_constraint(text)
        if not parsed[text] then
            fail("invalid constraint '%s'", text)
        end
    end
    return parsed[text]
end
local function checked_version(text)
    local value = parse_version(text)
    if not value then
        fail("invalid version '%s'", text)
    end
    return value
end
local function matches(value, text)
    for _, branch in ipairs(parsed[text].alternatives) do
        if #value.pre == 0 or branch.prerelease[table.concat(value.core, ".")] then
            local valid = true
            for _, comparator in ipairs(branch.comparisons) do
                local order, op = compare(value, comparator.value), comparator.op
                valid = op == "=" and order == 0 or op == ">" and order > 0 or op == ">=" and order >= 0 or
                    op == "<" and order < 0 or op == "<=" and order <= 0
                if not valid then
                    break
                end
            end
            if valid then
                return true
            end
        end
    end
    return false
end
local function find(name, text)
    for _, value in ipairs(registry[name] or {}) do
        if value.version.text == text then
            return value
        end
    end
    return nil
end
local function label(value)
    return value.name .. "@" .. value.version.text
end
local function applicable(value)
    local result = {}
    for _, id in ipairs(keys(advisories)) do
        local advisory = advisories[id]
        if advisory.name == value.name and matches(value.version, advisory.text) then
            result[#result + 1] = id
        end
    end
    return result
end
local function usable(value, audit)
    return (not value.yanked or installed[value.name] == value) and (not audit or #applicable(value) == 0)
end
local function display(value)
    local flags = {}
    if value.yanked then
        flags[#flags + 1] = "yanked"
    end
    if installed[value.name] == value then
        flags[#flags + 1] = "installed"
    end
    return label(value) .. (#flags > 0 and " (" .. table.concat(flags, ", ") .. ")" or "")
end
local function resolve(new_requests, preferred, audit)
    local selected, origins, failure, depth = {}, {}, nil, -1
    local function record(requirement, reason, extra)
        local count = #keys(selected)
        if count <= depth then
            return
        end
        depth, failure = count, {"UNSATISFIABLE"}
        for _, line in ipairs(requirement.chain) do
            failure[#failure + 1] = "  " .. line
        end
        failure[#failure + 1] = "  " .. reason
        for _, line in ipairs(extra or {}) do
            failure[#failure + 1] = "    " .. line
        end
    end
    local function search(todo)
        if #todo == 0 then
            return true
        end
        local requirement, rest = todo[1], {}
        for i = 2, #todo do
            rest[#rest + 1] = todo[i]
        end
        local name, text = requirement.name, requirement.text
        if selected[name] then
            if matches(selected[name].version, text) then
                return search(rest)
            end
            record(requirement, label(selected[name]) .. " was selected by:", origins[name].chain)
            return false
        end
        local candidates = {}
        if held[name] then
            local value = installed[name]
            if matches(value.version, text) and usable(value, audit) then
                candidates[1] = value
            else
                record(requirement, label(value) .. " is held")
                return false
            end
        else
            for _, value in ipairs(registry[name] or {}) do
                if matches(value.version, text) and usable(value, audit) then
                    candidates[#candidates + 1] = value
                end
            end
            if preferred[name] then
                for i, value in ipairs(candidates) do
                    if installed[name] == value then
                        table.remove(candidates, i)
                        table.insert(candidates, 1, value)
                        break
                    end
                end
            end
            if #candidates == 0 then
                record(requirement, "no version of " .. name .. " matches " .. text)
                return false
            end
        end
        for _, candidate in ipairs(candidates) do
            local conflicting
            for _, other_name in ipairs(keys(selected)) do
                local chosen, conflict = selected[other_name], false
                for _, pair in ipairs(candidate.conflicts) do
                    if pair.name == other_name and matches(chosen.version, pair.text) then
                        conflict = true
                        break
                    end
                end
                if not conflict then
                    for _, pair in ipairs(chosen.conflicts) do
                        if pair.name == name and matches(candidate.version, pair.text) then
                            conflict = true
                            break
                        end
                    end
                end
                if conflict then
                    conflicting = other_name
                    break
                end
            end
            if conflicting then
                record(requirement, label(candidate) .. " conflicts with " .. label(selected[conflicting]) ..
                    ", which was selected by:", origins[conflicting].chain)
            else
                selected[name], origins[name] = candidate, requirement
                local following = {}
                for _, pair in ipairs(candidate.dependencies) do
                    local chain = copy(requirement.chain)
                    chain[#chain + 1] = label(candidate) .. " requires " .. pair.name .. " " .. pair.text
                    following[#following + 1] = {name = pair.name, text = pair.text, chain = chain}
                end
                for _, item in ipairs(rest) do
                    following[#following + 1] = item
                end
                if search(following) then
                    return true
                end
                selected[name], origins[name] = nil, nil
            end
        end
        return false
    end
    local initial = {}
    for _, pair in ipairs(new_requests) do
        initial[#initial + 1] = {name = pair.name, text = pair.text, chain = {"requested " .. pair.name .. " " .. pair.text}}
    end
    if search(initial) then
        return selected, nil
    end
    return nil, failure
end
local function report_failure(lines)
    for _, line in ipairs(lines) do
        emit("%s", line)
    end
end
local function plan(next_installed)
    local arranged, added, upgraded, downgraded, removed = {}, 0, 0, 0, 0
    local names = keys(next_installed)
    while #keys(arranged) < #names do
        for _, name in ipairs(names) do
            if not arranged[name] then
                local ready = true
                for _, pair in ipairs(next_installed[name].dependencies) do
                    if not arranged[pair.name] then
                        ready = false
                        break
                    end
                end
                if ready then
                    local value, old = next_installed[name], installed[name]
                    if not old then
                        emit("install %s", label(value))
                        added = added + 1
                    elseif old ~= value then
                        if compare(value.version, old.version) > 0 then
                            emit("upgrade %s %s -> %s", name, old.version.text, value.version.text)
                            upgraded = upgraded + 1
                        else
                            emit("downgrade %s %s -> %s", name, old.version.text, value.version.text)
                            downgraded = downgraded + 1
                        end
                    end
                    arranged[name] = true
                    break
                end
            end
        end
    end
    local dropping = {}
    for name in pairs(installed) do
        if not next_installed[name] then
            dropping[name] = true
        end
    end
    while next(dropping) do
        for _, name in ipairs(keys(dropping)) do
            local ready = true
            for other in pairs(dropping) do
                for _, pair in ipairs(installed[other].dependencies) do
                    if pair.name == name then
                        ready = false
                        break
                    end
                end
                if not ready then
                    break
                end
            end
            if ready then
                emit("remove %s", label(installed[name]))
                dropping[name], removed = nil, removed + 1
                break
            end
        end
    end
    if added + upgraded + downgraded + removed == 0 then
        emit("no changes")
    else
        emit("%d installed, %d upgraded, %d downgraded, %d removed", added, upgraded, downgraded, removed)
    end
end
local function update(new_requests, new_installed, save)
    if save then
        history[#history + 1] = {requests = copy_requests(requests), installed = copy(installed)}
    end
    requests, installed = copy_requests(new_requests), copy(new_installed)
    for name in pairs(held) do
        if not installed[name] then
            held[name] = nil
        end
    end
end
local function parent(name)
    for _, candidate in ipairs(keys(installed)) do
        for _, pair in ipairs(installed[candidate].dependencies) do
            if pair.name == name then
                return candidate
            end
        end
    end
end
local function requested(name)
    for _, pair in ipairs(requests) do
        if pair.name == name then
            return pair.text
        end
    end
end
local function tree(root, seen, text, prefix, indent)
    local value = installed[root]
    local body = prefix .. label(value) .. (text and " [" .. text .. "]" or "")
    if seen[root] then
        emit("%s (*)", body)
        return
    end
    emit("%s", body)
    seen[root] = true
    for i, pair in ipairs(value.dependencies) do
        local mark, following = "|-- ", "|   "
        if i == #value.dependencies then
            mark, following = "`-- ", "    "
        end
        tree(pair.name, seen, pair.text, indent .. mark, indent .. following)
    end
end
local function all_preferred()
    local preferred = {}
    for name in pairs(installed) do
        preferred[name] = true
    end
    return preferred
end

local function command(line)
    local w = split(line, " ")
    local cmd = w[1]
    if cmd == "PKG" then
        local clauses = split(line, "; ")
        local head = split(clauses[1], " ")
        local value = checked_version(head[3])
        if find(head[2], head[3]) then
            fail("%s@%s is already registered", head[2], head[3])
        end
        local candidate = {name = head[2], version = value, dependencies = {}, conflicts = {}}
        for i = 2, #clauses do
            local parts = split(clauses[i], " ", 3)
            constraint(parts[3])
            local list = parts[1] == "DEP" and candidate.dependencies or candidate.conflicts
            list[#list + 1] = {name = parts[2], text = parts[3]}
        end
        registry[candidate.name] = registry[candidate.name] or {}
        table.insert(registry[candidate.name], candidate)
        table.sort(registry[candidate.name], function(a, b) return compare(a.version, b.version) > 0 end)
        emit("registered %s", label(candidate))
    elseif cmd == "YANK" or cmd == "INFO" then
        local value = find(w[2], w[3])
        if not value then
            fail("%s@%s is not registered", w[2], w[3])
        end
        if cmd == "YANK" then
            if value.yanked then
                fail("%s is already yanked", label(value))
            end
            value.yanked = true
            emit("yanked %s", label(value))
        else
            emit("%s", display(value))
            for _, pair in ipairs(value.dependencies) do
                emit("  requires %s %s", pair.name, pair.text)
            end
            for _, pair in ipairs(value.conflicts) do
                emit("  conflicts with %s %s", pair.name, pair.text)
            end
            for _, id in ipairs(applicable(value)) do
                emit("  advisory %s", id)
            end
        end
    elseif cmd == "COMPARE" then
        local a = checked_version(w[2])
        local b = checked_version(w[3])
        local relation = compare(a, b)
        emit("%s %s %s", w[2], relation < 0 and "<" or relation > 0 and ">" or "=", w[3])
    elseif cmd == "MATCH" then
        local parts = split(line, " ", 3)
        local value = checked_version(parts[2])
        constraint(parts[3])
        emit("%s", matches(value, parts[3]) and "yes" or "no")
    elseif cmd == "RANGE" then
        emit("%s", constraint(line:sub(7)).normal)
    elseif cmd == "VERSIONS" or cmd == "INSTALL" or cmd == "SIMULATE" then
        local parts = split(line, " ", 3)
        local text = parts[3] or "*"
        constraint(text)
        if not registry[w[2]] then
            fail("unknown package %s", w[2])
        end
        if cmd == "VERSIONS" then
            local count = 0
            for _, value in ipairs(registry[w[2]]) do
                if not parts[3] or matches(value.version, text) then
                    emit("%s", display(value))
                    count = count + 1
                end
            end
            if count == 0 then
                emit("no matching versions")
            end
        else
            local new_requests, found = copy_requests(requests), false
            for _, pair in ipairs(new_requests) do
                if pair.name == w[2] then
                    pair.text, found = text, true
                    break
                end
            end
            if not found then
                new_requests[#new_requests + 1] = {name = w[2], text = text}
            end
            local next_installed, failure = resolve(new_requests, all_preferred(), false)
            if failure then
                report_failure(failure)
            else
                plan(next_installed)
                if cmd == "INSTALL" then
                    update(new_requests, next_installed, true)
                end
            end
        end
    elseif cmd == "DEPENDENTS" then
        local selected = w[3] and checked_version(w[3]) or nil
        local count = 0
        for _, name in ipairs(keys(registry)) do
            for _, value in ipairs(registry[name]) do
                for _, pair in ipairs(value.dependencies) do
                    if pair.name == w[2] and (not selected or matches(selected, pair.text)) then
                        emit("%s requires %s %s", label(value), w[2], pair.text)
                        count = count + 1
                    end
                end
            end
        end
        if count == 0 then
            emit("no dependents")
        end
    elseif cmd == "REMOVE" then
        if not requested(w[2]) then
            if installed[w[2]] then
                fail("%s is required by %s", w[2], parent(w[2]))
            end
            fail("%s is not installed", w[2])
        end
        local new_requests, keep, queue = {}, {}, {}
        for _, pair in ipairs(requests) do
            if pair.name ~= w[2] then
                new_requests[#new_requests + 1], queue[#queue + 1] = pair, pair.name
            end
        end
        local at = 1
        while at <= #queue do
            local name = queue[at]
            at = at + 1
            if not keep[name] then
                keep[name] = installed[name]
                for _, pair in ipairs(installed[name].dependencies) do
                    queue[#queue + 1] = pair.name
                end
            end
        end
        if keep[w[2]] then
            emit("%s is still required by %s", label(installed[w[2]]), parent(w[2]))
            update(new_requests, installed, true)
        else
            plan(keep)
            update(new_requests, keep, true)
        end
    elseif cmd == "UPGRADE" then
        if w[2] and not installed[w[2]] then
            fail("%s is not installed", w[2])
        end
        local preferred = w[2] and all_preferred() or {}
        if w[2] then
            preferred[w[2]] = nil
        end
        local next_installed, failure = resolve(requests, preferred, false)
        if failure then
            report_failure(failure)
        else
            plan(next_installed)
            update(requests, next_installed, true)
        end
    elseif cmd == "ROLLBACK" then
        if #history == 0 then
            fail("nothing to roll back")
        end
        local saved = table.remove(history)
        plan(saved.installed)
        update(saved.requests, saved.installed, false)
    elseif cmd == "HOLD" then
        if not installed[w[2]] then
            fail("%s is not installed", w[2])
        end
        if held[w[2]] then
            fail("%s is already held", w[2])
        end
        held[w[2]] = true
        emit("held %s", label(installed[w[2]]))
    elseif cmd == "UNHOLD" then
        if not held[w[2]] then
            fail("%s is not held", w[2])
        end
        held[w[2]] = nil
        emit("released %s", w[2])
    elseif cmd == "WHY" then
        local value = installed[w[2]]
        if not value then
            fail("%s is not installed", w[2])
        end
        if requested(w[2]) then
            emit("%s is explicitly installed", label(value))
            return
        end
        local previous, seen, queue, roots = {}, {}, {}, {}
        for _, pair in ipairs(requests) do
            roots[pair.name] = true
        end
        for _, name in ipairs(keys(roots)) do
            queue[#queue + 1], seen[name] = name, true
        end
        local at = 1
        while at <= #queue do
            local name, deps = queue[at], {}
            at = at + 1
            for _, pair in ipairs(installed[name].dependencies) do
                deps[pair.name] = true
            end
            for _, dep in ipairs(keys(deps)) do
                if not seen[dep] then
                    seen[dep], previous[dep], queue[#queue + 1] = true, name, dep
                end
            end
        end
        local path, name = {}, w[2]
        while name do
            table.insert(path, 1, label(installed[name]))
            name = previous[name]
        end
        emit("%s", table.concat(path, " -> "))
    elseif cmd == "TREE" then
        if w[2] and not installed[w[2]] then
            fail("%s is not installed", w[2])
        end
        local roots = {}
        if w[2] then
            roots[1] = w[2]
        else
            for _, pair in ipairs(requests) do
                roots[#roots + 1] = pair.name
            end
            table.sort(roots)
        end
        if #roots == 0 then
            emit("(empty)")
        end
        local seen = {}
        for _, name in ipairs(roots) do
            tree(name, seen, requested(name), "", "")
        end
    elseif cmd == "OUTDATED" then
        local count = 0
        for _, name in ipairs(keys(installed)) do
            local current, conditions = installed[name], {}
            local text = requested(name)
            if text then
                conditions[#conditions + 1] = text
            end
            for _, value in pairs(installed) do
                for _, pair in ipairs(value.dependencies) do
                    if pair.name == name then
                        conditions[#conditions + 1] = pair.text
                    end
                end
            end
            local wanted, latest
            for _, value in ipairs(registry[name]) do
                if not value.yanked and #value.version.pre == 0 and not latest then
                    latest = value
                end
                if not wanted and (not value.yanked or value == current) then
                    local valid = true
                    for _, condition in ipairs(conditions) do
                        if not matches(value.version, condition) then
                            valid = false
                            break
                        end
                    end
                    if valid then
                        wanted = value
                    end
                end
            end
            if wanted ~= current or latest and compare(latest.version, current.version) > 0 then
                emit("%s %s %s %s", name, current.version.text, wanted.version.text, latest and latest.version.text or "-")
                count = count + 1
            end
        end
        if count == 0 then
            emit("all packages are up to date")
        end
    elseif cmd == "LOCK" then
        if not next(installed) then
            emit("(empty)")
        end
        for _, name in ipairs(keys(installed)) do
            emit("%s", label(installed[name]))
        end
    elseif cmd == "STATUS" then
        if #requests == 0 then
            emit("no requests")
        end
        for _, pair in ipairs(requests) do
            emit("%s %s -> %s", pair.name, pair.text, installed[pair.name].version.text)
        end
        emit("%d installed, %d held, %d snapshots", #keys(installed), #keys(held), #history)
    elseif cmd == "ADVISORY" then
        local parts = split(line, " ", 4)
        if advisories[w[2]] then
            fail("advisory %s already exists", w[2])
        end
        constraint(parts[4])
        advisories[w[2]] = {name = w[3], text = parts[4]}
        emit("advisory %s recorded", w[2])
    elseif cmd == "AUDIT" then
        if w[2] then
            local next_installed, failure = resolve(requests, all_preferred(), true)
            if failure then
                report_failure(failure)
            else
                plan(next_installed)
                update(requests, next_installed, true)
            end
        else
            local count = 0
            for _, name in ipairs(keys(installed)) do
                local current = installed[name]
                local ids = applicable(current)
                if #ids > 0 then
                    local fix
                    for i = #registry[name], 1, -1 do
                        local value = registry[name][i]
                        if compare(value.version, current.version) > 0 and #value.version.pre == 0 and
                            not value.yanked and #applicable(value) == 0 then
                            fix = value
                            break
                        end
                    end
                    emit("%s: %s (%s)", label(current), table.concat(ids, ", "), fix and "fix: " .. fix.version.text or "no fix")
                    count = count + 1
                end
            end
            if count == 0 then
                emit("no known vulnerabilities")
            end
        end
    end
end

local count = tonumber(io.read("*l"))
for _ = 1, count do
    local ok, message = pcall(command, io.read("*l"))
    if not ok then
        emit("error: %s", message)
    end
end
io.write(table.concat(output, "\n"), "\n")
