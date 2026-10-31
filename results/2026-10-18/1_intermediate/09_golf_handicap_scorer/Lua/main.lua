local courses,players,events,event_order = {},{},{},{}
local function fail(message) error(message,0) end
local function half_up(a,b) return (2*a+b)//(2*b) end
local function half_away(a,b) return (a < 0 and -1 or 1)*((2*math.abs(a)+b)//(2*b)) end
local function decimal(v) return (math.abs(v)//10) .. '.' .. (math.abs(v)%10) end
local function index_text(v) return v == nil and 'none' or (v < 0 and '+' or '') .. decimal(v) end
local function signed_text(v) return (v < 0 and '-' or '') .. decimal(v) end
local function handicap_text(v)
    if v == nil then return 'none' end
    return v < 0 and '+' .. -v or tostring(v)
end
local function hundredths(v) return string.format('%d.%02d',v//100,v%100) end
local function mean_text(total,count) return count == 0 and '-' or hundredths((total*100)//count) end
local function status_text(lead)
    if lead == 0 then return 'AS' end
    return math.abs(lead) .. (lead > 0 and ' UP' or ' DN')
end
local function sum(values,first,last)
    local total = 0
    for i = first or 1,last or #values do total = total+values[i] end
    return total
end
local function append(target,items)
    table.move(items,1,#items,#target+1,target)
end
local function slice(values,first,last)
    return {table.unpack(values,first,last or #values)}
end
local function tuple_less(a,b)
    for i = 1,#a do
        if a[i] ~= b[i] then return a[i] < b[i] end
    end
    return false
end
local function get_player(id)
    if not players[id] then fail('unknown player') end
    return players[id]
end
local function get_course(id)
    if not courses[id] then fail('unknown course') end
    return courses[id]
end
local function tee_check(course,tee)
    local c = get_course(course)
    if not c.tees[tee] then fail('unknown tee') end
    return c,c.tees[tee]
end
local function course_handicap(index,c,tee) return half_up(index*tee[2]+113*(tee[1]-10*sum(c.pars)),1130) end
local function allocate(handicap,si)
    local q,r = math.abs(handicap)//18,math.abs(handicap)%18
    local out = {}
    for h,rank in ipairs(si) do
        if handicap >= 0 then out[h] = q+(rank <= r and 1 or 0)
        else out[h] = -q-(rank >= 19-r and 1 or 0) end
    end
    return out
end
local function low_index(p,day)
    local best
    for _,record in ipairs(p.records) do
        if record[1] >= day-365 and record[1] < day then
            if not best or record[2] < best[2] or (record[2] == best[2] and record[1] < best[1]) then best = record end
        end
    end
    return best
end
local function counting_rule(n)
    if n < 3 then return 0,0 end
    if n == 3 then return 1,-20 end
    if n == 4 then return 1,-10 end
    if n == 5 then return 1,0 end
    if n == 6 then return 2,-10 end
    if n <= 8 then return 2,0 end
    if n <= 11 then return 3,0 end
    if n <= 14 then return 4,0 end
    if n <= 16 then return 5,0 end
    if n <= 18 then return 6,0 end
    return n == 19 and 7 or 8,0
end
local function eligible(p)
    local result,reduction = {},0
    for i = #p.rounds,math.max(1,#p.rounds-19),-1 do
        local r = p.rounds[i]
        reduction = reduction+r.exceptional
        table.insert(result,1,{number=i,round=r,adjusted=r.diff-reduction})
    end
    return result
end
local function counting(items)
    local k = counting_rule(#items)
    local ordered = slice(items,1)
    table.sort(ordered,function(a,b)
        if a.adjusted ~= b.adjusted then return a.adjusted < b.adjusted end
        return a.number > b.number
    end)
    return slice(ordered,1,k)
end
local function update_index(p,day)
    local items = eligible(p)
    local k,adjustment = counting_rule(#items)
    if k == 0 then
        p.calculation = nil
        return
    end
    local total = 0
    for _,item in ipairs(counting(items)) do total = total+item.adjusted end
    local average = half_away(total,k)
    local value = average+adjustment
    local low = low_index(p,day)
    local soft,hard,maximum = false,false,false
    if low then
        local l = low[2]
        if value-l > 30 then
            local new = l+30+(value-l-30)//2
            soft,value = new ~= value,new
        end
        if value-l > 50 then value,hard = l+50,true end
    end
    if value > 540 then value,maximum = 540,true end
    p.index = value
    p.calculation = {k=k,average=average,adjustment=adjustment,low=low and low[2] or nil,hard=hard,soft=soft,maximum=maximum}
end
local function hole_values(r,strokes,c)
    local nets,points = {},{}
    for h,score in ipairs(r.scores) do
        local raw = tonumber(score)
        local net = raw and raw-strokes[h] or false
        nets[h] = net
        points[h] = net == false and 0 or math.max(0,c.pars[h]+2-net)
    end
    return nets,points
end
local function countback(values,larger)
    local key = {}
    for _,first in ipairs({1,10,13,16,18}) do key[#key+1] = sum(values,first,18)*(larger and -1 or 1) end
    return key
end
local function event_context(e)
    local c = tee_check(e.course,e.tee)
    local rounds,ph = {},{}
    local minimum
    for _,id in ipairs(e.players) do
        local found
        for _,r in ipairs(players[id].rounds) do
            if r.course == e.course and r.tee == e.tee and r.day == e.day then
                found = r
                break
            end
        end
        if not found then fail('missing round') end
        if found.handicap == nil then fail('no index') end
        rounds[id] = found
        ph[id] = half_up(found.handicap*e.allowance,100)
        minimum = minimum and math.min(minimum,ph[id]) or ph[id]
    end
    if e.format ~= 'MATCH' and e.format ~= 'NASSAU' and e.format ~= 'FOURBALL' then minimum = 0 end
    local nets,points = {},{}
    for _,id in ipairs(e.players) do nets[id],points[id] = hole_values(rounds[id],allocate(ph[id]-minimum,c.si),c) end
    return {course=c,rounds=rounds,ph=ph,minimum=minimum,nets=nets,points=points}
end
local function par_values(nets,pars)
    local values = {}
    for h,net in ipairs(nets) do
        if net == false or net > pars[h] then values[h] = -1
        elseif net < pars[h] then values[h] = 1
        else values[h] = 0 end
    end
    return values
end
local function ranking(e,ctx)
    local ranked,keys = {},{}
    for _,id in ipairs(e.players) do
        local values,valid = nil,true
        if e.format == 'STROKE' then
            values = ctx.nets[id]
            for h = 1,18 do
                if values[h] == false then valid = false end
            end
        elseif e.format == 'STABLEFORD' then values = ctx.points[id]
        else values = par_values(ctx.nets[id],ctx.course.pars) end
        if valid then
            ranked[#ranked+1] = id
            local key = countback(values,e.format ~= 'STROKE')
            key[#key+1] = id
            keys[id] = key
        end
    end
    table.sort(ranked,function(a,b) return tuple_less(keys[a],keys[b]) end)
    return ranked
end
local function play_match(wins,names,first,last)
    local lead,remaining,statuses = 0,0,{}
    for h = first,last do
        lead = lead+wins[h]
        statuses[#statuses+1] = status_text(lead)
        remaining = last-h
        if math.abs(lead) > remaining then break end
    end
    local result = 'AS'
    if lead ~= 0 then
        local name = names[lead > 0 and 1 or 2]
        local margin = remaining > 0 and math.abs(lead) .. '&' .. remaining or math.abs(lead) .. ' UP'
        result = name .. ' ' .. margin
    end
    return statuses,result
end
local function raw_scores(r)
    local values = {}
    for h,score in ipairs(r.scores) do values[h] = tonumber(score) end
    return values
end
local function result_lines(e)
    local ctx = event_context(e)
    local c = ctx.course
    local out = {'results ' .. e.id .. ': ' .. e.format .. ' ' .. e.course .. ' ' .. e.tee .. ' day ' .. e.day .. ' allowance ' .. e.allowance}
    if e.format == 'STROKE' or e.format == 'STABLEFORD' or e.format == 'PAR' then
        local ranked = ranking(e,ctx)
        local ranked_set = {}
        for rank,id in ipairs(ranked) do
            ranked_set[id] = true
            local text
            if e.format == 'STROKE' then text = 'net ' .. sum(ctx.nets[id]) .. ' gross ' .. sum(raw_scores(ctx.rounds[id]))
            elseif e.format == 'STABLEFORD' then text = 'points ' .. sum(ctx.points[id])
            else text = status_text(sum(par_values(ctx.nets[id],c.pars))) end
            out[#out+1] = rank .. ' ' .. id .. ' ' .. text .. ' hcp ' .. handicap_text(ctx.ph[id])
        end
        if e.format == 'STROKE' then
            local nr = {}
            for _,id in ipairs(e.players) do
                if not ranked_set[id] then nr[#nr+1] = id end
            end
            table.sort(nr)
            for _,id in ipairs(nr) do out[#out+1] = 'NR ' .. id .. ' hcp ' .. handicap_text(ctx.ph[id]) end
            if #ranked > 0 then
                local keys = {}
                for _,id in ipairs(ranked) do
                    keys[id] = countback(raw_scores(ctx.rounds[id]))
                    keys[id][6] = id
                end
                table.sort(ranked,function(a,b) return tuple_less(keys[a],keys[b]) end)
                local id = ranked[1]
                out[#out+1] = 'gross ' .. id .. ' ' .. sum(raw_scores(ctx.rounds[id]))
            end
        end
    elseif e.format == 'MATCH' or e.format == 'NASSAU' or e.format == 'FOURBALL' then
        local side_size = e.format == 'FOURBALL' and 2 or 1
        local sides = {slice(e.players,1,side_size),slice(e.players,side_size+1,2*side_size)}
        local names = {table.concat(sides[1],'+'),table.concat(sides[2],'+')}
        local wins = {}
        for h = 1,18 do
            local scores = {false,false}
            for index,ids in ipairs(sides) do
                for _,id in ipairs(ids) do
                    local net = ctx.nets[id][h]
                    if net ~= false then scores[index] = scores[index] == false and net or math.min(scores[index],net) end
                end
            end
            if scores[1] == false then wins[h] = scores[2] == false and 0 or -1
            elseif scores[2] == false then wins[h] = 1
            elseif scores[1] < scores[2] then wins[h] = 1
            elseif scores[1] > scores[2] then wins[h] = -1
            else wins[h] = 0 end
        end
        local parts = {'strokes'}
        for _,id in ipairs(e.players) do append(parts,{id,ctx.ph[id]-ctx.minimum}) end
        out[#out+1] = table.concat(parts,' ')
        if e.format == 'NASSAU' then
            for _,range in ipairs({{'front',1,9},{'back',10,18},{'total',1,18}}) do
                local _,result = play_match(wins,names,range[2],range[3])
                out[#out+1] = range[1] .. ' ' .. result
            end
        else
            local statuses,result = play_match(wins,names,1,18)
            out[#out+1] = 'status ' .. table.concat(statuses,', ')
            out[#out+1] = 'result ' .. result
        end
    elseif e.format == 'BETTERBALL' then
        local teams = {}
        for i = 1,#e.players,2 do
            local a,b = e.players[i],e.players[i+1]
            local values = {}
            for h = 1,18 do values[h] = math.max(ctx.points[a][h],ctx.points[b][h]) end
            local key = countback(values,true)
            key[6] = a
            teams[#teams+1] = {a=a,b=b,values=values,key=key}
        end
        table.sort(teams,function(a,b) return tuple_less(a.key,b.key) end)
        for rank,team in ipairs(teams) do
            out[#out+1] = rank .. ' ' .. team.a .. '+' .. team.b .. ' points ' .. sum(team.values) .. ' hcp ' .. handicap_text(ctx.ph[team.a]) .. ' ' .. handicap_text(ctx.ph[team.b])
        end
    else
        local totals = {}
        for _,id in ipairs(e.players) do totals[id] = 0 end
        local carry,winners = 0,{}
        for h = 1,18 do
            carry = carry+1
            local minimum
            winners = {}
            for _,id in ipairs(e.players) do
                local net = ctx.nets[id][h]
                if net ~= false then
                    if minimum == nil or net < minimum then minimum,winners = net,{id}
                    elseif net == minimum then winners[#winners+1] = id end
                end
            end
            if #winners == 1 then
                local id = winners[1]
                totals[id] = totals[id]+100*carry
                out[#out+1] = 'hole ' .. h .. ' ' .. id .. ' ' .. carry
                carry = 0
            end
        end
        if carry > 0 then
            if #winners == 0 then winners = slice(e.players,1) end
            table.sort(winners)
            local share = (100*carry)//#winners
            for _,id in ipairs(winners) do totals[id] = totals[id]+share end
            out[#out+1] = 'carry ' .. carry .. ' ' .. table.concat(winners,' ')
        end
        local ids = slice(e.players,1)
        table.sort(ids,function(a,b)
            if totals[a] ~= totals[b] then return totals[a] > totals[b] end
            return a < b
        end)
        for _,id in ipairs(ids) do out[#out+1] = id .. ' ' .. hundredths(totals[id]) end
    end
    return out
end
local function execute(line)
    local t,out = {},{}
    for token in line:gmatch('%S+') do t[#t+1] = token end
    local cmd = t[1]
    local function emit(text) out[#out+1] = text end
    if cmd == 'COURSE' then
        if courses[t[2]] then fail('duplicate course') end
        local pars,si,seen = {},{},{}
        local valid = true
        for h = 1,18 do
            pars[h],si[h] = tonumber(t[h+2]),tonumber(t[h+20])
            if pars[h] < 3 or pars[h] > 5 or si[h] < 1 or si[h] > 18 or seen[si[h]] then valid = false end
            seen[si[h]] = true
        end
        if not valid then fail('invalid course') end
        courses[t[2]] = {id=t[2],pars=pars,si=si,tees={}}
    elseif cmd == 'TEE' then
        local c = get_course(t[2])
        if c.tees[t[3]] then fail('duplicate tee') end
        local rating,slope = tonumber(t[4]),tonumber(t[5])
        if rating < 500 or rating > 900 or slope < 55 or slope > 155 then fail('invalid tee') end
        c.tees[t[3]] = {rating,slope}
    elseif cmd == 'PLAYER' then
        if players[t[2]] then fail('duplicate player') end
        local index = t[4] and tonumber(t[4]) or nil
        if index and (index < -100 or index > 540) then fail('invalid index') end
        players[t[2]] = {id=t[2],name=t[3],index=index,rounds={},records={},calculation=nil}
    elseif cmd == 'ROUND' then
        local p = get_player(t[2])
        local c,tee = tee_check(t[3],t[4])
        local day = tonumber(t[5])
        if #p.rounds > 0 and day < p.rounds[#p.rounds].day then fail('invalid day') end
        local scores,missing = slice(t,6),0
        for _,score in ipairs(scores) do
            if score == '-' then missing = missing+1 end
        end
        if missing >= 5 then fail('too few holes') end
        local hcp = p.index and course_handicap(p.index,c,tee) or nil
        local strokes = allocate(hcp or 0,c.si)
        local adjusted = {}
        for h,score in ipairs(scores) do
            local limit = c.pars[h]+(p.index and 2+strokes[h] or 5)
            if score == 'X' then adjusted[h] = limit
            elseif score == '-' then adjusted[h] = c.pars[h]+strokes[h]
            else adjusted[h] = math.min(tonumber(score),limit) end
        end
        local ags = sum(adjusted)
        local diff = half_away(113*(10*ags-tee[1]),tee[2])
        local exceptional = 0
        if p.index and p.index-diff >= 70 then exceptional = p.index-diff >= 100 and 20 or 10 end
        local r = {day=day,course=c.id,tee=t[4],scores=scores,handicap=hcp,adjusted=adjusted,ags=ags,diff=diff,exceptional=exceptional,
            before_index=p.index,before_records=#p.records,before_calculation=p.calculation}
        p.rounds[#p.rounds+1] = r
        update_index(p,day)
        if p.index ~= nil then p.records[#p.records+1] = {day,p.index} end
        local extra = exceptional == 0 and '' or ' exceptional ' .. signed_text(-exceptional)
        emit('round ' .. p.id .. ' ' .. #p.rounds .. ': ags ' .. ags .. ' diff ' .. signed_text(diff) .. extra .. ' index ' .. index_text(p.index))
    elseif cmd == 'REMOVE' then
        local p = get_player(t[2])
        if #p.rounds == 0 then fail('no rounds') end
        local number = #p.rounds
        local r = table.remove(p.rounds)
        p.index,p.calculation = r.before_index,r.before_calculation
        while #p.records > r.before_records do table.remove(p.records) end
        emit('removed ' .. p.id .. ' ' .. number .. ': index ' .. index_text(p.index))
    elseif cmd == 'INDEX' or cmd == 'HISTORY' or cmd == 'LOWINDEX' or cmd == 'COURSEHCP' or cmd == 'CARD' or cmd == 'STATS' then
        local p = get_player(t[2])
        if cmd == 'INDEX' then
            local text = 'index ' .. p.id .. ': ' .. index_text(p.index) .. ' rounds ' .. #p.rounds
            local calc = p.calculation
            if calc then
                text = text .. ' lowest ' .. calc.k .. ' average ' .. signed_text(calc.average) .. ' adjustment ' .. signed_text(calc.adjustment)
                if calc.low ~= nil then text = text .. ' low ' .. index_text(calc.low) end
                if calc.hard then text = text .. ' hard cap' elseif calc.soft then text = text .. ' soft cap' end
                if calc.maximum then text = text .. ' maximum' end
            end
            emit(text)
        elseif cmd == 'HISTORY' then
            emit('history ' .. p.id .. ': rounds ' .. #p.rounds)
            local items = eligible(p)
            local counted = {}
            for _,item in ipairs(counting(items)) do counted[item.number] = true end
            for _,item in ipairs(items) do
                local r = item.round
                local text = item.number .. ' day ' .. r.day .. ' ' .. r.course .. ' ' .. r.tee .. ' ags ' .. r.ags .. ' diff ' .. signed_text(r.diff)
                if item.adjusted ~= r.diff then text = text .. ' adjusted ' .. signed_text(item.adjusted) end
                if counted[item.number] then text = text .. ' *' end
                emit(text)
            end
        elseif cmd == 'LOWINDEX' then
            local low = low_index(p,tonumber(t[3]))
            local text = low and index_text(low[2]) .. ' day ' .. low[1] or 'none'
            emit('lowindex ' .. p.id .. ' ' .. t[3] .. ': ' .. text)
        elseif cmd == 'COURSEHCP' then
            local c,tee = tee_check(t[3],t[4])
            if p.index == nil then fail('no index') end
            local hcp = course_handicap(p.index,c,tee)
            emit('coursehcp ' .. p.id .. ' ' .. c.id .. ' ' .. t[4] .. ': ' .. handicap_text(hcp) .. ' strokes ' .. table.concat(allocate(hcp,c.si),' '))
        elseif cmd == 'CARD' then
            local number = tonumber(t[3])
            local r = p.rounds[number]
            if not r then fail('unknown round') end
            local c = courses[r.course]
            local strokes = allocate(r.handicap or 0,c.si)
            local nets,points = hole_values(r,strokes,c)
            emit('card ' .. p.id .. ' ' .. number .. ': ' .. r.course .. ' ' .. r.tee .. ' day ' .. r.day .. ' handicap ' .. handicap_text(r.handicap))
            for h = 1,18 do
                emit(table.concat({h,c.pars[h],c.si[h],r.scores[h],r.adjusted[h],strokes[h],nets[h] == false and '-' or nets[h],points[h]},' '))
                local ranges = {}
                if h == 9 then ranges = {{'OUT',1,9}} elseif h == 18 then ranges = {{'IN',10,18},{'TOTAL',1,18}} end
                for _,range in ipairs(ranges) do
                    local raw,net,complete = 0,0,true
                    for i = range[2],range[3] do
                        if nets[i] == false then complete = false else raw,net = raw+tonumber(r.scores[i]),net+nets[i] end
                    end
                    emit(table.concat({range[1],sum(c.pars,range[2],range[3]),complete and raw or '-',sum(r.adjusted,range[2],range[3]),sum(strokes,range[2],range[3]),complete and net or '-',sum(points,range[2],range[3])},' '))
                end
            end
            emit('ags ' .. r.ags .. ' diff ' .. signed_text(r.diff))
        else
            local counts = {eagles=0,birdies=0,pars=0,bogeys=0,doubles=0,others=0,pickups=0}
            local sums,numbers,totals = {[3]=0,[4]=0,[5]=0},{[3]=0,[4]=0,[5]=0},{}
            for _,r in ipairs(p.rounds) do
                local c = courses[r.course]
                local total,complete = 0,true
                for h,score in ipairs(r.scores) do
                    local value = tonumber(score)
                    if not value then
                        complete = false
                        if score == 'X' then counts.pickups = counts.pickups+1 end
                    else
                        local par = c.pars[h]
                        local relative,category = value-par,nil
                        if relative <= -2 then category = 'eagles'
                        elseif relative == -1 then category = 'birdies'
                        elseif relative == 0 then category = 'pars'
                        elseif relative == 1 then category = 'bogeys'
                        elseif relative == 2 then category = 'doubles'
                        else category = 'others' end
                        counts[category] = counts[category]+1
                        sums[par],numbers[par],total = sums[par]+value,numbers[par]+1,total+value
                    end
                end
                if complete then totals[#totals+1] = total end
            end
            local best = #totals == 0 and '-' or math.min(table.unpack(totals))
            emit('stats ' .. p.id .. ': rounds ' .. #p.rounds .. ' best ' .. best .. ' average ' .. mean_text(sum(totals),#totals) .. ' eagles ' .. counts.eagles .. ' birdies ' .. counts.birdies .. ' pars ' .. counts.pars .. ' bogeys ' .. counts.bogeys .. ' doubles ' .. counts.doubles .. ' others ' .. counts.others .. ' pickups ' .. counts.pickups .. ' par3 ' .. mean_text(sums[3],numbers[3]) .. ' par4 ' .. mean_text(sums[4],numbers[4]) .. ' par5 ' .. mean_text(sums[5],numbers[5]))
        end
    elseif cmd == 'HCPTABLE' then
        local c,tee = tee_check(t[2],t[3])
        local first,last = tonumber(t[4]),tonumber(t[5])
        if first < -100 or first > last or last > 540 then fail('invalid index') end
        emit('hcptable ' .. c.id .. ' ' .. t[3] .. ': ' .. index_text(first) .. ' to ' .. index_text(last))
        local start,hcp = first,course_handicap(first,c,tee)
        for i = first+1,last+1 do
            local next_hcp = i <= last and course_handicap(i,c,tee) or nil
            if next_hcp ~= hcp then
                emit(index_text(start) .. ' to ' .. index_text(i-1) .. ': ' .. handicap_text(hcp))
                start,hcp = i,next_hcp
            end
        end
    elseif cmd == 'HOLESTATS' then
        local c = get_course(t[2])
        local sums,numbers,holes,ranks = {},{},{},{}
        for h = 1,18 do sums[h],numbers[h],holes[h] = 0,0,h end
        local rounds = 0
        for _,p in pairs(players) do
            for _,r in ipairs(p.rounds) do
                if r.course == c.id then
                    rounds = rounds+1
                    for h,score in ipairs(r.scores) do
                        local value = tonumber(score)
                        if value then sums[h],numbers[h] = sums[h]+value,numbers[h]+1 end
                    end
                end
            end
        end
        table.sort(holes,function(a,b)
            if numbers[a] == 0 or numbers[b] == 0 then
                if (numbers[a] == 0) ~= (numbers[b] == 0) then return numbers[a] ~= 0 end
                return a < b
            end
            local left = (sums[a]-c.pars[a]*numbers[a])*numbers[b]
            local right = (sums[b]-c.pars[b]*numbers[b])*numbers[a]
            if left ~= right then return left > right end
            return a < b
        end)
        for rank,h in ipairs(holes) do ranks[h] = rank end
        emit('holestats ' .. c.id .. ': rounds ' .. rounds)
        for h = 1,18 do emit(h .. ' par ' .. c.pars[h] .. ' si ' .. c.si[h] .. ' scores ' .. numbers[h] .. ' avg ' .. mean_text(sums[h],numbers[h]) .. ' rank ' .. ranks[h]) end
    elseif cmd == 'PLAYERS' then
        local all = {}
        for _,p in pairs(players) do all[#all+1] = p end
        table.sort(all,function(a,b)
            if (a.index == nil) ~= (b.index == nil) then return a.index ~= nil end
            if a.index ~= b.index then return a.index < b.index end
            return a.id < b.id
        end)
        emit('players ' .. #all)
        for _,p in ipairs(all) do emit(p.id .. ' ' .. p.name .. ' ' .. index_text(p.index) .. ' rounds ' .. #p.rounds) end
    elseif cmd == 'EVENT' then
        if events[t[2]] then fail('duplicate event') end
        tee_check(t[4],t[5])
        local allowance = tonumber(t[7])
        if allowance < 1 or allowance > 100 then fail('invalid allowance') end
        local ids = slice(t,8)
        for _,id in ipairs(ids) do get_player(id) end
        local n,valid,seen = #ids,false,{}
        if t[3] == 'MATCH' or t[3] == 'NASSAU' then valid = n == 2
        elseif t[3] == 'FOURBALL' then valid = n == 4
        elseif t[3] == 'BETTERBALL' then valid = n == 4 or n == 6 or n == 8
        else valid = n >= 2 and n <= 8 end
        for _,id in ipairs(ids) do
            if seen[id] then valid = false end
            seen[id] = true
        end
        if not valid then fail('invalid players') end
        events[t[2]] = {id=t[2],format=t[3],course=t[4],tee=t[5],day=tonumber(t[6]),allowance=allowance,players=ids}
        event_order[#event_order+1] = t[2]
    elseif cmd == 'RESULTS' then
        if not events[t[2]] then fail('unknown event') end
        out = result_lines(events[t[2]])
    elseif cmd == 'MERIT' then
        local totals,counted = {},0
        for _,id in ipairs(event_order) do
            local e = events[id]
            if e.format == 'STROKE' or e.format == 'STABLEFORD' or e.format == 'PAR' then
                local ok,ctx = pcall(event_context,e)
                if ok then
                    counted = counted+1
                    for _,player in ipairs(e.players) do
                        if not totals[player] then totals[player] = {0,0,0} end
                        totals[player][3] = totals[player][3]+1
                    end
                    for rank,player in ipairs(ranking(e,ctx)) do
                        totals[player][1] = totals[player][1]+({10,8,6,5,4,3,2,1})[rank]
                        if rank == 1 then totals[player][2] = totals[player][2]+1 end
                    end
                end
            end
        end
        local ids = {}
        for id in pairs(totals) do ids[#ids+1] = id end
        table.sort(ids,function(a,b)
            if totals[a][1] ~= totals[b][1] then return totals[a][1] > totals[b][1] end
            if totals[a][2] ~= totals[b][2] then return totals[a][2] > totals[b][2] end
            return a < b
        end)
        emit('merit: events ' .. counted)
        for rank,id in ipairs(ids) do emit(rank .. ' ' .. id .. ' ' .. totals[id][1] .. ' wins ' .. totals[id][2] .. ' played ' .. totals[id][3]) end
    end
    return out
end
local n = tonumber(io.read('*l'))
for _ = 1,n do
    local ok,out = pcall(execute,io.read('*l'))
    if ok then
        for _,line in ipairs(out) do io.write(line,'\n') end
    else
        io.write('ERROR ',out,'\n')
    end
end
