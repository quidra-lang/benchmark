local PRECS = {GEOHASH={1,2,3,4,5,6,7,8,9}, MAIDENHEAD={2,4,6,8}, PLUSCODE={2,4,6,8,10,11}, GARS={5,6,7}, GEOREF={2,4,8,10,12}, MESH={4,6,8,9,10,11}}
local GH = '0123456789bcdefghjkmnpqrstuvwxyz'
local L24 = 'ABCDEFGHJKLMNPQRSTUVWXYZ'
local PC = '23456789CFGHJMPQRVWX'
local MH = {'ABCDEFGHIJKLMNOPQR','0123456789','abcdefghijklmnopqrstuvwx','0123456789'}
local BANDS = 'CDEFGHJKLMNPQRSTUVWX'
local OS = 'ABCDEFGHJKLMNOPQRSTUVWXYZ'
local COLS = {'STUVWXYZ','ABCDEFGH','JKLMNPQR'}
local ROWS = 'ABCDEFGHJKLMNPQRSTUV'
local function invalid() error('INVALID',0) end
local function pow(base, exponent)
    local value = 1
    for _ = 1, exponent do value = value * base end
    return value
end
local function char_at(set, index) return set:sub(index+1,index+1) end
local function index_char(set, char)
    local index = set:find(char,1,true)
    if #char ~= 1 or not index then invalid() end
    return index-1
end
local function position(values, needle)
    for index, value in ipairs(values) do
        if value == needle then return index end
    end
    return nil
end
local function decimal(text)
    return #text > 0 and text:match('^[0-9]+$') ~= nil
end
local function integer(text, lo, hi)
    local body = text
    if body:sub(1,1) == '-' then body = body:sub(2) end
    if not decimal(body) or #body > 9 then invalid() end
    local value = tonumber(text)
    if value < lo or value > hi then invalid() end
    return value
end
local function coordinate(text, latitude)
    local negative = text:sub(1,1) == '-'
    if negative then text = text:sub(2) end
    local whole, fraction = text:match('^([0-9]+)%.([0-9]+)$')
    if not whole then
        if not decimal(text) then invalid() end
        whole, fraction = text, ''
    end
    if #whole > 3 or #fraction > 6 then invalid() end
    local value = tonumber(whole)*1000000 + tonumber(fraction .. string.rep('0',6-#fraction))
    if negative then value = -value end
    if latitude then
        if value < -90000000 or value > 90000000 then invalid() end
    else
        if value < -180000000 or value >= 180000000 then invalid() end
    end
    return value
end
local function system_name(sys)
    if not PRECS[sys] then invalid() end
    return sys
end
local function precision(sys, text)
    local p = integer(text,1,12)
    if not position(PRECS[sys],p) then invalid() end
    return p
end
local function grid(sys,p)
    if sys == 'GEOHASH' then return pow(2,(5*p+1)//2),pow(2,(5*p)//2) end
    local sizes = {
        MAIDENHEAD={{18,18},{180,180},{4320,4320},{43200,43200}},
        PLUSCODE={{18,9},{360,180},{7200,3600},{144000,72000},{2880000,1440000},{11520000,7200000}},
        GARS={{720,360},{1440,720},{4320,2160}},
        GEOREF={{24,12},{360,180},{21600,10800},{216000,108000},{2160000,1080000}},
        MESH={{360,270},{2880,2160},{28800,21600},{57600,43200},{115200,86400},{230400,172800}}
    }
    return table.unpack(sizes[sys][position(PRECS[sys],p)])
end
local function digits(value, radices)
    local out = {}
    for index = #radices,1,-1 do
        out[index] = value % radices[index]
        value = value // radices[index]
    end
    return out
end
local function encode(sys,p,x,y)
    if sys == 'GEOHASH' then
        local a,b = (5*p+1)//2,(5*p)//2
        local value,out = 0,''
        for index = 0,5*p-1 do
            local bit
            if index % 2 == 0 then
                a = a-1
                bit = (x // pow(2,a)) % 2
            else
                b = b-1
                bit = (y // pow(2,b)) % 2
            end
            value = 2*value+bit
            if index % 5 == 4 then
                out = out .. char_at(GH,value)
                value = 0
            end
        end
        return out
    end
    if sys == 'MAIDENHEAD' then
        local k = p//2
        local radices = {table.unpack({18,10,24,10},1,k)}
        local xs,ys = digits(x,radices),digits(y,radices)
        local out = ''
        for index = 1,k do out = out .. char_at(MH[index],xs[index]) .. char_at(MH[index],ys[index]) end
        return out
    end
    if sys == 'PLUSCODE' then
        local tail = ''
        if p == 11 then
            tail = char_at(PC,4*(y%5)+x%4)
            x,y = x//4,y//5
        end
        local k = math.min(p,10)//2
        local radices = {}
        for index = 1,k do radices[index] = 20 end
        radices[1] = 18
        local xs = digits(x,radices)
        radices[1] = 9
        local ys = digits(y,radices)
        local out = ''
        for index = 1,k do out = out .. char_at(PC,ys[index]) .. char_at(PC,xs[index]) end
        out = out .. tail
        if p < 8 then return out .. string.rep('0',8-p) .. '+' end
        return out:sub(1,8) .. '+' .. out:sub(9)
    end
    if sys == 'GARS' then
        local tail = ''
        if p == 7 then
            tail = tostring(1+x%3+3*(2-y%3))
            x,y = x//3,y//3
        end
        if p >= 6 then
            tail = (1+x%2+2*(1-y%2)) .. tail
            x,y = x//2,y//2
        end
        return string.format('%03d',x+1) .. char_at(L24,y//24) .. char_at(L24,y%24) .. tail
    end
    if sys == 'GEOREF' then
        local tail = ''
        if p >= 8 then
            local m = (p-4)//2
            local scale = 6*pow(10,m-1)
            tail = string.format('%0' .. m .. 'd%0' .. m .. 'd',x%scale,y%scale)
            x,y = x//scale,y//scale
        end
        if p >= 4 then
            tail = char_at(L24,x%15) .. char_at(L24,y%15) .. tail
            x,y = x//15,y//15
        end
        return char_at(L24,x) .. char_at(L24,y) .. tail
    end
    local level = position(PRECS.MESH,p)
    local scale = ({1,8,80,160,320,640})[level]
    local u,v = x-280*scale,y-135*scale
    if u < 0 or u >= 80*scale or v < 0 or v >= 100*scale then return '-' end
    local radices = {table.unpack({80,8,10,2,2,2},1,level)}
    local us = digits(u,radices)
    radices[1] = 100
    local vs = digits(v,radices)
    local out = string.format('%02d%02d',vs[1],us[1])
    for index = 2,level do
        if index <= 3 then out = out .. vs[index] .. us[index] else out = out .. (1+us[index]+2*vs[index]) end
    end
    return out
end
local function decode(sys,code)
    local p,x,y = #code,0,0
    if sys ~= 'PLUSCODE' and not position(PRECS[sys],p) then invalid() end
    if sys == 'GEOHASH' then
        local bit_index = 0
        for index = 1,#code do
            local value = index_char(GH,code:sub(index,index))
            for i = 4,0,-1 do
                local bit = (value // pow(2,i)) % 2
                if bit_index % 2 == 0 then x = 2*x+bit else y = 2*y+bit end
                bit_index = bit_index+1
            end
        end
    elseif sys == 'MAIDENHEAD' then
        for index = 1,p//2 do
            local radix = #MH[index]
            x = x*radix+index_char(MH[index],code:sub(2*index-1,2*index-1))
            y = y*radix+index_char(MH[index],code:sub(2*index,2*index))
        end
    elseif sys == 'PLUSCODE' then
        local _,plus_count = code:gsub('%+','')
        if plus_count ~= 1 or code:find('+',1,true) ~= 9 then invalid() end
        local before,after = code:sub(1,8),code:sub(10)
        local zero = before:find('0',1,true)
        local count = zero and zero-1 or 8
        if not position({2,4,6,8},count) then invalid() end
        if count < 8 and (before:sub(count+1) ~= string.rep('0',8-count) or after ~= '') then invalid() end
        if count == 8 and not position({0,2,3},#after) then invalid() end
        local sequence,values = before:sub(1,count) .. after,{}
        p = #sequence
        for index = 1,p do values[index] = index_char(PC,sequence:sub(index,index)) end
        if values[1] > 8 or values[2] > 17 then invalid() end
        for index = 1,math.min(p,10)//2 do
            y = y*(index == 1 and 9 or 20)+values[2*index-1]
            x = x*(index == 1 and 18 or 20)+values[2*index]
        end
        if p == 11 then
            x = 4*x+values[11]%4
            y = 5*y+values[11]//4
        end
    elseif sys == 'GARS' then
        if not decimal(code:sub(1,3)) then invalid() end
        x = tonumber(code:sub(1,3))-1
        y = 24*index_char(L24:sub(1,15),code:sub(4,4))+index_char(L24,code:sub(5,5))
        if p >= 6 then
            local q = index_char('1234',code:sub(6,6))
            x,y = 2*x+q%2,2*y+1-q//2
        end
        if p == 7 then
            local q = index_char('123456789',code:sub(7,7))
            x,y = 3*x+q%3,3*y+2-q//3
        end
    elseif sys == 'GEOREF' then
        x = index_char(L24,code:sub(1,1))
        y = index_char(L24:sub(1,12),code:sub(2,2))
        if p >= 4 then
            x = 15*x+index_char(L24:sub(1,15),code:sub(3,3))
            y = 15*y+index_char(L24:sub(1,15),code:sub(4,4))
        end
        if p >= 8 then
            local m = (p-4)//2
            local tail = code:sub(5)
            if not decimal(tail) then invalid() end
            local scale = 6*pow(10,m-1)
            local e,n = tonumber(tail:sub(1,m)),tonumber(tail:sub(m+1))
            if e >= scale or n >= scale then invalid() end
            x,y = x*scale+e,y*scale+n
        end
    else
        if not decimal(code) then invalid() end
        local level = position(PRECS.MESH,p)
        local u,v = tonumber(code:sub(3,4)),tonumber(code:sub(1,2))
        if u > 79 then invalid() end
        for index = 2,level do
            if index <= 3 then
                local base = index == 2 and 8 or 10
                local a = tonumber(code:sub(2*index+1,2*index+1))
                local b = tonumber(code:sub(2*index+2,2*index+2))
                if a >= base or b >= base then invalid() end
                v,u = v*base+a,u*base+b
            else
                local q = index_char('1234',code:sub(index+5,index+5))
                u,v = 2*u+q%2,2*v+q//2
            end
        end
        local scale = ({1,8,80,160,320,640})[level]
        x,y = u+280*scale,v+135*scale
    end
    local w,h = grid(sys,p)
    if x < 0 or x >= w or y < 0 or y >= h or encode(sys,p,x,y) ~= code then invalid() end
    return {p,x,y}
end
local function point_cell(sys,p,lat,lon)
    local w,h = grid(sys,p)
    return ((lon+180000000)*w)//360000000,math.min(((lat+90000000)*h)//180000000,h-1)
end
local function ancestor(sys,cell,q)
    local w,h = grid(sys,cell[1])
    local v,u = grid(sys,q)
    return {q,(cell[2]*v)//w,(cell[3]*u)//h}
end
local function cell_code(sys,cell) return encode(sys,table.unpack(cell)) end
local function coord_text(value)
    return (value < 0 and '-' or '') .. string.format('%d.%06d',math.abs(value)//1000000,math.abs(value)%1000000)
end
local function decimal_suffix(e,n,d)
    if d == 0 then return '' end
    return ' ' .. string.format('%05d',e%100000):sub(1,d) .. ' ' .. string.format('%05d',n%100000):sub(1,d)
end
local function square_digits(args,offset)
    if #args == offset then return 0,0,100000 end
    local a,b = args[offset+1],args[offset+2]
    if not decimal(a) or not decimal(b) or #a > 5 or #a ~= #b then invalid() end
    local size = pow(10,5-#a)
    return tonumber(a)*size,tonumber(b)*size,size
end
local function cell_key(cell) return table.concat(cell,':') end
local function compact_cells(sys,cells)
    local set = {}
    for _,cell in ipairs(cells) do set[cell_key(cell)] = cell end
    local changed
    repeat
        changed = false
        for key,cell in pairs(set) do
            local index = position(PRECS[sys],cell[1])
            for i = 1,index-1 do
                if set[cell_key(ancestor(sys,cell,PRECS[sys][i]))] then
                    set[key] = nil
                    changed = true
                    break
                end
            end
        end
        for index = #PRECS[sys],2,-1 do
            local p,q = PRECS[sys][index],PRECS[sys][index-1]
            local w,h = grid(sys,p)
            local v,u = grid(sys,q)
            local needed = (w//v)*(h//u)
            local groups = {}
            for key,cell in pairs(set) do
                if cell[1] == p then
                    local parent = ancestor(sys,cell,q)
                    local pk = cell_key(parent)
                    if not groups[pk] then groups[pk] = {parent=parent,keys={}} end
                    local keys = groups[pk].keys
                    keys[#keys+1] = key
                end
            end
            for key,group in pairs(groups) do
                if #group.keys == needed then
                    for _,child in ipairs(group.keys) do set[child] = nil end
                    set[key] = group.parent
                    changed = true
                end
            end
        end
    until not changed
    cells = {}
    for _,cell in pairs(set) do cells[#cells+1] = cell end
    table.sort(cells,function(a,b)
        if a[1] ~= b[1] then return a[1] < b[1] end
        if a[3] ~= b[3] then return a[3] > b[3] end
        return a[2] < b[2]
    end)
    return cells
end
local function execute(line)
    local t = {}
    for word in line:gmatch('[^ ]+') do t[#t+1] = word end
    local command = table.remove(t,1)
    local counts = {ENCODE={4},DECODE={2},NEIGHBORS={2},PARENT={2},CHILDREN={2},COMMON={3},CONTAINS={4},COVER={6},
        CONVERT={5},STEPS={3},PATH={3},RELATE={4},SIZE={2},SHORTEN={3},RECOVER={3},UTMZONE={2},OSGB={3},UNOSGB={1,3},MGRS={5},UNMGRS={2,4},QUADKEY={3},UNQUADKEY={1}}
    if command == 'COMPACT' then
        if #t < 2 or #t > 101 then invalid() end
    elseif not counts[command] or not position(counts[command],#t) then
        invalid()
    end
    if command == 'UTMZONE' then
        local lat,lon = coordinate(t[1],true),coordinate(t[2],false)
        if lat < -80000000 or lat >= 84000000 then return 'NONE' end
        local band = char_at(BANDS,math.min((lat+80000000)//8000000,19))
        local zone = (lon+180000000)//6000000+1
        if band == 'V' and lon >= 3000000 and lon < 12000000 then zone = 32 end
        if band == 'X' and lon >= 0 and lon < 42000000 then
            if lon < 9000000 then zone = 31
            elseif lon < 21000000 then zone = 33
            elseif lon < 33000000 then zone = 35
            else zone = 37 end
        end
        return zone .. band
    end
    if command == 'OSGB' then
        local e,n,d = integer(t[1],0,699999),integer(t[2],0,1299999),integer(t[3],0,5)
        local letters = char_at(OS,5*(3-n//500000)+2+e//500000) .. char_at(OS,5*(4-(n//100000)%5)+(e//100000)%5)
        return letters .. decimal_suffix(e,n,d)
    end
    if command == 'UNOSGB' then
        if #t[1] ~= 2 then invalid() end
        local a,b = index_char(OS,t[1]:sub(1,1)),index_char(OS,t[1]:sub(2,2))
        local e = 500000*(a%5-2)+100000*(b%5)
        local n = 500000*(3-a//5)+100000*(4-b//5)
        if e < 0 or e >= 700000 or n < 0 or n >= 1300000 then invalid() end
        local de,dn,size = square_digits(t,1)
        return 'sw=' .. (e+de) .. ',' .. (n+dn) .. ' size=' .. size
    end
    if command == 'MGRS' then
        local zone = integer(t[1],1,60)
        if #t[2] ~= 1 then invalid() end
        index_char(BANDS,t[2])
        local e,n,d = integer(t[3],100000,899999),integer(t[4],0,9999999),integer(t[5],0,5)
        local letters = char_at(COLS[zone%3+1],e//100000-1) .. char_at(ROWS,(n//100000+(zone%2 == 0 and 5 or 0))%20)
        return zone .. t[2] .. ' ' .. letters .. decimal_suffix(e,n,d)
    end
    if command == 'UNMGRS' then
        local zone_text,band = t[1]:match('^([1-9][0-9]?)([CDEFGHJKLMNPQRSTUVWX])$')
        if not zone_text then invalid() end
        local zone = tonumber(zone_text)
        if zone > 60 or #t[2] ~= 2 then invalid() end
        local c = index_char(COLS[zone%3+1],t[2]:sub(1,1))
        local r = index_char(ROWS,t[2]:sub(2,2))
        local e,n = 100000*(c+1),100000*((r-(zone%2 == 0 and 5 or 0))%20)
        local de,dn,size = square_digits(t,2)
        return t[1] .. ' sw=' .. (e+de) .. ',' .. (n+dn) .. ' size=' .. size
    end
    if command == 'QUADKEY' then
        local z = integer(t[3],1,23)
        local x,y = integer(t[1],0,pow(2,z)-1),integer(t[2],0,pow(2,z)-1)
        local out = ''
        for i = z-1,0,-1 do out = out .. ((x//pow(2,i))%2+2*((y//pow(2,i))%2)) end
        return out
    end
    if command == 'UNQUADKEY' then
        if #t[1] < 1 or #t[1] > 23 or not t[1]:match('^[0-3]+$') then invalid() end
        local x,y = 0,0
        for index = 1,#t[1] do
            local v = tonumber(t[1]:sub(index,index))
            x,y = 2*x+v%2,2*y+v//2
        end
        return 'x=' .. x .. ' y=' .. y .. ' z=' .. #t[1]
    end
    if command == 'SHORTEN' or command == 'RECOVER' then
        local lat,lon = coordinate(t[2],true),coordinate(t[3],false)
        if command == 'SHORTEN' then
            local cell = decode('PLUSCODE',t[1])
            local p,x,y = table.unpack(cell)
            if p < 8 then invalid() end
            local w,h = grid('PLUSCODE',p)
            local dy = math.abs((-90000000-lat)*2*h+180000000*(2*y+1))
            local dx = math.abs((-180000000-lon)*2*w+360000000*(2*x+1))
            if dy < 15000*2*h and dx < 15000*2*w then return t[1]:sub(7) end
            if dy < 300000*2*h and dx < 300000*2*w then return t[1]:sub(5) end
            return t[1]
        end
        local _,plus_count = t[1]:gsub('%+','')
        local plus = t[1]:find('+',1,true)
        if plus_count ~= 1 then invalid() end
        local before,after = t[1]:sub(1,plus-1),t[1]:sub(plus+1)
        if not position({2,4},#before) or not position({0,2,3},#after) then invalid() end
        for index = 1,#before do index_char(PC,before:sub(index,index)) end
        for index = 1,#after do index_char(PC,after:sub(index,index)) end
        local r = 8-#before
        local px,py = point_cell('PLUSCODE',10,lat,lon)
        local full = encode('PLUSCODE',10,px,py):sub(1,r) .. t[1]
        local p,x,y = table.unpack(decode('PLUSCODE',full))
        local w,h = grid('PLUSCODE',p)
        local d = r == 4 and 1000000 or 50000
        local my,mx = (d*h)//180000000,(d*w)//360000000
        local cy,cx = 180000000*(2*y+1),360000000*(2*x+1)
        if (lat+d//2+90000000)*2*h < cy and cy >= d*2*h then
            y = y-my
        elseif (lat-d//2+90000000)*2*h > cy and cy <= (180000000-d)*2*h then
            y = y+my
        end
        if (lon+d//2+180000000)*2*w < cx then
            x = (x-mx)%w
        elseif (lon-d//2+180000000)*2*w > cx then
            x = (x+mx)%w
        end
        return encode('PLUSCODE',p,x,y)
    end
    local sys = system_name(t[1])
    if command == 'SIZE' or command == 'ENCODE' or command == 'COVER' then
        local p = precision(sys,t[command == 'ENCODE' and 4 or 2])
        local w,h = grid(sys,p)
        if command == 'SIZE' then
            local cells = w*h
            if sys == 'MESH' then
                local scale = ({1,8,80,160,320,640})[position(PRECS[sys],p)]
                cells = 8000*scale*scale
            end
            return 'w=' .. coord_text(360000000//w) .. ' h=' .. coord_text(180000000//h) .. ' cells=' .. cells
        end
        if command == 'ENCODE' then
            local x,y = point_cell(sys,p,coordinate(t[2],true),coordinate(t[3],false))
            local code = encode(sys,p,x,y)
            return code == '-' and 'OUT OF AREA' or code
        end
        local lat1,lon1 = coordinate(t[3],true),coordinate(t[4],false)
        local lat2,lon2 = coordinate(t[5],true),coordinate(t[6],false)
        if lat1 > lat2 then invalid() end
        local x1,y1 = point_cell(sys,p,lat1,lon1)
        local x2,y2 = point_cell(sys,p,lat2,lon2)
        local columns_count
        if lon1 <= lon2 then columns_count = x2-x1+1 else columns_count = math.min(w,x2-x1+1+w) end
        if (y2-y1+1)*columns_count > 100 then return 'TOO MANY' end
        local out = {}
        for y = y2,y1,-1 do
            for i = 0,columns_count-1 do out[#out+1] = encode(sys,p,(x1+i)%w,y) end
        end
        return table.concat(out,' ')
    end
    if command == 'COMPACT' then
        local cells,out = {},{}
        for index = 2,#t do cells[#cells+1] = decode(sys,t[index]) end
        for _,cell in ipairs(compact_cells(sys,cells)) do out[#out+1] = cell_code(sys,cell) end
        return table.concat(out,' ')
    end
    local cell = decode(sys,t[2])
    local p,x,y = table.unpack(cell)
    local w,h = grid(sys,p)
    local index = position(PRECS[sys],p)
    if command == 'DECODE' then
        local south,west = -90000000+(180000000*y)//h,-180000000+(360000000*x)//w
        local north,east = -90000000+(180000000*(y+1))//h,-180000000+(360000000*(x+1))//w
        local cy,cx = -90000000+(180000000*(2*y+1))//(2*h),-180000000+(360000000*(2*x+1))//(2*w)
        return 'sw=' .. coord_text(south) .. ',' .. coord_text(west) .. ' ne=' .. coord_text(north) .. ',' .. coord_text(east) .. ' c=' .. coord_text(cy) .. ',' .. coord_text(cx)
    end
    if command == 'CONTAINS' then
        local a,b = point_cell(sys,p,coordinate(t[3],true),coordinate(t[4],false))
        return a == x and b == y and 'YES' or 'NO'
    end
    if command == 'NEIGHBORS' then
        local out = {}
        for _,delta in ipairs({{0,1},{1,1},{1,0},{1,-1},{0,-1},{-1,-1},{-1,0},{-1,1}}) do
            local yy = y+delta[2]
            if yy < 0 or yy >= h then out[#out+1] = '-' else out[#out+1] = encode(sys,p,(x+delta[1])%w,yy) end
        end
        return table.concat(out,' ')
    end
    if command == 'PARENT' then
        if index == 1 then return 'NONE' end
        return cell_code(sys,ancestor(sys,cell,PRECS[sys][index-1]))
    end
    if command == 'CHILDREN' then
        if index == #PRECS[sys] then return 'NONE' end
        local q = PRECS[sys][index+1]
        local v,u = grid(sys,q)
        local rx,ry = v//w,u//h
        if rx*ry > 100 then return 'TOO MANY' end
        local out = {}
        for j = ry-1,0,-1 do
            for i = 0,rx-1 do out[#out+1] = encode(sys,q,rx*x+i,ry*y+j) end
        end
        return table.concat(out,' ')
    end
    if command == 'CONVERT' then
        if t[3] ~= 'TO' then invalid() end
        local sys2 = system_name(t[4])
        local q = precision(sys2,t[5])
        local v,u = grid(sys2,q)
        local code = encode(sys2,q,((2*x+1)*v)//(2*w),((2*y+1)*u)//(2*h))
        return code == '-' and 'OUT OF AREA' or code
    end
    if command == 'RELATE' then
        local sys2 = system_name(t[3])
        local q,a,b = table.unpack(decode(sys2,t[4]))
        local v,u = grid(sys2,q)
        local l1,r1,l2,r2 = x*v,(x+1)*v,a*w,(a+1)*w
        local s1,n1,s2,n2 = y*u,(y+1)*u,b*h,(b+1)*h
        if l1 == l2 and r1 == r2 and s1 == s2 and n1 == n2 then return 'EQUAL' end
        if l1 >= l2 and r1 <= r2 and s1 >= s2 and n1 <= n2 then return 'INSIDE' end
        if l2 >= l1 and r2 <= r1 and s2 >= s1 and n2 <= n1 then return 'CONTAINS' end
        if math.max(l1,l2) < math.min(r1,r2) and math.max(s1,s2) < math.min(n1,n2) then return 'OVERLAP' end
        local latitude_touch = math.max(s1,s2) <= math.min(n1,n2)
        local date_line = (x == 0 and a+1 == v) or (a == 0 and x+1 == w)
        if latitude_touch and (math.max(l1,l2) <= math.min(r1,r2) or date_line) then return 'TOUCH' end
        return 'DISJOINT'
    end
    local second = decode(sys,t[3])
    if command == 'COMMON' then
        local limit = math.min(index,position(PRECS[sys],second[1]))
        for i = limit,1,-1 do
            local a = ancestor(sys,cell,PRECS[sys][i])
            local b = ancestor(sys,second,PRECS[sys][i])
            if a[2] == b[2] and a[3] == b[3] then return cell_code(sys,a) end
        end
        return 'NONE'
    end
    if p ~= second[1] then return 'MISMATCH' end
    local dx = (second[2]-x)%w
    if 2*dx > w then dx = dx-w end
    local dy = second[3]-y
    if command == 'STEPS' then return 'dx=' .. dx .. ' dy=' .. dy end
    local n = math.max(math.abs(dx),math.abs(dy))
    if n+1 > 100 then return 'TOO MANY' end
    if n == 0 then return cell_code(sys,cell) end
    local out = {}
    for i = 0,n do out[#out+1] = encode(sys,p,(x+(2*i*dx+n)//(2*n))%w,y+(2*i*dy+n)//(2*n)) end
    return table.concat(out,' ')
end
local count = tonumber(io.read('*l'))
for _ = 1,count do
    local ok,result = pcall(execute,io.read('*l'))
    io.write(ok and result or 'INVALID','\n')
end
