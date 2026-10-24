local function copy(v)
    if type(v) ~= 'table' then return v end
    local r = {}; for k, x in pairs(v) do r[k] = copy(x) end
    return r
end
local function words(s)
    local a = {}; for x in s:gmatch('%S+') do a[#a+1] = x end
    return a
end
local function initial(score)
    local own = {}; for p = 0,25 do own[p] = 0 end
    own[24],own[13],own[8],own[6] = 2,5,3,5
    return {pos={copy(own),copy(own)},side=1,cube=1,owner=0,pending=false,over=false,score=copy(score or {0,0})}
end
local function color(x) return x == 1 and 'W' or 'B' end
local function positionKey(pos)
    local a = {}; for x = 1,2 do for p = 0,25 do a[#a+1] = pos[x][p] end end
    return table.concat(a,',')
end
local function pairLess(a,b) return a[1] > b[1] or a[1] == b[1] and a[2] > b[2] end
local function keyLess(a,b)
    for i = 1,math.min(#a,#b) do
        if a[i][1] ~= b[i][1] or a[i][2] ~= b[i][2] then return pairLess(a[i],b[i]) end
    end
    return #a > #b
end
local function notation(moves,hits)
    local key = copy(moves); table.sort(key,pairLess)
    while true do
        local ai,bi
        for i,a in ipairs(key) do
            if a[2] > 0 and not hits[a[2]] then
                for j,b in ipairs(key) do if b[1] == a[2] then ai,bi = i,j; break end end
            end
            if ai then break end
        end
        if not ai then break end
        local a,b = key[ai],key[bi]
        table.remove(key,math.max(ai,bi)); table.remove(key,math.min(ai,bi))
        key[#key+1] = {a[1],b[2]}; table.sort(key,pairLess)
    end
    local parts,marked,i = {},{},1
    while i <= #key do
        local s,t = key[i][1],key[i][2]
        local j = i+1
        while j <= #key and key[j][1] == s and key[j][2] == t do j = j+1 end
        local text = (s == 25 and 'bar' or s) .. '/' .. (t == 0 and 'off' or t)
        if hits[t] and not marked[t] then text = text .. '*'; marked[t] = true end
        if j-i > 1 then text = text .. '(' .. j-i .. ')' end
        parts[#parts+1] = text; i = j
    end
    return key,#parts == 0 and 'none' or table.concat(parts,' ')
end
local function enumerate(pos,side,d1,d2)
    local all = {}
    local dice = d1 == d2 and {d1,d1,d1,d1} or {d1,d2}
    local function visit(board,remaining,moves,hits,used)
        local key,text = notation(moves,hits)
        all[#all+1] = {pos=board,key=key,text=text,count=#moves,used=used,id=positionKey(board)}
        local own,opponent = board[side],board[3-side]
        local tried = {}
        for di,d in ipairs(remaining) do
            if not tried[d] then
                tried[d] = true
                local sources = {}
                if own[25] > 0 then sources = {25}
                else for p = 1,24 do if own[p] > 0 then sources[#sources+1] = p end end end
                for _,s in ipairs(sources) do
                    local t,valid = math.max(0,s-d),true
                    if t > 0 then valid = opponent[25-t] < 2
                    else
                        if own[25] > 0 then valid = false end
                        for p = 7,24 do if own[p] > 0 then valid = false end end
                        if s < d then for p = s+1,6 do if own[p] > 0 then valid = false end end end
                    end
                    if valid then
                        local nextBoard,nextMoves,nextHits,nextUsed,rest = copy(board),copy(moves),copy(hits),copy(used),copy(remaining)
                        nextBoard[side][s] = nextBoard[side][s]-1
                        nextBoard[side][t] = nextBoard[side][t]+1
                        if t > 0 and opponent[25-t] == 1 then
                            nextBoard[3-side][25-t] = 0; nextBoard[3-side][25] = nextBoard[3-side][25]+1; nextHits[t] = true
                        end
                        nextMoves[#nextMoves+1] = {s,t}; nextUsed[#nextUsed+1] = d; table.remove(rest,di)
                        visit(nextBoard,rest,nextMoves,nextHits,nextUsed)
                    end
                end
            end
        end
    end
    visit(pos,dice,{},{},{})
    local maximum,larger = 0,false
    for _,p in ipairs(all) do maximum = math.max(maximum,p.count) end
    if maximum == 1 and d1 ~= d2 then
        for _,p in ipairs(all) do if p.count == 1 and p.used[1] == math.max(d1,d2) then larger = true end end
    end
    local unique,legal = {},{}
    for _,p in ipairs(all) do
        if p.count == maximum and (not larger or p.used[1] == math.max(d1,d2)) and not unique[p.id] then
            unique[p.id] = true; legal[#legal+1] = p
        end
    end
    table.sort(legal,function(a,b) return keyLess(a.key,b.key) end)
    return legal,all,maximum
end
local function pips(own)
    local n = 0; for p = 1,25 do n = n+p*own[p] end
    return n
end
local function evaluation(pos,side)
    local own,opp = pos[side],pos[3-side]
    local p,s,h,r,a,run = pips(opp)-pips(own),0,0,0,0,0
    for point = 1,24 do
        if own[point] == 1 then
            local distances = {}
            for q = 0,point-1 do if opp[25-q] > 0 then distances[point-q] = true end end
            for d1 = 1,6 do for d2 = 1,6 do
                if distances[d1] or distances[d2] or distances[d1+d2] or (d1 == d2 and (distances[3*d1] or distances[4*d1])) then s = s+1 end
            end end
        end
        if own[point] >= 2 then
            if point <= 6 then h = h+1 end
            if point >= 19 then a = a+1 end
            run = run+1; r = math.max(r,run)
        else run = 0 end
    end
    local g = opp[25]-own[25]
    return {2*p-s+4*h+3*r+3*a+6*g,p,s,h,r,a,g}
end
local function keith(own)
    local n = pips(own)+2*math.max(own[1]-1,0)+math.max(own[2]-1,0)+math.max(own[3]-3,0)
    for p = 4,6 do if own[p] == 0 then n = n+1 end end
    return n
end
local function contact(pos)
    local w,b = 0,25
    for p = 1,24 do if pos[1][p] > 0 then w = math.max(w,p) end; if pos[2][p] > 0 then b = math.min(b,25-p) end end
    if pos[1][25] > 0 then w = 25 end
    if pos[2][25] > 0 then b = 0 end
    return w > b
end
local function cubeDecision(state,forbidden)
    local x = state.side
    if state.owner == 3-x or state.cube == 64 or forbidden then return 'unavailable' end
    if contact(state.pos) then
        local e = evaluation(state.pos,x)[1]
        if e < 60 then return 'no double' end
        return e <= 100 and 'double take' or 'double drop'
    end
    local v = 8*keith(state.pos[x])-7*keith(state.pos[3-x])
    local limit = state.owner == 0 and 28 or 21
    if v > limit then return 'no double' end
    return v >= 14 and 'double take' or 'double drop'
end
local function endGame(state,winner,kind)
    if not kind then
        local opp = state.pos[3-winner]
        local back = opp[25] > 0
        for p = 19,24 do if opp[p] > 0 then back = true end end
        kind = opp[0] > 0 and 'single' or (back and 'backgammon' or 'gammon')
    end
    local multiplier = ({single=1,gammon=2,backgammon=3,drop=1})[kind]
    local points = multiplier*state.cube
    state.over,state.pending = true,false
    state.score[winner] = state.score[winner]+points
    return {winner,kind,points}
end
local function applyPlay(state,play)
    state.pos = copy(play.pos)
    if state.pos[state.side][0] == 15 then return endGame(state,state.side) end
    state.side = 3-state.side
end
local function ranked(legal,side)
    local result = {}
    for i,p in ipairs(legal) do result[#result+1] = {evaluation(p.pos,side)[1],i,p} end
    table.sort(result,function(a,b) return a[1] > b[1] or a[1] == b[1] and a[2] < b[2] end)
    return result
end
local function validPoint(s)
    return s and s:match('^[1-9]%d?$') and tonumber(s) <= 24
end
local function parsePlay(tokens)
    if #tokens == 1 and tokens[1] == 'none' then return {} end
    local moves = {}
    local function syntax() error('ILLEGAL syntax',0) end
    for _,token in ipairs(tokens) do
        local path,k = token:match('^(.-)%(([234])%)$')
        if not path then path,k = token,1 else k = tonumber(k) end
        local fields = {}
        for field in (path .. '/'):gmatch('(.-)/') do fields[#fields+1] = field end
        if #fields < 2 then syntax() end
        local values = {}
        for i,word in ipairs(fields) do
            if i == 1 then
                if word == 'bar' then values[i] = 25
                elseif validPoint(word) then values[i] = tonumber(word) else syntax() end
            else
                if word == 'off' then values[i] = 0
                else
                    local point = word:gsub('%*$','')
                    if not validPoint(point) then syntax() end
                    values[i] = tonumber(point)
                end
                if values[i-1] <= values[i] then syntax() end
            end
        end
        for i = 1,#values-1 do for _ = 1,k do moves[#moves+1] = {values[i],values[i+1]} end end
    end
    return moves
end
local function randomStream(seed)
    local value = seed
    return function() value = value*48271%2147483647; return value end
end
local function resultLine(result) return 'result ' .. color(result[1]) .. ' ' .. result[2] .. ' ' .. result[3] end
local function simulate(state,rng,strategies,opening,target,scores,crawford,verbose)
    state = copy(state)
    local dice
    local function die() return rng()%6+1 end
    if opening then
        repeat dice = {die(),die()} until dice[1] ~= dice[2]
        state.side = dice[1] > dice[2] and 1 or 2
    end
    local first,turn,plays = state.side,1,0
    while true do
        local x = state.side
        if not opening or turn ~= 1 then
            local forbidden = target and (crawford or scores[x]+state.cube >= target)
            local decision = cubeDecision(state,forbidden)
            if decision == 'double take' or decision == 'double drop' then
                if verbose then print(turn .. ' ' .. color(x) .. ' doubles ' .. state.cube*2) end
                if decision == 'double drop' then
                    if verbose then print(turn .. ' ' .. color(3-x) .. ' drops') end
                    return endGame(state,x,'drop'),plays,first
                end
                if verbose then print(turn .. ' ' .. color(3-x) .. ' takes') end
                state.cube,state.owner = state.cube*2,3-x
            end
            dice = {die(),die()}
        end
        local legal = enumerate(state.pos,x,dice[1],dice[2])
        local play
        if strategies[x] == 'FIRST' then play = legal[1]
        elseif strategies[x] == 'RANDOM' then play = legal[rng()%#legal+1]
        else play = ranked(legal,x)[1][3] end
        if verbose then print(turn .. ' ' .. color(x) .. ' ' .. dice[1] .. '-' .. dice[2] .. ' ' .. play.text) end
        local result = applyPlay(state,play)
        plays = plays+1
        if result then return result,plays,first end
        turn = turn+1
    end
end
local function numeric(s,lo,hi) return s and s:match('^%d+$') and tonumber(s) >= lo and tonumber(s) <= hi end
local noargs,known,limited,pendingLimited = {},{},{},{}
for _,c in ipairs(words('NEW SHOW BOARD PIPS RACE EVAL SHOTS CUBE DOUBLE TAKE DROP SCORE HISTORY')) do noargs[c],known[c] = true,true end
for _,c in ipairs(words('POS MOVES PLAY AUTO HINT RESIGN UNDO REDO GAME MATCH STATS')) do known[c] = true end
for _,c in ipairs(words('RACE MOVES PLAY AUTO HINT EVAL SHOTS CUBE DOUBLE TAKE DROP RESIGN GAME')) do limited[c] = true end
for _,c in ipairs(words('PLAY AUTO CUBE DOUBLE RESIGN GAME')) do pendingLimited[c] = true end
local state,history,redo = initial(),{},{}
local function requireThat(valid,message) if not valid then error(message,0) end end
local function run(line)
    local a = words(line); local cmd = table.remove(a,1)
    requireThat(known[cmd],'ERROR unknown command')
    local valid,pos = true,nil
    if noargs[cmd] then valid = #a == 0
    elseif cmd == 'POS' then
        local points = {}; for v in (a[1] or ''):gmatch('[^,]+') do points[#points+1] = tonumber(v) end
        valid = #a == 4 and #points == 24 and numeric(a[2],0,15) and numeric(a[3],0,15) and (a[4] == 'W' or a[4] == 'B')
        if valid then
            pos = initial().pos
            for x = 1,2 do for p = 0,25 do pos[x][p] = 0 end end
            for p,v in ipairs(points) do if v > 0 then pos[1][p] = v else pos[2][25-p] = -v end end
            pos[1][25],pos[2][25] = tonumber(a[2]),tonumber(a[3])
            for x = 1,2 do
                local count = 0; for p = 1,25 do count = count+pos[x][p] end
                pos[x][0] = 15-count
                if pos[x][0] < 0 or pos[x][0] > 14 then valid = false end
            end
        end
    elseif cmd == 'MOVES' or cmd == 'AUTO' or cmd == 'PLAY' or cmd == 'HINT' then
        valid = numeric(a[1],1,6) and numeric(a[2],1,6)
        if cmd == 'PLAY' then valid = valid and #a >= 3
        elseif cmd == 'HINT' then valid = valid and #a == 3 and numeric(a[3],1,1000)
        else valid = valid and #a == 2 end
    elseif cmd == 'RESIGN' then valid = #a == 1 and (a[1] == 'single' or a[1] == 'gammon' or a[1] == 'backgammon')
    elseif cmd == 'UNDO' or cmd == 'REDO' then valid = #a == 1 and numeric(a[1],1,1000)
    elseif cmd == 'GAME' then
        local strategies = {BEST=true,FIRST=true,RANDOM=true}
        valid = #a == 3 and numeric(a[1],1,2147483646) and strategies[a[2]] and strategies[a[3]]
    elseif cmd == 'MATCH' or cmd == 'STATS' then valid = #a == 2 and numeric(a[1],1,cmd == 'MATCH' and 15 or 50) and numeric(a[2],1,2147483646) end
    requireThat(valid,cmd == 'POS' and 'ERROR bad position' or 'ERROR bad arguments')
    requireThat(not limited[cmd] or not state.over,'ERROR game over')
    requireThat(not pendingLimited[cmd] or not state.pending,'ERROR double pending')
    local side = state.side
    if cmd == 'NEW' or cmd == 'POS' then
        state = initial(state.score)
        if cmd == 'POS' then state.pos,state.side = pos,a[4] == 'W' and 1 or 2 end
        history,redo = {},{}; print('OK')
    elseif cmd == 'SHOW' then
        local points = {}; for p = 1,24 do points[p] = state.pos[1][p]-state.pos[2][25-p] end
        print('POS ' .. table.concat(points,',') .. ' ' .. state.pos[1][25] .. ' ' .. state.pos[2][25] .. ' ' .. color(side))
    elseif cmd == 'BOARD' then
        local function boardLine(top,row)
            local fields = {}
            for i = 1,12 do
                local p = top and i+12 or 13-i
                local value = p
                if row then
                    local w,b = state.pos[1][p],state.pos[2][25-p]; local count = math.max(w,b)
                    value = row == 5 and count > 5 and count or (count >= row and (w > 0 and 'W' or 'B') or '.')
                end
                fields[#fields+1] = string.format('%3s',tostring(value))
                if i == 6 then fields[#fields+1] = ' |' end
            end
            print(table.concat(fields))
        end
        boardLine(true)
        for row = 1,5 do boardLine(true,row) end
        local owner = state.owner == 0 and 'center' or color(state.owner)
        local status = state.over and 'game over' or color(side) .. (state.pending and ' doubles' or ' to move')
        print('bar W' .. state.pos[1][25] .. ' B' .. state.pos[2][25] .. ' | off W' .. state.pos[1][0] .. ' B' .. state.pos[2][0] .. ' | cube ' .. state.cube .. ' ' .. owner .. ' | ' .. status)
        for row = 5,1,-1 do boardLine(false,row) end
        boardLine(false)
    elseif cmd == 'PIPS' then print('pips W ' .. pips(state.pos[1]) .. ' B ' .. pips(state.pos[2]))
    elseif cmd == 'RACE' then print(contact(state.pos) and 'contact' or 'race W ' .. keith(state.pos[1]) .. ' B ' .. keith(state.pos[2]))
    elseif cmd == 'EVAL' then
        local labels,values = {'eval','pips','blots','home','prime','anchors','bar'},evaluation(state.pos,side)
        local parts = {}; for i,label in ipairs(labels) do parts[#parts+1] = label .. ' ' .. values[i] end
        print(table.concat(parts,' '))
    elseif cmd == 'MOVES' or cmd == 'HINT' or cmd == 'AUTO' or cmd == 'PLAY' then
        local d1,d2 = tonumber(a[1]),tonumber(a[2])
        local legal,all,maximum = enumerate(state.pos,side,d1,d2)
        if cmd == 'MOVES' then for _,p in ipairs(legal) do print(p.text) end; print('total ' .. #legal)
        elseif cmd == 'HINT' then
            local list = ranked(legal,side)
            for i = 1,math.min(#list,tonumber(a[3])) do print(list[i][1] .. ' ' .. list[i][3].text) end
        else
            local play,value
            if cmd == 'AUTO' then local best = ranked(legal,side)[1]; value,play = best[1],best[3]
            else
                local tokens = {}; for i = 3,#a do tokens[#tokens+1] = a[i] end
                local moves = parsePlay(tokens)
                local final,destinations = copy(state.pos),{}
                for _,m in ipairs(moves) do final[side][m[1]] = final[side][m[1]]-1; final[side][m[2]] = final[side][m[2]]+1; if m[2] > 0 then destinations[m[2]] = true end end
                for t in pairs(destinations) do
                    if state.pos[3-side][25-t] == 1 then final[3-side][25-t] = 0; final[3-side][25] = final[3-side][25]+1 end
                end
                for p = 1,25 do requireThat(final[side][p] >= 0,'ILLEGAL no checker') end
                if final[side][25] > 0 then for _,m in ipairs(moves) do requireThat(m[1] == 25,'ILLEGAL bar') end end
                for t in pairs(destinations) do requireThat(state.pos[3-side][25-t] < 2,'ILLEGAL blocked') end
                local bearing = false; for _,m in ipairs(moves) do if m[2] == 0 then bearing = true end end
                if bearing then
                    requireThat(final[side][25] == 0,'ILLEGAL bear-off')
                    for p = 7,24 do requireThat(final[side][p] == 0,'ILLEGAL bear-off') end
                end
                local key = positionKey(final)
                for _,p in ipairs(legal) do if p.id == key then play = p; break end end
                if not play then
                    local possible,fewer = false,false
                    for _,p in ipairs(all) do if p.id == key then possible = true; if p.count < maximum then fewer = true end end end
                    requireThat(possible,'ILLEGAL impossible')
                    error(fewer and 'ILLEGAL too few dice' or 'ILLEGAL larger die required',0)
                end
            end
            local before = copy(state)
            local result = applyPlay(state,play)
            print('OK ' .. play.text .. (cmd == 'AUTO' and ' eval ' .. value or ''))
            if result then print(resultLine(result)) end
            history[#history+1] = {color(side) .. ' ' .. d1 .. '-' .. d2 .. ' ' .. play.text,before,copy(state)}
            redo = {}
        end
    elseif cmd == 'SHOTS' then
        local blots,counts = {},{}
        for p = 24,1,-1 do if state.pos[side][p] == 1 then blots[#blots+1] = p; counts[p] = 0 end end
        local total,rolls = 0,{}
        for d1 = 6,1,-1 do for d2 = d1,1,-1 do
            local legal = enumerate(state.pos,3-side,d1,d2)
            local hit = {}
            for _,p in ipairs(blots) do for _,play in ipairs(legal) do if play.pos[side][p] == 0 then hit[#hit+1] = p; break end end end
            if #hit > 0 then
                local weight = d1 == d2 and 1 or 2; total = total+weight; rolls[#rolls+1] = d1 .. '-' .. d2
                for _,p in ipairs(hit) do counts[p] = counts[p]+weight end
            end
        end end
        print('shots ' .. total .. '/36' .. (#rolls > 0 and ' ' .. table.concat(rolls,' ') or ''))
        for _,p in ipairs(blots) do print('blot ' .. p .. ' ' .. counts[p] .. '/36') end
    elseif cmd == 'CUBE' then print('cube ' .. cubeDecision(state))
    elseif cmd == 'DOUBLE' then
        requireThat(state.owner ~= 3-side and state.cube ~= 64,'ERROR cube unavailable')
        state.pending,redo = true,{}; print('OK double ' .. state.cube*2)
    elseif cmd == 'TAKE' or cmd == 'DROP' then
        requireThat(state.pending,'ERROR no double'); state.pending,redo = false,{}
        if cmd == 'TAKE' then state.cube,state.owner = state.cube*2,3-side; print('OK take ' .. state.cube .. ' ' .. color(state.owner))
        else print('OK drop'); print(resultLine(endGame(state,side,'drop'))) end
    elseif cmd == 'RESIGN' then redo = {}; print('OK resign'); print(resultLine(endGame(state,3-side,a[1])))
    elseif cmd == 'SCORE' then print('score W ' .. state.score[1] .. ' B ' .. state.score[2])
    elseif cmd == 'HISTORY' then print('history ' .. #history); for i,entry in ipairs(history) do print(i .. ' ' .. entry[1]) end
    elseif cmd == 'UNDO' or cmd == 'REDO' then
        local n = tonumber(a[1])
        if cmd == 'UNDO' then
            requireThat(n <= #history,'ERROR cannot undo')
            local entries = {}; local start = #history-n+1
            for i = start,#history do entries[#entries+1] = history[i] end
            state = copy(entries[1][2])
            for i = #history,start,-1 do history[i] = nil end
            for i = #entries,1,-1 do table.insert(redo,1,entries[i]) end
        else
            requireThat(n <= #redo,'ERROR cannot redo')
            local entries = {}; for _ = 1,n do entries[#entries+1] = table.remove(redo,1) end
            state = copy(entries[#entries][3])
            for _,e in ipairs(entries) do history[#history+1] = e end
        end
        print('OK')
    elseif cmd == 'GAME' then
        local result = simulate(state,randomStream(tonumber(a[1])),{a[2],a[3]},false,nil,nil,false,true)
        print(resultLine(result))
    elseif cmd == 'MATCH' or cmd == 'STATS' then
        local n,rng = tonumber(a[1]),randomStream(tonumber(a[2]))
        local points,turns,game,crawfordUsed = {0,0},0,0,false
        local kinds,outcomes = {'single','gammon','backgammon','drop'},{}
        for _,k in ipairs(kinds) do outcomes[k] = {0,0} end
        while cmd == 'STATS' and game < n or cmd == 'MATCH' and math.max(points[1],points[2]) < n do
            game = game+1
            local crawford = cmd == 'MATCH' and not crawfordUsed and math.max(points[1],points[2]) == n-1
            if crawford then crawfordUsed = true end
            local result,played,first = simulate(initial(),rng,{'BEST','BEST'},true,cmd == 'MATCH' and n or nil,points,crawford,false)
            local winner,kind,value = result[1],result[2],result[3]
            points[winner] = points[winner]+value; outcomes[kind][winner] = outcomes[kind][winner]+1; turns = turns+played
            if cmd == 'MATCH' then print('game ' .. game .. (crawford and ' crawford' or '') .. ' start ' .. color(first) .. ' turns ' .. played .. ' ' .. resultLine(result) .. ' score ' .. points[1] .. '-' .. points[2]) end
        end
        if cmd == 'MATCH' then print('match ' .. color(points[1] >= n and 1 or 2) .. ' ' .. points[1] .. '-' .. points[2])
        else
            for _,k in ipairs(kinds) do print(k .. ' W ' .. outcomes[k][1] .. ' B ' .. outcomes[k][2]) end
            print('points W ' .. points[1] .. ' B ' .. points[2]); print('turns ' .. turns)
        end
    end
end
local n = tonumber(io.read())
for _ = 1,n do
    local ok,message = pcall(run,io.read())
    if not ok then print(message) end
end
