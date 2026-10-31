local TYPES = {'MOTORCYCLE','CAR','ECAR','VAN','BUS'}
local KINDS = {'MOTO','COMPACT','LARGE','EV'}
local PREFS = {MOTORCYCLE={'MOTO','COMPACT','LARGE'},CAR={'COMPACT','LARGE'},ECAR={'EV','COMPACT','LARGE'},VAN={'LARGE'}}
local rates = {MOTORCYCLE={100,800},CAR={200,1600},ECAR={200,1600},VAN={300,2400},BUS={600,4800}}
local fees = {NIGHT=300,LOST=2000,KWH=30}
local levels,spots,vehicles,queue,passes,history,stats,daily = {},{},{},{},{},{},{},{}
local now,peak,peak_time = 0,0,0
local function fail(message) error(message,0) end
local function zeros(fields)
    local result = {}
    for _,field in ipairs(fields) do result[field] = 0 end
    return result
end
for _,kind in ipairs(TYPES) do stats[kind] = zeros({'entries','exits','refused','stay','parking','night','lost','charge','total'}) end
local function size(map)
    local total = 0
    for _ in pairs(map) do total = total+1 end
    return total
end
local function find(items,needle)
    for index,value in ipairs(items) do
        if value == needle then return index end
    end
    return nil
end
local function append(target,items)
    table.move(items,1,#items,#target+1,target)
end
local function date_of(time) return time//1440+1 end
local function time_text(time) return date_of(time) .. '-' .. string.format('%02d:%02d',(time%1440)//60,time%60) end
local function duration(minutes) return string.format('%d:%02d',minutes//60,minutes%60) end
local function one_decimal(q) return (q//10) .. '.' .. (q%10) end
local function valid_pass(plate,time) return passes[plate] ~= nil and date_of(time) <= passes[plate] end
local function get_spot(id)
    if not spots[id] then fail('unknown spot ' .. id) end
    return spots[id]
end
local function get_vehicle(plate)
    if not vehicles[plate] then fail(plate .. ' is not parked') end
    return vehicles[plate]
end
local function location(v)
    local s = v.spots[1]
    if v.type == 'BUS' then return 'L' .. s.level .. '-' .. s.number .. '..' .. (s.number+2) end
    return s.id
end
local function location_less(a,b)
    local x,y = a.spots[1],b.spots[1]
    if x.level ~= y.level then return x.level < y.level end
    return x.number < y.number
end
local function free_spot(s) return not s.closed and s.plate == '' end
local function assignment(kind)
    if kind == 'BUS' then
        for _,level in ipairs(levels) do
            for i = 1,#level-2 do
                local triple,valid = {},true
                for j = i,i+2 do
                    triple[#triple+1] = level[j]
                    if level[j].kind ~= 'LARGE' or not free_spot(level[j]) then valid = false end
                end
                if valid then return triple end
            end
        end
    else
        for _,preferred in ipairs(PREFS[kind]) do
            for _,level in ipairs(levels) do
                for _,s in ipairs(level) do
                    if s.kind == preferred and free_spot(s) then return {s} end
                end
            end
        end
    end
    return {}
end
local function add_stat(kind,field,amount,date)
    stats[kind][field] = stats[kind][field]+amount
    if field == 'entries' or field == 'exits' or field == 'refused' or field == 'total' then
        if not daily[date] then
            daily[date] = {}
            for _,k in ipairs(TYPES) do daily[date][k] = zeros({'entries','exits','refused','revenue'}) end
        end
        local daily_field = field == 'total' and 'revenue' or field
        daily[date][kind][daily_field] = daily[date][kind][daily_field]+amount
    end
end
local function park_vehicle(plate,kind,chosen)
    local v = {plate=plate,type=kind,spots=chosen,entry=now,kwh=0,cost=0,validation=0,payment=nil}
    for _,s in ipairs(chosen) do s.plate = plate end
    vehicles[plate] = v
    add_stat(kind,'entries',1,date_of(now))
    if size(vehicles) > peak then peak,peak_time = size(vehicles),now end
    return v
end
local function process_queue(out)
    local remaining = {}
    for _,waiting in ipairs(queue) do
        local chosen = assignment(waiting.type)
        if #chosen == 0 then
            remaining[#remaining+1] = waiting
        else
            local v = park_vehicle(waiting.plate,waiting.type,chosen)
            out[#out+1] = 'ADMIT ' .. v.plate .. ' ' .. v.type .. ' ' .. location(v) .. ' waited ' .. duration(now-waiting.time)
        end
    end
    queue = remaining
end
local function giveups()
    local remaining,out = {},{}
    for _,waiting in ipairs(queue) do
        if now-waiting.time >= 30 then
            local time = waiting.time+30
            out[#out+1] = 'GIVEUP ' .. waiting.plate .. ' ' .. waiting.type .. ' ' .. time_text(time)
            add_stat(waiting.type,'refused',1,date_of(time))
        else
            remaining[#remaining+1] = waiting
        end
    end
    queue = remaining
    return out
end
local function interval_fee(v,a,b,free)
    local total = b-a
    if valid_pass(v.plate,b) or total <= free then return 0,0 end
    local rate,cap = table.unpack(rates[v.type])
    local parking,i = 0,0
    while total > 0 do
        local minutes = math.min(total,1440)
        local billable = minutes-(i == 0 and free or 0)
        parking = parking+math.min(((billable+29)//30)*rate,cap)
        total,i = total-minutes,i+1
    end
    return parking,(date_of(b)-date_of(a))*fees.NIGHT
end
local function charges(v,lost)
    if not v.payment then
        local parking,night = interval_fee(v,v.entry,now,15+v.validation)
        local loss = lost and fees.LOST or 0
        local total = parking+night+loss+v.cost
        return {parking,night,loss,v.cost,total,total}
    end
    local extra,extra_night = interval_fee(v,v.payment.time,now,15)
    local parking,night = v.payment.parking+extra,v.payment.night+extra_night
    return {parking,night,0,v.cost,parking+night+v.cost,extra+extra_night}
end
local function fee_line(label,v,f)
    return label .. ' ' .. v.plate .. ' ' .. location(v) .. ' stay ' .. duration(now-v.entry) .. ' parking ' .. f[1] .. ' night ' .. f[2] .. ' lost ' .. f[3] .. ' charge ' .. f[4] .. ' total ' .. f[5] .. ' due ' .. f[6]
end
local function annotation(v)
    local text = valid_pass(v.plate,now) and ' PASS' or ''
    if v.validation ~= 0 then text = text .. ' VAL ' .. v.validation end
    if v.kwh ~= 0 then text = text .. ' KWH ' .. v.kwh end
    if v.payment then text = text .. ' PAID' end
    return text
end
local function move_vehicle(v,spot)
    local old = location(v)
    v.spots[1].plate = ''
    spot.plate = v.plate
    v.spots = {spot}
    return 'MOVE ' .. v.plate .. ' ' .. old .. ' -> ' .. spot.id
end
local function occupancy_line(label,used,available,closed_count)
    local parts = {label}
    for _,kind in ipairs(KINDS) do append(parts,{kind,used[kind] .. '/' .. available[kind]}) end
    append(parts,{'closed',closed_count})
    return table.concat(parts,' ')
end
local function execute(t)
    local cmd,out = t[1],{}
    local function emit(text) out[#out+1] = text end
    if cmd == 'LEVEL' then
        local level_no,level = #levels+1,{}
        for index,kind in ipairs(KINDS) do
            for _ = 1,tonumber(t[index+1]) do
                local number = #level+1
                local id = 'L' .. level_no .. '-' .. number
                local s = {id=id,level=level_no,number=number,kind=kind,closed=false,plate=''}
                spots[id] = s
                level[#level+1] = s
            end
        end
        levels[#levels+1] = level
        emit('LEVEL ' .. level_no .. ' spots ' .. #level .. ' MOTO ' .. t[2] .. ' COMPACT ' .. t[3] .. ' LARGE ' .. t[4] .. ' EV ' .. t[5])
    elseif cmd == 'CLOSE' or cmd == 'OPEN' then
        local s = get_spot(t[2])
        if cmd == 'CLOSE' then
            if s.closed then fail('spot ' .. t[2] .. ' is already closed') end
            if s.plate ~= '' then fail('spot ' .. t[2] .. ' is occupied by ' .. s.plate) end
            s.closed = true
        else
            if not s.closed then fail('spot ' .. t[2] .. ' is not closed') end
            s.closed = false
        end
        emit(cmd .. ' ' .. s.id .. ' ' .. s.kind)
    elseif cmd == 'RATE' then
        if not rates[t[2]] then fail('unknown type ' .. t[2]) end
        if tonumber(t[4]) < tonumber(t[3]) then fail('cap below rate for ' .. t[2]) end
        rates[t[2]] = {tonumber(t[3]),tonumber(t[4])}
        emit('RATE ' .. t[2] .. ' ' .. t[3] .. ' ' .. t[4])
    elseif cmd == 'FEE' then
        if fees[t[2]] == nil then fail('unknown fee ' .. t[2]) end
        fees[t[2]] = tonumber(t[3])
        emit('FEE ' .. t[2] .. ' ' .. t[3])
    elseif cmd == 'ENTER' then
        local plate,kind = t[2],t[3]
        if not rates[kind] then fail('unknown type ' .. kind) end
        if vehicles[plate] then fail(plate .. ' is already parked at ' .. location(vehicles[plate])) end
        for _,w in ipairs(queue) do
            if w.plate == plate then fail(plate .. ' is already waiting') end
        end
        local chosen = assignment(kind)
        if #chosen > 0 then
            local v = park_vehicle(plate,kind,chosen)
            emit('ENTER ' .. plate .. ' ' .. kind .. ' ' .. location(v))
        elseif #queue < 3 then
            queue[#queue+1] = {plate=plate,type=kind,time=now}
            emit('WAIT ' .. plate .. ' ' .. kind .. ' ' .. #queue)
        else
            add_stat(kind,'refused',1,date_of(now))
            emit('FULL ' .. plate .. ' ' .. kind)
        end
    elseif cmd == 'LEAVE' then
        local index
        for i,w in ipairs(queue) do
            if w.plate == t[2] then index = i end
        end
        if not index then fail(t[2] .. ' is not waiting') end
        local w = table.remove(queue,index)
        emit('LEAVE ' .. w.plate .. ' ' .. w.type)
    elseif cmd == 'EXIT' or cmd == 'PAY' or cmd == 'QUOTE' or cmd == 'CHARGE' or cmd == 'VALIDATE' or cmd == 'MOVE' then
        local v = get_vehicle(t[2])
        if cmd == 'EXIT' then
            local lost = #t == 3
            if lost and v.payment then fail(v.plate .. ' has already paid') end
            local f = charges(v,lost)
            emit(fee_line('EXIT',v,f))
            local record = {entry=v.entry,exit=now,location=location(v),type=v.type,total=f[5],lost=lost}
            if not history[v.plate] then history[v.plate] = {} end
            local records = history[v.plate]
            records[#records+1] = record
            for _,s in ipairs(v.spots) do s.plate = '' end
            vehicles[v.plate] = nil
            add_stat(v.type,'exits',1,date_of(now))
            add_stat(v.type,'stay',now-v.entry,date_of(now))
            for index,field in ipairs({'parking','night','lost','charge','total'}) do add_stat(v.type,field,f[index],date_of(now)) end
        elseif cmd == 'PAY' then
            if v.payment then fail(v.plate .. ' has already paid') end
            local f = charges(v)
            v.payment = {time=now,parking=f[1],night=f[2]}
            emit('PAY ' .. v.plate .. ' parking ' .. f[1] .. ' night ' .. f[2] .. ' charge ' .. f[4] .. ' total ' .. f[5])
        elseif cmd == 'QUOTE' then
            emit(fee_line('QUOTE',v,charges(v)))
        elseif cmd == 'CHARGE' then
            if v.type ~= 'ECAR' then fail(v.plate .. ' is not an electric car') end
            if v.spots[1].kind ~= 'EV' then fail(v.plate .. ' is not at a charger') end
            if v.payment then fail(v.plate .. ' has already paid') end
            local kwh = tonumber(t[3])
            if v.kwh+kwh > 100 then fail('charge limit exceeded for ' .. v.plate) end
            local cost = kwh*fees.KWH
            v.kwh,v.cost = v.kwh+kwh,v.cost+cost
            emit('CHARGE ' .. v.plate .. ' kwh ' .. kwh .. ' cost ' .. cost .. ' stay_kwh ' .. v.kwh .. ' stay_cost ' .. v.cost)
        elseif cmd == 'VALIDATE' then
            if v.payment then fail(v.plate .. ' has already paid') end
            local minutes = tonumber(t[3])
            if v.validation+minutes > 180 then fail('validation limit exceeded for ' .. v.plate) end
            v.validation = v.validation+minutes
            emit('VALIDATE ' .. v.plate .. ' ' .. minutes .. ' total ' .. v.validation)
        else
            if v.type == 'BUS' then fail('bus ' .. v.plate .. ' cannot be moved') end
            local s = get_spot(t[3])
            if v.spots[1].id == s.id then fail(v.plate .. ' is already at ' .. s.id) end
            if s.closed then fail('spot ' .. s.id .. ' is closed') end
            if s.plate ~= '' then fail('spot ' .. s.id .. ' is occupied by ' .. s.plate) end
            if not find(PREFS[v.type],s.kind) then fail(v.type .. ' cannot use ' .. s.kind .. ' spot ' .. s.id) end
            emit(move_vehicle(v,s))
        end
    elseif cmd == 'PASS' then
        local plate,days = t[2],tonumber(t[3])
        passes[plate] = valid_pass(plate,now) and passes[plate]+days or date_of(now)+days-1
        emit('PASS ' .. plate .. ' until ' .. passes[plate])
    elseif cmd == 'UNPASS' then
        if not valid_pass(t[2],now) then fail(t[2] .. ' has no pass') end
        passes[t[2]] = nil
        emit('UNPASS ' .. t[2])
    elseif cmd == 'REBALANCE' then
        local targets = {}
        for _,v in pairs(vehicles) do
            if v.type ~= 'BUS' then targets[#targets+1] = v end
        end
        table.sort(targets,location_less)
        local moved = 0
        for _,v in ipairs(targets) do
            local current = find(PREFS[v.type],v.spots[1].kind)
            if current ~= 1 then
                local chosen = assignment(v.type)
                if #chosen > 0 and find(PREFS[v.type],chosen[1].kind) < current then
                    emit(move_vehicle(v,chosen[1]))
                    moved = moved+1
                end
            end
        end
        emit('REBALANCE ' .. moved)
    elseif cmd == 'WHERE' then
        local plate = t[2]
        if vehicles[plate] then
            local v = vehicles[plate]
            emit('WHERE ' .. plate .. ' ' .. location(v) .. ' ' .. v.type .. ' ' .. time_text(v.entry) .. ' stay ' .. duration(now-v.entry) .. annotation(v))
        else
            local position
            for index,w in ipairs(queue) do
                if w.plate == plate then position = index end
            end
            if position then
                emit('WHERE ' .. plate .. ' waiting ' .. position)
            elseif history[plate] then
                local records = history[plate]
                emit('WHERE ' .. plate .. ' gone ' .. time_text(records[#records].exit))
            else
                fail('unknown plate ' .. plate)
            end
        end
    elseif cmd == 'LIST' or cmd == 'OVERSTAY' then
        if cmd == 'LIST' and t[2] and not levels[tonumber(t[2])] then fail('unknown level ' .. t[2]) end
        local targets = {}
        for _,v in pairs(vehicles) do
            local include = true
            if cmd == 'LIST' and t[2] then include = v.spots[1].level == tonumber(t[2]) end
            if cmd == 'OVERSTAY' then include = now-v.entry >= tonumber(t[2])*60 end
            if include then targets[#targets+1] = v end
        end
        table.sort(targets,function(a,b)
            if cmd == 'OVERSTAY' and a.entry ~= b.entry then return a.entry < b.entry end
            return location_less(a,b)
        end)
        local header = cmd == 'OVERSTAY' and cmd .. ' ' .. t[2] or cmd
        emit(header .. ' ' .. #targets)
        for _,v in ipairs(targets) do
            local text = location(v) .. ' ' .. v.plate .. ' ' .. v.type .. ' ' .. time_text(v.entry)
            if cmd == 'LIST' then text = text .. annotation(v) else text = text .. ' stay ' .. duration(now-v.entry) end
            emit(text)
        end
    elseif cmd == 'MAP' then
        emit('MAP ' .. #levels)
        for index,level in ipairs(levels) do
            local symbols = ''
            for _,s in ipairs(level) do
                local char
                if s.closed then char = '#'
                elseif s.plate ~= '' then char = s.kind:sub(1,1)
                else char = s.kind:sub(1,1):lower() end
                symbols = symbols .. char
            end
            local chunks = {}
            for i = 1,#symbols,10 do chunks[#chunks+1] = symbols:sub(i,i+9) end
            emit('L' .. index .. ' ' .. table.concat(chunks,' '))
        end
    elseif cmd == 'OCCUPANCY' then
        emit('OCCUPANCY vehicles ' .. size(vehicles) .. ' waiting ' .. #queue)
        local total_used,total_available,total_closed = zeros(KINDS),zeros(KINDS),0
        for index,level in ipairs(levels) do
            local used,available,closed_count = zeros(KINDS),zeros(KINDS),0
            for _,s in ipairs(level) do
                if s.closed then closed_count = closed_count+1 else available[s.kind] = available[s.kind]+1 end
                if s.plate ~= '' then used[s.kind] = used[s.kind]+1 end
            end
            emit(occupancy_line('L' .. index,used,available,closed_count))
            for _,kind in ipairs(KINDS) do
                total_used[kind] = total_used[kind]+used[kind]
                total_available[kind] = total_available[kind]+available[kind]
            end
            total_closed = total_closed+closed_count
        end
        local used,capacity = 0,0
        for _,kind in ipairs(KINDS) do used,capacity = used+total_used[kind],capacity+total_available[kind] end
        local usage = capacity == 0 and 0 or (used*1000)//capacity
        emit(occupancy_line('TOTAL',total_used,total_available,total_closed) .. ' rate ' .. one_decimal(usage) .. '%')
    elseif cmd == 'SIGN' then
        local parts = {'SIGN'}
        for _,kind in ipairs(TYPES) do
            local count = 0
            for _,level in ipairs(levels) do
                local run = 0
                for _,s in ipairs(level) do
                    if kind == 'BUS' then
                        if s.kind == 'LARGE' and free_spot(s) then run = run+1
                        else count,run = count+run//3,0 end
                    elseif find(PREFS[kind],s.kind) and free_spot(s) then
                        count = count+1
                    end
                end
                if kind == 'BUS' then count = count+run//3 end
            end
            append(parts,{kind,count == 0 and 'FULL' or count})
        end
        emit(table.concat(parts,' '))
    elseif cmd == 'RATES' then
        emit('RATES')
        for _,kind in ipairs(TYPES) do emit(kind .. ' ' .. rates[kind][1] .. ' ' .. rates[kind][2]) end
        emit('NIGHT ' .. fees.NIGHT .. ' LOST ' .. fees.LOST .. ' KWH ' .. fees.KWH)
    elseif cmd == 'PASSES' then
        local plates = {}
        for plate in pairs(passes) do
            if valid_pass(plate,now) then plates[#plates+1] = plate end
        end
        table.sort(plates)
        emit('PASSES ' .. #plates)
        for _,plate in ipairs(plates) do emit(plate .. ' until ' .. passes[plate] .. (vehicles[plate] and ' IN' or '')) end
    elseif cmd == 'HISTORY' then
        local records = history[t[2]]
        if not records then fail('no history for ' .. t[2]) end
        local paid = 0
        for _,r in ipairs(records) do paid = paid+r.total end
        emit('HISTORY ' .. t[2] .. ' visits ' .. #records .. ' paid ' .. paid)
        for _,r in ipairs(records) do emit(time_text(r.entry) .. ' ' .. time_text(r.exit) .. ' ' .. r.location .. ' ' .. r.type .. ' ' .. r.total .. (r.lost and ' LOST' or '')) end
    elseif cmd == 'REVENUE' then
        emit('REVENUE')
        local total = zeros({'exits','parking','night','lost','charge','total'})
        local labels = {table.unpack(TYPES)}
        labels[#labels+1] = 'TOTAL'
        for _,kind in ipairs(labels) do
            local s = kind == 'TOTAL' and total or stats[kind]
            if kind ~= 'TOTAL' then
                for key in pairs(total) do total[key] = total[key]+s[key] end
            end
            emit(kind .. ' exits ' .. s.exits .. ' parking ' .. s.parking .. ' night ' .. s.night .. ' lost ' .. s.lost .. ' charge ' .. s.charge .. ' total ' .. s.total)
        end
    elseif cmd == 'DAILY' then
        local date = tonumber(t[2])
        local rows = daily[date] or {}
        local total,lines = zeros({'entries','exits','refused','revenue'}),{}
        for _,kind in ipairs(TYPES) do
            local s = rows[kind] or zeros({'entries','exits','refused','revenue'})
            for key in pairs(total) do total[key] = total[key]+s[key] end
            lines[#lines+1] = kind .. ' entries ' .. s.entries .. ' exits ' .. s.exits .. ' refused ' .. s.refused .. ' revenue ' .. s.revenue
        end
        emit('DAILY ' .. date .. ' entries ' .. total.entries .. ' exits ' .. total.exits .. ' refused ' .. total.refused .. ' revenue ' .. total.revenue)
        append(out,lines)
    elseif cmd == 'STATS' then
        emit('STATS parked ' .. size(vehicles) .. ' peak ' .. peak .. ' at ' .. (peak == 0 and '-' or time_text(peak_time)))
        local total,labels = zeros({'entries','exits','refused','stay'}),{table.unpack(TYPES)}
        labels[#labels+1] = 'ALL'
        for _,kind in ipairs(labels) do
            local s = kind == 'ALL' and total or stats[kind]
            if kind ~= 'ALL' then
                for key in pairs(total) do total[key] = total[key]+s[key] end
            end
            local average = s.exits == 0 and 0 or (s.stay*10)//s.exits
            emit(kind .. ' entries ' .. s.entries .. ' exits ' .. s.exits .. ' refused ' .. s.refused .. ' avg_stay ' .. one_decimal(average))
        end
    end
    if cmd == 'LEVEL' or cmd == 'OPEN' or cmd == 'EXIT' or cmd == 'MOVE' or cmd == 'REBALANCE' then process_queue(out) end
    return out
end
local n = tonumber(io.read('*l'))
for _ = 1,n do
    local tokens = {}
    for word in io.read('*l'):gmatch('%S+') do tokens[#tokens+1] = word end
    local hour,minute = tokens[2]:match('^(%d%d):(%d%d)$')
    now = (tonumber(tokens[1])-1)*1440+tonumber(hour)*60+tonumber(minute)
    for _,line in ipairs(giveups()) do io.write(line,'\n') end
    local command = {table.unpack(tokens,3)}
    local ok,out = pcall(execute,command)
    if ok then
        for _,line in ipairs(out) do io.write(line,'\n') end
    else
        io.write('ERROR ',out,'\n')
    end
end
