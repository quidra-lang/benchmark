local channels = {'NOTE_OFF','NOTE_ON','POLY_PRESSURE','CONTROL','PROGRAM','CHANNEL_PRESSURE','PITCH_BEND'}
local texts = {'TEXT_EVENT','COPYRIGHT','TRACK_NAME','INSTRUMENT_NAME','LYRIC','MARKER','CUE_POINT'}
local metas = {[0]='SEQUENCE_NUMBER',[32]='CHANNEL_PREFIX',[47]='END_OF_TRACK',[81]='TEMPO',[84]='SMPTE_OFFSET',[88]='TIME_SIGNATURE',[89]='KEY_SIGNATURE',[127]='SEQUENCER_SPECIFIC'}
for i, s in ipairs(texts) do metas[i] = s end
local major = {'Cb','Gb','Db','Ab','Eb','Bb','F','C','G','D','A','E','B','F#','C#'}
local minor = {'Ab','Eb','Bb','F','C','G','D','A','E','B','F#','C#','G#','D#','A#'}
local notes, noteNumbers = {}, {}
local pitches = {'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'}
for p = 0, 127 do notes[p] = pitches[p%12+1] .. (p//12-1); noteNumbers[notes[p]] = p end
local function copy(v)
    if type(v) ~= 'table' then return v end
    local r = {}; for k, x in pairs(v) do r[k] = copy(x) end
    return r
end
local function words(s)
    local r = {}; for x in (s or ''):gmatch('%S+') do r[#r+1] = x end
    return r
end
local function append(a, b) for _, x in ipairs(b) do a[#a+1] = x end end
local function integer(a)
    local n = 0; for _, x in ipairs(a) do n = n*256+x end
    return n
end
local function big(n, count)
    local r = {}; for i = count, 1, -1 do r[i] = n%256; n = n//256 end
    return r
end
local function vlq(n)
    local r = {n%128}; n = n//128
    while n > 0 do table.insert(r,1,n%128+128); n = n//128 end
    return r
end
local function bytes(s)
    local r = {}; for i = 1, #s do r[i] = s:byte(i) end
    return r
end
local function hex(a)
    local r = {}; for _, x in ipairs(a) do r[#r+1] = string.format('%02X',x) end
    return table.concat(r)
end
local function unhex(s)
    local r = {}; for x in s:gmatch('..') do r[#r+1] = tonumber(x,16) end
    return r
end
local function eventType(e)
    if e.s < 240 then return channels[(e.s>>4)-7] end
    if e.s ~= 255 then return e.s == 240 and 'SYSEX' or 'SYSEX_ESCAPE' end
    return metas[e.m] or 'META'
end
local function eventFields(e)
    local d, s = e.d, e.s
    if s < 240 then
        local ch, kind = (s&15)+1, s>>4
        if kind <= 10 then return {ch,notes[d[1]],d[2]} end
        if kind == 14 then return {ch,d[1]+128*d[2]-8192} end
        local r = {ch}; append(r,d); return r
    end
    if s ~= 255 or e.m == 127 or not metas[e.m] then
        local r = {}
        if s == 255 and not metas[e.m] then r[#r+1] = string.format('%02X',e.m) end
        r[#r+1] = #d
        if #d > 0 then r[#r+1] = hex(d) end
        return r
    end
    if e.m == 0 or e.m == 81 then return {integer(d)} end
    if e.m >= 1 and e.m <= 7 then
        local r = {}; for _, x in ipairs(d) do r[#r+1] = string.char(x) end
        return {'"' .. table.concat(r) .. '"'}
    end
    if e.m == 32 then return {d[1]+1} end
    if e.m == 47 then return {} end
    if e.m == 84 then return d end
    if e.m == 88 then return {d[1] .. '/' .. (1<<d[2]),d[3],d[4]} end
    local sf = d[1] >= 128 and d[1]-256 or d[1]
    return {(d[2] == 0 and major or minor)[sf+8],d[2] == 0 and 'major' or 'minor'}
end
local function eventLine(e, tr)
    local a = {e.t,tr,eventType(e)}; append(a,eventFields(e))
    return table.concat(a,' ')
end
local function ordered(song)
    local a = {}
    for i, tr in ipairs(song.tracks) do
        for j, e in ipairs(tr) do a[#a+1] = {e=e,tr=i-1,index=j} end
    end
    table.sort(a,function(x,y)
        if x.e.t ~= y.e.t then return x.e.t < y.e.t end
        if x.tr ~= y.tr then return x.tr < y.tr end
        return x.index < y.index
    end)
    return a
end
local function length(song)
    local n = 0; for _, tr in ipairs(song.tracks) do n = math.max(n,tr[#tr].t) end
    return n
end
local function summary(song)
    local count = 0; for _, tr in ipairs(song.tracks) do count = count+#tr end
    return 'format ' .. song.f .. ' tracks ' .. #song.tracks .. ' division ' .. song.div .. ' events ' .. count
end
local function parseHex(data)
    local p, limit, start = 1,#data+1,1
    local function fail(reason,pos) error('byte ' .. (pos-1) .. ': ' .. reason,0) end
    local function read()
        if p >= limit then fail('truncated event',start) end
        local b = data[p]; p = p+1; return b
    end
    local function variable()
        local at, n = p,0
        for _ = 1, 4 do
            local b = read(); n = n*128+(b&127)
            if b < 128 then return n end
        end
        fail('variable-length value too long',at)
    end
    local function chunk(id)
        local at = p
        if #data-p+1 < 8 then fail('truncated chunk',at) end
        for i = 1, 4 do if data[p+i-1] ~= id:byte(i) then fail('bad chunk id',at) end end
        local n = integer({data[p+4],data[p+5],data[p+6],data[p+7]})
        if p+8+n > #data+1 then fail('truncated chunk',at) end
        p = p+8; return n
    end
    local n = chunk('MThd')
    if n ~= 6 then fail('bad header length',5) end
    local f = data[9]*256+data[10]
    local count = data[11]*256+data[12]
    local division = data[13]*256+data[14]
    if f > 2 then fail('bad format',9) end
    if count == 0 or (f == 0 and count ~= 1) then fail('bad track count',11) end
    if division >= 32768 then fail('smpte timing not supported',13) end
    if division == 0 then fail('bad division',13) end
    p = 15
    local tracks = {}
    for _ = 1, count do
        if p == #data+1 then fail('missing track',p) end
        local size = chunk('MTrk'); limit = p+size
        local tr, tick, running, ended = {},0,nil,false
        while p < limit do
            if ended then fail('event after end of track',p) end
            start = p; tick = tick+variable()
            if p >= limit then fail('truncated event',start) end
            local at, s = p,data[p]
            if s < 128 then
                if not running then fail('data byte without running status',p) end
                s = running
            else p = p+1 end
            local e = {t=tick,s=s,d={}}
            if s < 240 then
                running = s
                local kind = s>>4
                for _ = 1, (kind == 12 or kind == 13) and 1 or 2 do
                    local pos, b = p,read()
                    if b >= 128 then fail('bad data byte',pos) end
                    e.d[#e.d+1] = b
                end
            elseif s == 240 or s == 247 or s == 255 then
                running = nil
                if s == 255 then e.m = read() end
                local size = variable()
                if p+size > limit then fail('truncated event',start) end
                for _ = 1, size do e.d[#e.d+1] = read() end
                if s == 255 then
                    local fixed = {[0]=2,[32]=1,[47]=0,[81]=3,[84]=5,[88]=4,[89]=2}
                    if fixed[e.m] and fixed[e.m] ~= size then fail('bad meta length',at) end
                    local d, bad = e.d,false
                    if e.m == 32 then bad = d[1] > 15
                    elseif e.m == 81 then bad = integer(d) == 0
                    elseif e.m == 88 then bad = d[1] == 0 or d[2] > 6
                    elseif e.m == 89 then bad = (d[1] > 7 and d[1] < 249) or d[2] > 1 end
                    if bad then fail('bad meta data',at) end
                    ended = e.m == 47
                end
            else fail('unknown status byte',at) end
            tr[#tr+1] = e
        end
        if not ended then fail('missing end of track',limit) end
        tracks[#tracks+1] = tr; limit = #data+1
    end
    if p <= #data then fail('extra data',p) end
    return {f=f,div=division,tracks=tracks}
end
local function range(s,a,b)
    local n = tonumber(s)
    return n and n >= a and n <= b
end
local function index(a,x)
    for i, v in ipairs(a) do if x == v then return i end end
end
local function textEvent(line)
    local tick, tr, kind, rest = line:match('^(%S+) (%S+) (%S+) ?(.*)$')
    local e = {t=tonumber(tick),s=255,d={}}
    local ci = index(channels,kind)
    local ti = index(texts,kind)
    local known = ci or ti or kind == 'SYSEX' or kind == 'SYSEX_ESCAPE' or kind == 'META'
    for m, name in pairs(metas) do if name == kind then e.m = m; known = true end end
    if not known then error('unknown event type',0) end
    local f, good = words(rest),true
    if ci then
        local k = ci+7
        good = #f == ((k == 12 or k == 13 or k == 14) and 2 or 3) and range(f[1],1,16)
        if k <= 10 then
            good = good and noteNumbers[f[2]] ~= nil and range(f[3],0,127)
            e.d = {noteNumbers[f[2]],tonumber(f[3])}
        elseif k == 14 then
            good = good and range(f[2],-8192,8191)
            local v = (tonumber(f[2]) or 0)+8192; e.d = {v%128,v//128}
        else
            for i = 2, #f do good = good and range(f[i],0,127); e.d[#e.d+1] = tonumber(f[i]) end
        end
        e.s = k*16+(tonumber(f[1]) or 1)-1
    elseif ti then
        good = #rest >= 2 and rest:sub(1,1) == '"' and rest:sub(-1) == '"' and not rest:sub(2,-2):find('"',1,true)
        if good then e.d = bytes(rest:sub(2,-2)) end
    elseif kind == 'SYSEX' or kind == 'SYSEX_ESCAPE' or kind == 'SEQUENCER_SPECIFIC' or kind == 'META' then
        if kind == 'META' then
            local tt = table.remove(f,1)
            good = tt and tt:match('^[0-9A-F][0-9A-F]$') and not metas[tonumber(tt,16)]
            e.m = tt and tonumber(tt,16) or nil
        elseif kind ~= 'SEQUENCER_SPECIFIC' then e.s = kind == 'SYSEX' and 240 or 247 end
        local n = tonumber(f[1]) or -1
        good = good and range(f[1],0,1000000) and #f == (n == 0 and 1 or 2)
        if n > 0 then good = good and f[2] and #f[2] == 2*n and f[2]:match('^[0-9A-F]+$') end
        if good and n > 0 then e.d = unhex(f[2]) end
    elseif kind == 'SEQUENCE_NUMBER' or kind == 'TEMPO' or kind == 'CHANNEL_PREFIX' then
        local lo, hi = 0,65535
        if kind == 'TEMPO' then lo,hi = 1,16777215 elseif kind == 'CHANNEL_PREFIX' then lo,hi = 1,16 end
        good = #f == 1 and range(f[1],lo,hi)
        if good then e.d = kind == 'CHANNEL_PREFIX' and {tonumber(f[1])-1} or big(tonumber(f[1]),kind == 'TEMPO' and 3 or 2) end
    elseif kind == 'END_OF_TRACK' then good = #f == 0
    elseif kind == 'SMPTE_OFFSET' then
        good = #f == 5
        for _, v in ipairs(f) do good = good and range(v,0,255); e.d[#e.d+1] = tonumber(v) end
    elseif kind == 'TIME_SIGNATURE' then
        local nn, dd = (f[1] or ''):match('^(%-?%d+)/(%-?%d+)$')
        local exponent = index({1,2,4,8,16,32,64},tonumber(dd))
        good = #f == 3 and range(nn,1,255) and exponent and range(f[2],0,255) and range(f[3],0,255)
        if good then e.d = {tonumber(nn),exponent-1,tonumber(f[2]),tonumber(f[3])} end
    elseif kind == 'KEY_SIGNATURE' then
        local keys = f[2] == 'major' and major or minor
        local i = index(keys,f[1])
        good = #f == 2 and (f[2] == 'major' or f[2] == 'minor') and i
        if good then e.d = {(i-8)%256,f[2] == 'major' and 0 or 1} end
    end
    if not good then error('bad value',0) end
    return e,tonumber(tr)
end
local function parseText(lines)
    local h = words(lines[1])
    if #h ~= 4 or h[1] ~= 'HEADER' or not range(h[2],0,2) or not range(h[3],1,65535) or not range(h[4],1,32767) or (tonumber(h[2]) == 0 and tonumber(h[3]) ~= 1) then error('line 1: bad header',0) end
    local count, tracks, c = tonumber(h[3]),{{}},1
    for i = 2, #lines do
        local ok, e, tr = pcall(textEvent,lines[i])
        if not ok then error('line ' .. i .. ': ' .. e,0) end
        local reason
        local ended = #tracks[c] > 0 and eventType(tracks[c][#tracks[c]]) == 'END_OF_TRACK'
        if tr >= count then reason = 'bad track'
        elseif tr < c-1 then reason = 'out of order'
        elseif tr > c-1 and (not ended or tr > c) then reason = 'missing end of track'
        elseif tr == c-1 and ended then reason = 'event after end of track' end
        if reason then error('line ' .. i .. ': ' .. reason,0) end
        if tr == c then c = c+1; tracks[c] = {} end
        if #tracks[c] > 0 and e.t < tracks[c][#tracks[c]].t then error('line ' .. i .. ': out of order',0) end
        tracks[c][#tracks[c]+1] = e
    end
    if c < count or #tracks[c] == 0 or eventType(tracks[c][#tracks[c]]) ~= 'END_OF_TRACK' then error('line ' .. (#lines+1) .. ': missing end of track',0) end
    return {f=tonumber(h[2]),div=tonumber(h[4]),tracks=tracks}
end
local function pairing(song)
    local queues, paired, unmatched = {},{},{}
    for order, item in ipairs(ordered(song)) do
        local e = item.e; local k = e.s>>4
        if k == 8 or k == 9 then
            local key = (e.s&15)*128+e.d[1]
            local on = k == 9 and e.d[2] > 0
            local a = {e=e,tr=item.tr,order=order,on=on}
            queues[key] = queues[key] or {}
            if on then queues[key][#queues[key]+1] = a
            elseif #queues[key] == 0 then unmatched[#unmatched+1] = a
            else
                local first = table.remove(queues[key],1)
                paired[#paired+1] = {on=first.e,off=e,order=first.order,start=first.e.t,length=e.t-first.e.t,ch=(e.s&15)+1,p=e.d[1],v=first.e.d[2]}
            end
        end
    end
    for _, q in pairs(queues) do append(unmatched,q) end
    table.sort(paired,function(a,b)
        if a.start ~= b.start then return a.start < b.start end
        if a.ch ~= b.ch then return a.ch < b.ch end
        if a.p ~= b.p then return a.p < b.p end
        return a.order < b.order
    end)
    table.sort(unmatched,function(a,b) return a.order < b.order end)
    return paired,unmatched
end
local function timePosition(song,tick)
    local s,last,v,st,bar,nn,beat = 0,0,500000,0,1,4,song.div
    for _, item in ipairs(ordered(song)) do
        local e = item.e
        if e.t > tick then break end
        if e.s == 255 and e.m == 81 then s = s+(e.t-last)*v; last,v = e.t,integer(e.d)
        elseif e.s == 255 and e.m == 88 then
            local size = nn*beat
            bar = bar+(e.t-st+size-1)//size
            st,nn,beat = e.t,e.d[1],math.max(1,song.div*4//(1<<e.d[2]))
        end
    end
    local micro, x = (s+(tick-last)*v)//song.div,tick-st
    return micro//1000 .. '.' .. string.format('%03d',micro%1000),bar+x//(nn*beat) .. ':' .. x%(nn*beat)//beat+1 .. ':' .. x%beat
end
local function encode(song,running,noteoff)
    local result = bytes('MThd'); append(result,big(6,4)); append(result,big(song.f,2)); append(result,big(#song.tracks,2)); append(result,big(song.div,2))
    for _, tr in ipairs(song.tracks) do
        local data,last,status = {},0,nil
        for _, e in ipairs(tr) do
            append(data,vlq(e.t-last)); last = e.t
            local s,d = e.s,copy(e.d)
            if noteoff == 'ZERO' and s>>4 == 8 then s = s+16; d[2] = 0 end
            if s < 240 then
                if not running or status ~= s then data[#data+1] = s end
                append(data,d); status = s
            else
                status = nil; data[#data+1] = s
                if s == 255 then data[#data+1] = e.m end
                append(data,vlq(#d)); append(data,d)
            end
        end
        append(result,bytes('MTrk')); append(result,big(#data,4)); append(result,data)
    end
    for i = 1, #result, 16 do
        local a = {}; for j = i, math.min(i+15,#result) do a[#a+1] = string.format('%02X',result[j]) end
        print(string.format('%04X: ',i-1) .. table.concat(a,' '))
    end
    print(#result .. ' bytes')
end
local songs,running,noteoff = {},true,'KEEP'
local known = {}
for _, c in ipairs(words('HEX TEXT DECODE ENCODE TIMING NOTES STATS ROLL TRANSPOSE QUANTIZE VELOCITY TEMPO FILTER MERGE SPLIT COPY LIST RUNNING NOTEOFF')) do known[c] = true end
local function requireThat(valid,message) if not valid then error(message,0) end end
local function run(line)
    local a = words(line); local cmd = table.remove(a,1); local name = a[1]
    requireThat(known[cmd],'unknown command')
    if cmd == 'HEX' or cmd == 'TEXT' then
        local lines = {}; for _ = 1, tonumber(a[2]) do lines[#lines+1] = io.read() end
        local song
        if cmd == 'TEXT' then song = parseText(lines)
        else
            local data = {}; for _, b in ipairs(words(table.concat(lines,' '))) do data[#data+1] = tonumber(b,16) end
            song = parseHex(data)
        end
        songs[name] = song; print('loaded ' .. name .. ' ' .. summary(song)); return
    end
    if cmd ~= 'LIST' and cmd ~= 'RUNNING' and cmd ~= 'NOTEOFF' then requireThat(songs[name],'no song ' .. name) end
    local song = songs[name]
    if cmd == 'LIST' then
        local keys = {}; for k in pairs(songs) do keys[#keys+1] = k end; table.sort(keys)
        if #keys == 0 then print('no songs') end
        for _, k in ipairs(keys) do print(k .. ' ' .. summary(songs[k])) end
    elseif cmd == 'RUNNING' or cmd == 'NOTEOFF' then
        requireThat(cmd == 'RUNNING' and (name == 'ON' or name == 'OFF') or cmd == 'NOTEOFF' and (name == 'ZERO' or name == 'KEEP'),'bad argument')
        if cmd == 'RUNNING' then running = name == 'ON' else noteoff = name end
        print(cmd:lower() .. ' ' .. name:lower())
    elseif cmd == 'COPY' then songs[a[2]] = copy(song); print('copied ' .. name .. ' to ' .. a[2])
    elseif cmd == 'DECODE' then
        print('HEADER ' .. song.f .. ' ' .. #song.tracks .. ' ' .. song.div)
        for i, tr in ipairs(song.tracks) do for _, e in ipairs(tr) do print(eventLine(e,i-1)) end end
    elseif cmd == 'ENCODE' then encode(song,running,noteoff)
    elseif cmd == 'TIMING' then
        requireThat(song.f ~= 2,'format 2 not supported')
        for _, item in ipairs(ordered(song)) do
            local tm,pos = timePosition(song,item.e.t)
            print(item.e.t .. ' ' .. item.tr .. ' ' .. eventType(item.e) .. ' ' .. tm .. ' ' .. pos)
        end
        local tm,pos = timePosition(song,length(song)); print('end ' .. length(song) .. ' ' .. tm .. ' ' .. pos)
    elseif cmd == 'NOTES' or cmd == 'STATS' or cmd == 'ROLL' then
        local from,to,step = tonumber(a[2]),tonumber(a[3]),tonumber(a[4])
        if cmd == 'ROLL' then requireThat(range(a[2],0,10000000) and range(a[3],1,10000000) and range(a[4],1,10000000) and to > from and (to-from+step-1)//step <= 64,'bad argument')
        elseif cmd == 'STATS' then requireThat(song.f ~= 2,'format 2 not supported') end
        local ns,unmatched = pairing(song)
        if cmd == 'NOTES' then
            print('notes ' .. #ns .. ' unmatched ' .. #unmatched)
            for _, n in ipairs(ns) do print(n.start .. ' ' .. n.length .. ' ' .. n.ch .. ' ' .. notes[n.p] .. ' ' .. n.v) end
            for _, u in ipairs(unmatched) do print('unmatched ' .. (u.on and 'on' or 'off') .. ' ' .. u.e.t .. ' ' .. u.tr .. ' ' .. (u.e.s&15)+1 .. ' ' .. notes[u.e.d[1]]) end
        elseif cmd == 'ROLL' then
            local found = false
            for p = 127, 0, -1 do
                local chars, visible = {},false
                for i = 0, (to-from+step-1)//step-1 do
                    local at,c = from+i*step,'.'
                    for _, n in ipairs(ns) do if n.p == p and n.start <= at and at < n.start+n.length then c = '=' end end
                    for _, n in ipairs(ns) do if n.p == p and at <= n.start and n.start < at+step then c = '#' end end
                    chars[#chars+1] = c; if c ~= '.' then visible = true end
                end
                if visible then print(string.format('%-4s ',notes[p]) .. table.concat(chars)); found = true end
            end
            if not found then print('empty') end
        else
            print(summary(song)); print('notes ' .. #ns .. ' unmatched ' .. #unmatched)
            local low,high,changes = 128,-1,{}
            for ch = 1, 16 do
                local count,lo,hi = 0,128,-1
                for _, n in ipairs(ns) do if n.ch == ch then count = count+1; lo,hi = math.min(lo,n.p),math.max(hi,n.p) end end
                if count > 0 then print('channel ' .. ch .. ' notes ' .. count .. ' range ' .. notes[lo] .. ' ' .. notes[hi]); low,high = math.min(low,lo),math.max(high,hi) end
            end
            print(#ns == 0 and 'range none' or 'range ' .. notes[low] .. ' ' .. notes[high])
            local tm = timePosition(song,length(song)); print('length ' .. length(song) .. ' ticks ' .. tm .. ' ms')
            for _, n in ipairs(ns) do if n.length > 0 then changes[n.start] = (changes[n.start] or 0)+1; changes[n.start+n.length] = (changes[n.start+n.length] or 0)-1 end end
            local ticks = {}; for t in pairs(changes) do ticks[#ticks+1] = t end; table.sort(ticks)
            local active,maximum,at = 0,0,0
            for _, t in ipairs(ticks) do active = active+changes[t]; if active > maximum then maximum,at = active,t end end
            print(maximum == 0 and 'polyphony 0' or 'polyphony ' .. maximum .. ' at ' .. at)
        end
    elseif cmd == 'TRANSPOSE' then
        requireThat(range(a[2],-127,127) and (not a[3] or range(a[3],1,16)),'bad argument')
        local amount,ch,kept,dropped = tonumber(a[2]),tonumber(a[3]),0,{}
        for i, tr in ipairs(song.tracks) do
            local new = {}
            for _, e in ipairs(tr) do
                local kind = e.s>>4
                if kind >= 8 and kind <= 10 and (not ch or (e.s&15)+1 == ch) then
                    local p = e.d[1]+amount
                    if p < 0 or p > 127 then dropped[#dropped+1] = 'dropped ' .. e.t .. ' ' .. i-1 .. ' ' .. eventType(e) .. ' ' .. (e.s&15)+1 .. ' ' .. notes[e.d[1]]
                    else e.d[1] = p; kept = kept+1; new[#new+1] = e end
                else new[#new+1] = e end
            end
            song.tracks[i] = new
        end
        print('transposed ' .. kept .. ' dropped ' .. #dropped); for _, s in ipairs(dropped) do print(s) end
    elseif cmd == 'QUANTIZE' then
        requireThat(range(a[2],1,1000000) and range(a[3],0,100),'bad argument')
        local grid,strength = tonumber(a[2]),tonumber(a[3])
        local ns,unmatched = pairing(song); local targets,moved = {},0
        for _, n in ipairs(ns) do targets[#targets+1] = {n.on,n.off} end
        for _, u in ipairs(unmatched) do if u.on then targets[#targets+1] = {u.e} end end
        for _, events in ipairs(targets) do
            local t = events[1].t; local lower = t//grid*grid
            local g = t-lower <= lower+grid-t and lower or lower+grid
            local delta = (2*(g-t)*strength+100)//200
            if delta ~= 0 then moved = moved+1 end
            for _, e in ipairs(events) do e.t = e.t+delta end
        end
        for _, tr in ipairs(song.tracks) do
            local ending = table.remove(tr)
            for i, e in ipairs(tr) do e.order = i end
            table.sort(tr,function(x,y) return x.t < y.t or x.t == y.t and x.order < y.order end)
            for _, e in ipairs(tr) do ending.t = math.max(ending.t,e.t); e.order = nil end
            tr[#tr+1] = ending
        end
        print('quantized ' .. #targets .. ' moved ' .. moved)
    elseif cmd == 'VELOCITY' then
        requireThat(range(a[2],0,1000) and range(a[3],-127,127),'bad argument')
        local count,clamped = 0,0
        for _, item in ipairs(ordered(song)) do
            local e = item.e
            if e.s>>4 == 9 and e.d[2] > 0 then
                count = count+1; local v = (e.d[2]*tonumber(a[2])+50)//100+tonumber(a[3])
                if v < 1 or v > 127 then clamped = clamped+1 end
                e.d[2] = math.max(1,math.min(127,v))
            end
        end
        print('velocity ' .. count .. ' clamped ' .. clamped)
    elseif cmd == 'TEMPO' then
        requireThat(range(a[2],1,1000) and range(a[3],1,1000),'bad argument')
        local num,den,converted,insert = tonumber(a[2]),tonumber(a[3]),{},true
        for _, item in ipairs(ordered(song)) do
            local e = item.e
            if e.s == 255 and e.m == 81 then
                local v = (2*integer(e.d)*den+num)//(2*num)
                requireThat(v >= 1 and v <= 16777215,'tempo out of range')
                converted[#converted+1] = {e,v}; if e.t == 0 then insert = false end
            end
        end
        local v = (1000000*den+num)//(2*num)
        requireThat(not insert or v >= 1 and v <= 16777215,'tempo out of range')
        for _, pair in ipairs(converted) do pair[1].d = big(pair[2],3) end
        print('scaled ' .. #converted)
        if insert then table.insert(song.tracks[1],1,{t=0,s=255,m=81,d=big(v,3)}); print('inserted 0 0 TEMPO ' .. v) end
    elseif cmd == 'FILTER' then
        local allowed = {}; for i = 2, #a do requireThat(range(a[i],1,16),'bad argument'); allowed[tonumber(a[i])] = true end
        local count = 0
        for _, tr in ipairs(song.tracks) do
            for i = #tr, 1, -1 do if tr[i].s < 240 and not allowed[(tr[i].s&15)+1] then table.remove(tr,i); count = count+1 end end
        end
        print('removed ' .. count)
    elseif cmd == 'MERGE' then
        requireThat(song.f == 1,'not format 1')
        local count,ending,tr = #song.tracks,length(song),{}
        for _, item in ipairs(ordered(song)) do if eventType(item.e) ~= 'END_OF_TRACK' then tr[#tr+1] = item.e end end
        tr[#tr+1] = {t=ending,s=255,m=47,d={}}; song.f,song.tracks = 0,{tr}
        print('merged ' .. count .. ' tracks events ' .. #tr)
    elseif cmd == 'SPLIT' then
        requireThat(song.f == 0,'not format 0')
        local tr,groups = song.tracks[1],{[-1]={}}
        for i = 1, #tr-1 do local e = tr[i]; local key = e.s < 240 and (e.s&15) or -1; groups[key] = groups[key] or {}; groups[key][#groups[key]+1] = e end
        local result,count = {},0
        for key = -1, 15 do if groups[key] then local group = groups[key]; group[#group+1] = copy(tr[#tr]); result[#result+1] = group; count = count+#group end end
        song.f,song.tracks = 1,result
        print('split tracks ' .. #result .. ' events ' .. count)
    end
end
local n = tonumber(io.read())
for _ = 1, n do
    local ok,message = pcall(run,io.read())
    if not ok then print('error: ' .. message) end
end
