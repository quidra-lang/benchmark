local function copy(value)
    if type(value) ~= 'table' then return value end
    local result = {}
    for k, v in pairs(value) do result[k] = copy(v) end
    return result
end
local function vec(v) return '(' .. table.concat(v, ',') .. ')' end
local function names(ids)
    local result = {}
    for _, id in ipairs(ids) do result[#result + 1] = 'P' .. id end
    return table.concat(result, ' ')
end
local function add(a, b)
    local result = {}
    for i, x in ipairs(a) do result[i] = x + b[i] end
    return result
end
local function sub(a, b)
    local result = {}
    for i, x in ipairs(a) do result[i] = x - b[i] end
    return result
end
local function fits(a, b)
    for i, x in ipairs(a) do if x > b[i] then return false end end
    return true
end
local function sum(a)
    local result = 0
    for _, x in ipairs(a) do result = result + x end
    return result
end
local function sortedKeys(a)
    local result = {}
    for k in pairs(a) do result[#result + 1] = k end
    table.sort(result)
    return result
end
local function lexLess(a, b)
    for i = 1, math.min(#a, #b) do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return #a < #b
end
local total, available, processes, queue, history = {}, {}, {}, {}, {}
local mode, policy, trace, autodetect = 'AVOID', 'ALLOC', false, false
local snapshots, time = {}, 0
local kinds = {'granted','blocked','unblocked','released','finished','aborted','cancelled'}
local function zero()
    local result = {}
    for i = 1, #total do result[i] = 0 end
    return result
end
local function need(id, ps)
    local p = (ps or processes)[id]
    return sub(p.max, p.alloc)
end
local function blocked(id, qs)
    for _, q in ipairs(qs or queue) do if q[1] == id then return q end end
end
local function check(detect, tracing, av, ps, qs)
    ps, qs = ps or processes, qs or queue
    local work = copy(av or available)
    local remaining, idle, sequence = {}, {}, {}
    for _, id in ipairs(sortedKeys(ps)) do
        local dest = detect and sum(ps[id].alloc) == 0 and idle or remaining
        dest[#dest + 1] = id
    end
    local label = detect and 'detect' or 'safety'
    if tracing then
        local suffix = #idle > 0 and ' idle ' .. names(idle) or ''
        print('[' .. label .. '] start work=' .. vec(work) .. suffix)
    end
    while true do
        local index
        for i, id in ipairs(remaining) do
            local q = blocked(id, qs)
            local required = detect and (q and q[2] or zero()) or need(id, ps)
            if fits(required, work) then index = i; break end
        end
        if not index then break end
        local id = table.remove(remaining, index)
        work = add(work, ps[id].alloc)
        sequence[#sequence + 1] = id
        if tracing then print('[' .. label .. '] P' .. id .. ' can finish, work=' .. vec(work)) end
    end
    if tracing and #remaining > 0 then
        print('[' .. label .. '] stuck work=' .. vec(work) .. ' remaining ' .. names(remaining))
    end
    return #remaining == 0, sequence, remaining
end
local function reject(id, v)
    if blocked(id) then return 'process P' .. id .. ' is blocked' end
    if sum(v) == 0 then return 'zero vector' end
    if not fits(v, need(id)) then return 'request exceeds need' end
    local last = 0
    for i, x in ipairs(processes[id].alloc) do if x > 0 then last = i end end
    if mode == 'ORDER' then
        for i, x in ipairs(v) do if x > 0 and i <= last then return 'resource order violation' end end
    end
end
local function decision(id, v, tracing)
    if not fits(v, available) then return false, 'insufficient resources', {} end
    if mode == 'AVOID' then
        local ps = copy(processes)
        ps[id].alloc = add(ps[id].alloc, v)
        local safe, sequence = check(false, tracing, sub(available, v), ps)
        if not safe then return false, 'unsafe state', {} end
        return true, '', sequence
    end
    return true, '', {}
end
local function record(kind, id, v, wait)
    history[#history + 1] = {time, kind, id, copy(v), wait}
end
local function grant(id, v)
    available = sub(available, v)
    processes[id].alloc = add(processes[id].alloc, v)
end
local function retryQueue()
    local old = queue
    queue = {}
    for _, q in ipairs(old) do
        local id, v, since = q[1], q[2], q[3]
        if decision(id, v, trace) then
            grant(id, v)
            print('unblocked P' .. id .. ' ' .. vec(v))
            record('unblocked', id, v, time - since)
        else queue[#queue + 1] = q end
    end
end
local function removeRequest(id)
    for i = #queue, 1, -1 do if queue[i][1] == id then table.remove(queue, i) end end
end
local function terminate(id, kind, retryAfter)
    local allocation = processes[id].alloc
    available = add(available, allocation)
    processes[id] = nil
    removeRequest(id)
    print(kind .. ' P' .. id .. ' released ' .. vec(allocation))
    record(kind, id, allocation)
    if retryAfter then retryQueue() end
end
local function requireThat(valid, message)
    if not valid then error(message, 0) end
end
local function graph(single)
    if single then for _, x in ipairs(total) do requireThat(x == 1, 'not single-instance') end end
    local ids, edges, edgeCount = sortedKeys(processes), {}, 0
    for _, p in ipairs(ids) do edges[p] = {} end
    if single then
        for i = 1, #total do
            for _, p in ipairs(ids) do
                if processes[p].alloc[i] > 0 then print('assign ' .. string.char(64+i) .. ' -> P' .. p) end
            end
        end
        for _, p in ipairs(ids) do
            local q = blocked(p)
            if q then
                for i, x in ipairs(q[2]) do
                    if x > 0 then
                        print('request P' .. p .. ' -> ' .. string.char(64+i))
                        for _, j in ipairs(ids) do
                            if processes[j].alloc[i] > 0 then edges[p][#edges[p]+1] = {i,j} end
                        end
                    end
                end
            end
        end
        for _, p in ipairs(ids) do
            local q = blocked(p)
            for i, x in ipairs(need(p)) do
                if x > 0 and (not q or q[2][i] == 0) then print('claim P' .. p .. ' -> ' .. string.char(64+i)) end
            end
        end
    else
        for _, p in ipairs(ids) do
            local q = blocked(p)
            if q then
                for _, j in ipairs(ids) do
                    if j ~= p then
                        local labels = {}
                        for i, x in ipairs(q[2]) do
                            if x > available[i] and processes[j].alloc[i] > 0 then labels[#labels+1] = string.char(64+i) end
                        end
                        if #labels > 0 then
                            print('P' .. p .. ' -> P' .. j .. ' on ' .. table.concat(labels, ','))
                            edges[p][#edges[p]+1] = {j,j}
                            edgeCount = edgeCount + 1
                        end
                    end
                end
            end
        end
        if edgeCount == 0 then print('no wait edges') end
    end
    local cycles = {}
    for _, start in ipairs(ids) do
        local function visit(p, seen, path)
            for _, e in ipairs(edges[p]) do
                local label, nextId = e[1], e[2]
                local nextPath = copy(path)
                if single then nextPath[#nextPath+1] = label end
                nextPath[#nextPath+1] = nextId
                if nextId == start then
                    if single or #path >= 2 then cycles[#cycles+1] = nextPath end
                elseif nextId > start and not seen[nextId] then
                    local nextSeen = copy(seen)
                    nextSeen[nextId] = true
                    visit(nextId, nextSeen, nextPath)
                end
            end
        end
        visit(start, {[start]=true}, {start})
    end
    table.sort(cycles, lexLess)
    for _, path in ipairs(cycles) do
        local text = {}
        for i, x in ipairs(path) do text[i] = single and i%2 == 0 and string.char(64+x) or 'P' .. x end
        print('cycle: ' .. table.concat(text, ' -> '))
    end
    if #cycles == 0 then print('no cycles') end
end
local function stateTable()
    local widths = {}
    for i, x in ipairs(total) do widths[i] = #tostring(x) end
    local function tableForm(v)
        local a = {}
        for i, x in ipairs(v) do a[i] = string.format('%' .. widths[i] .. 's', tostring(x)) end
        return table.concat(a, ' ')
    end
    local letters = {}
    for i = 1, #total do letters[i] = string.char(64+i) end
    local name = tableForm(letters)
    local columns = {math.max(10,#name),math.max(3,#name),math.max(4,#name),math.max(7,#name)}
    local function row(heading, content)
        local s = string.format('%-9s', heading)
        for i, x in ipairs(content) do s = s .. '  ' .. string.format('%-' .. columns[i] .. 's', x) end
        print((s:gsub('%s+$', '')))
    end
    row('Process', {'Allocation','Max','Need','Request'})
    row('', {name,name,name,name})
    for _, p in ipairs(sortedKeys(processes)) do
        local q = blocked(p)
        row('P'..p, {tableForm(processes[p].alloc),tableForm(processes[p].max),tableForm(need(p)),tableForm(q and q[2] or zero())})
    end
    row('Available', {tableForm(available),'','',''})
    row('Total', {tableForm(total),'','',''})
    local requests = {}
    for _, q in ipairs(queue) do requests[#requests+1] = 'P' .. q[1] .. ' ' .. vec(q[2]) .. ' since t=' .. q[3] end
    print('blocked queue: ' .. (#requests > 0 and table.concat(requests, ', ') or 'empty'))
end
local function statistics()
    for i, t in ipairs(total) do
        local used, requested = t - available[i], 0
        for _, q in ipairs(queue) do requested = requested + q[2][i] end
        local percent = used * 1000 // t
        print(string.char(64+i) .. ': allocated ' .. used .. '/' .. t .. ' (' .. percent//10 .. '.' .. percent%10 .. '%), requested ' .. requested)
    end
    local counts, waits, waitSum = {}, 0, 0
    for _, k in ipairs(kinds) do counts[k] = 0 end
    for _, e in ipairs(history) do
        counts[e[2]] = counts[e[2]] + 1
        if e[2] == 'unblocked' then waits, waitSum = waits+1, waitSum+e[5] end
    end
    local parts = {}
    for _, k in ipairs(kinds) do parts[#parts+1] = k .. ' ' .. counts[k] end
    print('events: ' .. table.concat(parts, ', '))
    if waits == 0 then print('waits: none')
    else
        local avg = waitSum*100//waits
        print('waits: ' .. waits .. ' unblocked, total ' .. waitSum .. ', average ' .. avg//100 .. '.' .. string.format('%02d',avg%100))
    end
end
local function run(line)
    local words = {}
    for word in line:gmatch('%S+') do words[#words+1] = word end
    local cmd = table.remove(words,1)
    local id = tonumber(words[1]) or 0
    local withId = cmd == 'PROCESS' or cmd == 'CLAIM' or cmd == 'REQUEST' or cmd == 'WHATIF' or cmd == 'RELEASE'
    local v = {}
    for i = withId and 2 or 1, #words do v[#v+1] = tonumber(words[i]) end
    if withId or cmd == 'ADD' or cmd == 'REMOVE' then requireThat(#v == #total, 'wrong vector length') end
    if cmd == 'CLAIM' or cmd == 'REQUEST' or cmd == 'WHATIF' or cmd == 'RELEASE' or cmd == 'FINISH' or cmd == 'ABORT' or cmd == 'CANCEL' or cmd == 'MAXGRANT' then
        requireThat(processes[id] ~= nil, 'unknown process P' .. id)
    end
    if cmd == 'RESOURCES' then
        total, available, processes, queue, history = copy(v), copy(v), {}, {}, {}
        print('resources ' .. vec(v))
    elseif cmd == 'MODE' or cmd == 'POLICY' or cmd == 'TRACE' or cmd == 'AUTODETECT' then
        if cmd == 'MODE' then mode = words[1]
        elseif cmd == 'POLICY' then policy = words[1]
        elseif cmd == 'TRACE' then trace = words[1] == 'ON'
        else autodetect = words[1] == 'ON' end
        print(cmd:lower() .. ' ' .. words[1])
    elseif cmd == 'PROCESS' then
        requireThat(not processes[id], 'duplicate process P' .. id)
        requireThat(fits(v,total), 'max exceeds total')
        processes[id] = {max=v,alloc=zero(),born=time}
        print('process P' .. id .. ' max ' .. vec(v))
    elseif cmd == 'CLAIM' then
        requireThat(not blocked(id), 'process P' .. id .. ' is blocked')
        requireThat(fits(processes[id].alloc,v), 'claim below allocation')
        requireThat(fits(v,total), 'max exceeds total')
        if mode == 'AVOID' then
            local ps = copy(processes)
            ps[id].max = v
            requireThat(check(false,trace,available,ps), 'claim makes state unsafe')
        end
        processes[id].max = v
        print('claim P' .. id .. ' max ' .. vec(v))
        retryQueue()
    elseif cmd == 'ADD' or cmd == 'REMOVE' then
        requireThat(sum(v) > 0, 'zero vector')
        if cmd == 'ADD' then
            total, available = add(total,v), add(available,v)
            print('added ' .. vec(v) .. ' total ' .. vec(total))
            retryQueue()
        else
            requireThat(fits(v,available), 'remove exceeds available')
            local nextTotal, nextAvailable = sub(total,v), sub(available,v)
            for _, x in ipairs(nextTotal) do requireThat(x ~= 0, 'total must stay positive') end
            for _, p in pairs(processes) do requireThat(fits(p.max,nextTotal), 'max exceeds total') end
            if mode == 'AVOID' then requireThat(check(false,trace,nextAvailable), 'removal makes state unsafe') end
            total, available = nextTotal, nextAvailable
            print('removed ' .. vec(v) .. ' total ' .. vec(total))
        end
    elseif cmd == 'REQUEST' or cmd == 'WHATIF' then
        local reason = reject(id,v)
        if reason then
            if cmd == 'REQUEST' then error(reason,0) end
            print('whatif P' .. id .. ' ' .. vec(v) .. ': rejected (' .. reason .. ')')
        else
            local granted, why, sequence = decision(id,v,trace)
            if cmd == 'WHATIF' then
                local result = granted and 'granted' or 'blocked (' .. why .. ')'
                if granted and mode == 'AVOID' then result = result .. ', safe sequence ' .. names(sequence) end
                print('whatif P' .. id .. ' ' .. vec(v) .. ': ' .. result)
            elseif granted then
                grant(id,v)
                print('granted P' .. id .. ' ' .. vec(v))
                record('granted',id,v)
            else
                queue[#queue+1] = {id,v,time}
                print('blocked P' .. id .. ' ' .. vec(v) .. ': ' .. why)
                record('blocked',id,v)
                if autodetect then
                    local _, _, dead = check(true,trace)
                    if #dead > 0 then print('deadlock detected: ' .. names(dead)) end
                end
            end
        end
    elseif cmd == 'RELEASE' then
        requireThat(not blocked(id), 'process P' .. id .. ' is blocked')
        requireThat(sum(v) > 0, 'zero vector')
        requireThat(fits(v,processes[id].alloc), 'release exceeds allocation')
        available, processes[id].alloc = add(available,v), sub(processes[id].alloc,v)
        print('released P' .. id .. ' ' .. vec(v))
        record('released',id,v)
        retryQueue()
    elseif cmd == 'FINISH' or cmd == 'ABORT' then
        requireThat(cmd ~= 'FINISH' or not blocked(id), 'process P' .. id .. ' is blocked')
        terminate(id,cmd == 'FINISH' and 'finished' or 'aborted',true)
    elseif cmd == 'CANCEL' then
        local q = blocked(id)
        requireThat(q ~= nil, 'process P' .. id .. ' is not blocked')
        removeRequest(id)
        print('cancelled P' .. id .. ' ' .. vec(q[2]))
        record('cancelled',id,q[2])
    elseif cmd == 'MAXGRANT' then
        requireThat(not blocked(id), 'process P' .. id .. ' is blocked')
        local result = zero()
        for i, n in ipairs(need(id)) do
            for x = n, 1, -1 do
                local w = zero(); w[i] = x
                if not reject(id,w) and decision(id,w,false) then result[i] = x; break end
            end
        end
        print('maxgrant P' .. id .. ': ' .. vec(result))
    elseif cmd == 'SAFE' then
        if next(processes) == nil then print('safe: no processes')
        else
            local safe, sequence, remaining = check(false,trace)
            print(safe and 'safe: ' .. names(sequence) or 'unsafe: ' .. names(remaining) .. ' cannot finish')
        end
    elseif cmd == 'SEQUENCES' then
        if next(processes) == nil then print('safe sequences: no processes')
        else
            local count, first = 0, {}
            local function visit(work, remaining, path)
                if #remaining == 0 then
                    count = count + 1
                    if #first < id then first[#first+1] = path end
                    return
                end
                for i, p in ipairs(remaining) do
                    if fits(need(p),work) then
                        local rest, nextPath = copy(remaining), copy(path)
                        table.remove(rest,i); nextPath[#nextPath+1] = p
                        visit(add(work,processes[p].alloc),rest,nextPath)
                    end
                end
            end
            visit(available,sortedKeys(processes),{})
            print('safe sequences: ' .. count)
            for _, path in ipairs(first) do print(names(path)) end
        end
    elseif cmd == 'DEFICIT' then
        local result = {}
        for i = 1, #total do
            local limit = 0
            for p in pairs(processes) do limit = limit + need(p)[i] end
            result[i] = '-'
            for x = 0, limit do
                local av = copy(available); av[i] = av[i]+x
                if check(false,false,av) then result[i] = x; break end
            end
        end
        print('deficit: ' .. vec(result))
    elseif cmd == 'STATE' then stateTable()
    elseif cmd == 'STATS' then statistics()
    elseif cmd == 'DETECT' then
        local _, _, dead = check(true,trace)
        print(#dead > 0 and 'deadlocked: ' .. names(dead) or 'no deadlock')
    elseif cmd == 'VICTIMS' then
        local _, _, dead = check(true,false)
        if #dead == 0 then print('no deadlock')
        else
            local candidates = {}
            for mask = 1, (1 << #dead)-1 do
                local set, cost = {}, 0
                for i, p in ipairs(dead) do
                    if mask & (1 << (i-1)) ~= 0 then set[#set+1] = p; cost = cost+sum(processes[p].alloc) end
                end
                candidates[#candidates+1] = {set,cost}
            end
            table.sort(candidates,function(a,b)
                if #a[1] ~= #b[1] then return #a[1] < #b[1] end
                if a[2] ~= b[2] then return a[2] < b[2] end
                return lexLess(a[1],b[1])
            end)
            for _, candidate in ipairs(candidates) do
                local set, ps, av, qs = candidate[1], copy(processes), copy(available), copy(queue)
                local removed = {}
                for _, p in ipairs(set) do av = add(av,ps[p].alloc); ps[p] = nil; removed[p] = true end
                for i = #qs, 1, -1 do if removed[qs[i][1]] then table.remove(qs,i) end end
                if check(true,false,av,ps,qs) then print('victims: ' .. names(set)); break end
            end
        end
    elseif cmd == 'RECOVER' then
        local count = 0
        while true do
            local _, _, dead = check(true,trace)
            if #dead == 0 then break end
            if words[1] == 'ALL' then
                for _, p in ipairs(dead) do terminate(p,'aborted',false) end
                count = count+#dead; retryQueue(); break
            end
            table.sort(dead,function(a,b)
                if policy == 'YOUNGEST' then return processes[a].born > processes[b].born end
                local x = policy == 'ALLOC' and sum(processes[a].alloc) or -sum(need(a))
                local y = policy == 'ALLOC' and sum(processes[b].alloc) or -sum(need(b))
                return x < y or (x == y and a > b)
            end)
            terminate(dead[1],'aborted',true)
            count = count+1
        end
        print(count > 0 and 'recovered: ' .. count .. ' aborted' or 'no deadlock')
    elseif cmd == 'WAITGRAPH' or cmd == 'GRAPH' then graph(cmd == 'GRAPH')
    elseif cmd == 'HISTORY' then
        local found = false
        for _, e in ipairs(history) do
            if not words[1] or e[2] == words[1] or (tonumber(words[1]) and e[3] == id) then
                local text = 't=' .. e[1] .. ' ' .. e[2] .. ' P' .. e[3] .. ' ' .. vec(e[4])
                if e[2] == 'unblocked' then text = text .. ' waited ' .. e[5] end
                print(text); found = true
            end
        end
        if not found then print('no events') end
    elseif cmd == 'SNAPSHOT' then
        snapshots[words[1]] = copy({total,available,processes,queue,history})
        print('saved ' .. words[1])
    elseif cmd == 'RESTORE' then
        requireThat(snapshots[words[1]] ~= nil, 'unknown snapshot ' .. words[1])
        local saved = copy(snapshots[words[1]])
        total, available, processes, queue, history = table.unpack(saved)
        print('restored ' .. words[1])
    end
end
local n = tonumber(io.read())
for i = 1, n do
    time = i
    local ok, message = pcall(run,io.read())
    if not ok then print('error: ' .. message) end
end
