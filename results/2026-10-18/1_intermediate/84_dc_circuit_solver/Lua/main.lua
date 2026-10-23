local function gcd(a, b) a = math.abs(a); while b ~= 0 do a, b = b, a % b end; return a end
local Rational = {}
Rational.__index = Rational
local function fraction(n, d)
    if d < 0 then n, d = -n, -d end
    local common = gcd(n, d)
    return setmetatable({n=n // common, d=d // common}, Rational)
end
local zero, one = fraction(0, 1), fraction(1, 1)
function Rational:add(b) return fraction(self.n * b.d + b.n * self.d, self.d * b.d) end
function Rational:sub(b) return fraction(self.n * b.d - b.n * self.d, self.d * b.d) end
function Rational:mul(b) return fraction(self.n * b.n, self.d * b.d) end
function Rational:div(b) return fraction(self.n * b.d, self.d * b.n) end
function Rational:neg() return fraction(-self.n, self.d) end
function Rational:compare(b) local x, y = self.n * b.d, b.n * self.d; return x < y and -1 or x > y and 1 or 0 end
function Rational:text() return self.d == 1 and tostring(self.n) or self.n .. "/" .. self.d end
function Rational:value()
    local scaled = math.abs(self.n) * 1000000 // self.d
    return string.format("%s (%s%d.%06d)", self:text(), self.n < 0 and "-" or "", scaled // 1000000, scaled % 1000000)
end
local function parse_number(text)
    local multiplier = one
    if text:sub(-3) == "meg" then multiplier, text = fraction(1000000, 1), text:sub(1, -4)
    elseif text:sub(-1) == "k" then multiplier, text = fraction(1000, 1), text:sub(1, -2)
    elseif text:sub(-1) == "m" then multiplier, text = fraction(1, 1000), text:sub(1, -2)
    elseif text:sub(-1) == "u" then multiplier, text = fraction(1, 1000000), text:sub(1, -2) end
    local negative = text:sub(1, 1) == "-"
    if negative then text = text:sub(2) end
    local result
    if text:match("^%d+$") then result = fraction(tonumber(text), 1)
    else
        local a, b = text:match("^(%d+)%.(%d+)$")
        if a then
            local denominator = 1
            for _ = 1, #b do denominator = denominator * 10 end
            result = fraction(tonumber(a) * denominator + tonumber(b), denominator)
        else
            a, b = text:match("^(%d+)/(%d+)$")
            if not a or tonumber(b) == 0 then return nil end
            result = fraction(tonumber(a), tonumber(b))
        end
    end
    result = result:mul(multiplier)
    return negative and result:neg() or result
end
local function fail(format, ...) error({reason=string.format(format, ...)}, 0) end
local function number(text) local result = parse_number(text); if not result then fail("invalid value %s", text) end; return result end
local function valid_node(name) return name == "0" or #name >= 1 and #name <= 8 and name:match("^[a-z][a-z0-9]*$") ~= nil end
local function keys(set) local list = {}; for name in pairs(set) do list[#list + 1] = name end; table.sort(list); return list end
local function words(text) local list = {}; for word in text:gmatch("%S+") do list[#list + 1] = word end; return list end
local function voltage_source(e) return e.kind == "V" or e.kind == "E" or e.kind == "H" end
local function independent(e) return e.kind == "V" or e.kind == "I" end
local function element_terminals(e)
    if e.kind == "E" or e.kind == "G" then return {e.n1,e.n2,e.c1,e.c2} end
    return {e.n1,e.n2}
end
local function zero_vector(n) local result = {}; for i = 1, n do result[i] = zero end; return result end
local function zero_matrix(n) local result = {}; for i = 1, n do result[i] = zero_vector(n) end; return result end
local Union = {}
Union.__index = Union
function Union.new(nodes) local self = setmetatable({parent={["0"]="0"}}, Union); for _, node in ipairs(nodes) do self.parent[node] = node end; return self end
function Union:root(name) if self.parent[name] ~= name then self.parent[name] = self:root(self.parent[name]) end; return self.parent[name] end
function Union:join(a, b) a, b = self:root(a), self:root(b); if a > b then a, b = b, a end; self.parent[b] = a end
local Circuit = {}
Circuit.__index = Circuit
function Circuit:nodes(include_ground)
    local set = {}
    for _, e in ipairs(self.elements) do for _, node in ipairs(element_terminals(e)) do if include_ground or node ~= "0" then set[node] = true end end end
    return keys(set)
end
function Circuit:node(name) if name == "0" then return end; for _, node in ipairs(self:nodes(false)) do if node == name then return end end; fail("unknown node %s", name) end
function Circuit:index(name) for i, e in ipairs(self.elements) do if e.name == name then return i end end; fail("unknown element %s", name) end
function Circuit:add(fields)
    local name, kind, expected = fields[1], fields[1]:sub(1, 1), 4
    if kind == "E" or kind == "G" then expected = 6 elseif kind == "F" or kind == "H" then expected = 5 end
    if not ("RVIEGFH"):find(kind, 1, true) then fail("unknown element type %s", name) end
    if #fields ~= expected then fail("wrong field count for %s", name) end
    for _, e in ipairs(self.elements) do if e.name == name then fail("duplicate element %s", name) end end
    local count = (kind == "E" or kind == "G") and 4 or 2
    for i = 2, count + 1 do if not valid_node(fields[i]) then fail("invalid node %s", fields[i]) end end
    local e = {name=name, kind=kind, n1=fields[2], n2=fields[3]}
    if kind == "E" or kind == "G" then e.c1, e.c2 = fields[4], fields[5] end
    if kind == "F" or kind == "H" then
        e.reference = fields[4]
        local found = false
        for _, source in ipairs(self.elements) do if source.name == e.reference and source.kind == "V" then found = true end end
        if not found then fail("unknown voltage source %s", e.reference) end
    end
    e.value = number(fields[#fields])
    if kind == "R" and e.value.n <= 0 then fail("nonpositive resistance %s", name) end
    self.elements[#self.elements + 1] = e
end
function Circuit:floating()
    local groups, result = Union.new(self:nodes(false)), {}
    for _, e in ipairs(self.elements) do if e.kind == "R" or voltage_source(e) then groups:join(e.n1, e.n2) end end
    for _, node in ipairs(self:nodes(false)) do if groups:root(node) ~= groups:root("0") then result[#result + 1] = node end end
    return result
end
function Circuit:source_loops()
    local groups, result = Union.new(self:nodes(false)), {}
    for _, e in ipairs(self.elements) do if voltage_source(e) then if groups:root(e.n1) == groups:root(e.n2) then result[#result + 1] = e.name end; groups:join(e.n1, e.n2) end end
    return result
end
function Circuit:structure()
    if #self:nodes(false) == 0 then fail("no nodes") end
    local floating = self:floating(); if #floating > 0 then fail("floating node %s", floating[1]) end
    local loops = self:source_loops(); if #loops > 0 then fail("voltage source loop at %s", loops[1]) end
end
local Equations = {}
Equations.__index = Equations
function Equations:add(row, column, value)
    if row ~= "0" and column ~= "0" then local i, j = self.indices[row], self.indices[column]; self.a[i][j] = self.a[i][j]:add(value) end
end
function Equations:rhs(vector, row, value) if row ~= "0" then local i = self.indices[row]; vector[i] = vector[i]:add(value) end end
function Circuit:build()
    local m = setmetatable({nodes=self:nodes(false), names={}, labels={}, sources={}, indices={}}, Equations)
    for _, node in ipairs(m.nodes) do m.names[#m.names + 1] = "V(" .. node .. ")"; m.indices[node] = #m.names; m.labels[#m.labels + 1] = node end
    for _, e in ipairs(self.elements) do if voltage_source(e) then m.names[#m.names + 1] = "I(" .. e.name .. ")"; m.indices[e.name] = #m.names; m.sources[#m.sources + 1] = e.name; m.labels[#m.labels + 1] = e.name end end
    m.a, m.b = zero_matrix(#m.names), zero_vector(#m.names)
    for _, e in ipairs(self.elements) do
        local w = e.value
        if e.kind == "R" then local g = one:div(w); m:add(e.n1,e.n1,g); m:add(e.n2,e.n2,g); m:add(e.n1,e.n2,g:neg()); m:add(e.n2,e.n1,g:neg())
        elseif e.kind == "I" then m:rhs(m.b,e.n1,w:neg()); m:rhs(m.b,e.n2,w)
        elseif e.kind == "G" then m:add(e.n1,e.c1,w); m:add(e.n2,e.c2,w); m:add(e.n1,e.c2,w:neg()); m:add(e.n2,e.c1,w:neg())
        elseif e.kind == "F" then m:add(e.n1,e.reference,w); m:add(e.n2,e.reference,w:neg())
        else
            m:add(e.n1,e.name,one); m:add(e.name,e.n1,one); m:add(e.n2,e.name,one:neg()); m:add(e.name,e.n2,one:neg())
            if e.kind == "V" then m:rhs(m.b,e.name,w) elseif e.kind == "E" then m:add(e.name,e.c1,w:neg()); m:add(e.name,e.c2,w) else m:add(e.name,e.reference,w:neg()) end
        end
    end
    return m
end
local function solve(a, b)
    local n, rows = #b, {}
    for i = 1, n do rows[i] = {}; for j = 1, n do rows[i][j] = a[i][j] end; rows[i][n + 1] = b[i] end
    for k = 1, n do
        local pivot = k
        while pivot <= n and rows[pivot][k].n == 0 do pivot = pivot + 1 end
        if pivot > n then return nil end
        rows[k], rows[pivot] = rows[pivot], rows[k]
        local divisor = rows[k][k]
        for j = 1, n + 1 do rows[k][j] = rows[k][j]:div(divisor) end
        for i = 1, n do
            if i ~= k then
                local factor = rows[i][k]
                if factor.n ~= 0 then for j = 1, n + 1 do rows[i][j] = rows[i][j]:sub(factor:mul(rows[k][j])) end end
            end
        end
    end
    local result = {}; for i = 1, n do result[i] = rows[i][n + 1] end; return result
end
function Equations:potential(solution, node) return node == "0" and zero or solution[self.indices[node]] end
function Equations:voltage(solution, a, b) return self:potential(solution, a):sub(self:potential(solution, b)) end
function Equations:current(solution, e)
    if e.kind == "R" then return self:voltage(solution,e.n1,e.n2):div(e.value)
    elseif e.kind == "I" then return e.value
    elseif e.kind == "G" then return e.value:mul(self:voltage(solution,e.c1,e.c2))
    elseif e.kind == "F" then return e.value:mul(solution[self.indices[e.reference]])
    else return solution[self.indices[e.name]] end
end
function Equations:injection(a, b) local rhs = zero_vector(#self.b); self:rhs(rhs,a,one); self:rhs(rhs,b,one:neg()); return solve(self.a,rhs) end
function Equations:alone(e, value)
    local rhs = zero_vector(#self.b)
    if e.kind == "V" then self:rhs(rhs,e.name,value) else self:rhs(rhs,e.n1,value:neg()); self:rhs(rhs,e.n2,value) end
    return solve(self.a,rhs)
end
local function reachable(start, edges)
    local seen, changed = {[start]=true}, true
    while changed do changed = false; for _, e in ipairs(edges) do if seen[e.a] and not seen[e.b] then seen[e.b], changed = true, true end; if seen[e.b] and not seen[e.a] then seen[e.a], changed = true, true end end end
    return seen
end
function Circuit:resistance(a, b)
    local groups = Union.new(self:nodes(false))
    for _, e in ipairs(self.elements) do if e.kind == "V" then groups:join(e.n1,e.n2) end end
    a, b = groups:root(a), groups:root(b)
    if a == b then return "Req = " .. zero:value() end
    local edges = {}
    for _, e in ipairs(self.elements) do if e.kind == "R" then local x, y = groups:root(e.n1), groups:root(e.n2); if x ~= y then edges[#edges + 1] = {a=x,b=y,value=e.value} end end end
    local component = reachable(a,edges)
    if not component[b] then return "Req = INFINITE" end
    local indices, names = {}, {}
    for _, node in ipairs(keys(component)) do if node ~= b then names[#names + 1] = node; indices[node] = #names end end
    local matrix, rhs = zero_matrix(#names), zero_vector(#names)
    local function add(x, y, value) if x ~= b and y ~= b then local i,j=indices[x],indices[y]; matrix[i][j]=matrix[i][j]:add(value) end end
    for _, e in ipairs(edges) do if component[e.a] then local g=one:div(e.value); add(e.a,e.a,g); add(e.b,e.b,g); add(e.a,e.b,g:neg()); add(e.b,e.a,g:neg()) end end
    rhs[indices[a]] = one
    return "Req = " .. solve(matrix,rhs)[indices[a]]:value()
end
function Circuit:reduce(a, b)
    if a == b then return {"Req = " .. zero:value()} end
    local list = {}
    for _, e in ipairs(self.elements) do if e.kind == "R" then list[#list + 1] = {name=e.name,a=e.n1,b=e.n2,value=e.value} end end
    local component = reachable(a,list)
    if not component[b] then return {"Req = INFINITE"} end
    local kept = {}; for _, e in ipairs(list) do if component[e.a] then kept[#kept + 1] = e end end; list = kept
    local lines, serial = {}, 0
    while true do
        local self_loop
        for i,e in ipairs(list) do if e.a==e.b then self_loop=i; break end end
        if self_loop then lines[#lines+1]="remove "..list[self_loop].name; table.remove(list,self_loop)
        else
            local degrees = {}; for _,e in ipairs(list) do degrees[e.a]=(degrees[e.a] or 0)+1; degrees[e.b]=(degrees[e.b] or 0)+1 end
            local internal = {}; for _,node in ipairs(keys(degrees)) do if node~=a and node~=b then internal[#internal+1]=node end end
            local dangling; for _,node in ipairs(internal) do if degrees[node]==1 then dangling=node; break end end
            if dangling then
                for i,e in ipairs(list) do if e.a==dangling or e.b==dangling then lines[#lines+1]="remove "..e.name; table.remove(list,i); break end end
            else
                local first,second
                for i=1,#list do
                    for j=i+1,#list do local x,y=list[i],list[j]; if x.a==y.a and x.b==y.b or x.a==y.b and x.b==y.a then first,second=i,j; break end end
                    if first then break end
                end
                if first then
                    local x,y=list[first],list[second]; serial=serial+1; local name="#"..serial; local value=x.value:mul(y.value):div(x.value:add(y.value))
                    lines[#lines+1]=string.format("%s = %s || %s = %s",name,x.name,y.name,value:value())
                    table.remove(list,second); table.remove(list,first); list[#list+1]={name=name,a=x.a,b=x.b,value=value}
                else
                    local middle; for _,node in ipairs(internal) do if degrees[node]==2 then middle=node; break end end
                    if not middle then break end
                    local indices={}; for i,e in ipairs(list) do if e.a==middle or e.b==middle then indices[#indices+1]=i end end
                    first,second=indices[1],indices[2]; local x,y=list[first],list[second]; local u=x.a==middle and x.b or x.a; local v=y.a==middle and y.b or y.a
                    serial=serial+1; local name="#"..serial; local value=x.value:add(y.value)
                    lines[#lines+1]=string.format("%s = %s + %s = %s",name,x.name,y.name,value:value())
                    table.remove(list,second); table.remove(list,first); list[#list+1]={name=name,a=u,b=v,value=value}
                end
            end
        end
    end
    lines[#lines+1]=#list==1 and "Req = "..list[1].value:value() or string.format("not series-parallel: %d resistors remain",#list)
    return lines
end
local argument_counts = {[".OP"]=0,[".CURRENT"]=1,[".VOLTAGE"]=2,[".POWER"]=0,[".KCL"]=1,[".THEVENIN"]=2,[".NORTON"]=2,[".MAXPOWER"]=2,[".TF"]=2,[".SENS"]=1,[".ZPARAM"]=4,[".SUPERPOSITION"]=1,[".SWEEP"]=5,[".MATRIX"]=0,[".REQ"]=2,[".REDUCE"]=2,[".CHECK"]=0,[".ALTER"]=2,[".DELETE"]=1,[".CLEAR"]=0,[".NODES"]=0,[".PRINT"]=0}
function Circuit:command(fields)
    local name = table.remove(fields,1)
    local args, lines = fields, {}
    local function emit(format, ...) lines[#lines+1]=string.format(format,...) end
    if argument_counts[name]==nil then fail("unknown command %s",name) end
    if #args~=argument_counts[name] then fail("wrong argument count for %s",name) end
    if name==".ALTER" then
        local index=self:index(args[1]); local value=number(args[2]); local e=self.elements[index]
        if e.kind=="R" and value.n<=0 then fail("nonpositive resistance %s",e.name) end
        emit("altered %s: %s -> %s",e.name,e.value:text(),value:text()); e.value=value; return lines
    elseif name==".DELETE" then
        local index=self:index(args[1])
        for _,e in ipairs(self.elements) do if (e.kind=="F" or e.kind=="H") and e.reference==args[1] then fail("%s is referenced by %s",args[1],e.name) end end
        table.remove(self.elements,index); emit("deleted %s",args[1]); return lines
    elseif name==".CLEAR" then emit("cleared %d elements",#self.elements); self.elements={}; return lines
    elseif name==".PRINT" then
        if #self.elements==0 then emit("empty netlist") end
        for _,e in ipairs(self.elements) do local extra=""; if e.kind=="E" or e.kind=="G" then extra=e.c1.." "..e.c2.." " elseif e.kind=="F" or e.kind=="H" then extra=e.reference.." " end; emit("%s %s %s %s%s",e.name,e.n1,e.n2,extra,e.value:text()) end; return lines
    elseif name==".NODES" then
        local nodes=self:nodes(true); if #nodes==0 then emit("no nodes") end
        for _,node in ipairs(nodes) do local names={}; for _,e in ipairs(self.elements) do for _,terminal in ipairs(element_terminals(e)) do if terminal==node then names[#names+1]=e.name; break end end end; emit("%s: %s",node,table.concat(names," ")) end; return lines
    elseif name==".CHECK" then
        local nodes=self:nodes(false); if #nodes==0 then return {"no nodes"} end
        local degrees={}; for _,e in ipairs(self.elements) do degrees[e.n1]=(degrees[e.n1] or 0)+1; degrees[e.n2]=(degrees[e.n2] or 0)+1 end
        for _,node in ipairs(nodes) do if (degrees[node] or 0)<2 then emit("dangling node %s",node) end end
        for _,node in ipairs(self:floating()) do emit("floating node %s",node) end
        for _,source in ipairs(self:source_loops()) do emit("voltage source loop at %s",source) end
        if #lines==0 then local m=self:build(); emit(solve(m.a,m.b) and "ok" or "singular matrix") end; return lines
    elseif name==".REQ" or name==".REDUCE" then
        self:node(args[1]); self:node(args[2]); return name==".REQ" and {self:resistance(args[1],args[2])} or self:reduce(args[1],args[2])
    elseif name==".SWEEP" then
        local index=self:index(args[1]); local from=number(args[2]); local to=number(args[3]); local step=number(args[4]); self:node(args[5])
        if step.n<=0 then fail("invalid sweep step") end; if from:compare(to)>0 then fail("invalid sweep range") end
        local ratio=to:sub(from):div(step); local points=ratio.n//ratio.d+1
        if points>20 then fail("too many sweep points") end
        if self.elements[index].kind=="R" and from.n<=0 then fail("nonpositive resistance %s",args[1]) end
        self:structure()
        local temporary=setmetatable({elements={}},Circuit)
        for i,e in ipairs(self.elements) do local item={}; for key,value in pairs(e) do item[key]=value end; temporary.elements[i]=item end
        for k=0,points-1 do
            local value=from:add(step:mul(fraction(k,1))); temporary.elements[index].value=value
            local m=temporary:build(); local solution=solve(m.a,m.b)
            if solution then emit("%s = %s: V(%s) = %s",args[1],value:text(),args[5],m:potential(solution,args[5]):value()) else emit("%s = %s: singular matrix",args[1],value:text()) end
        end
        return lines
    end
    if name==".CURRENT" then self:index(args[1])
    elseif name==".TF" then self:node(args[1]); local index=self:index(args[2]); if not independent(self.elements[index]) then fail("not an independent source %s",args[2]) end
    else for _,node in ipairs(args) do self:node(node) end end
    self:structure()
    local m=self:build()
    if name==".MATRIX" then
        emit("unknowns: %s",table.concat(m.names," "))
        for i,row in ipairs(m.a) do local values={}; for _,value in ipairs(row) do values[#values+1]=value:text() end; emit("%s: %s | %s",m.labels[i],table.concat(values," "),m.b[i]:text()) end; return lines
    end
    local solution=solve(m.a,m.b); if not solution then fail("singular matrix") end
    if name==".OP" then
        for _,node in ipairs(m.nodes) do emit("V(%s) = %s",node,m:potential(solution,node):value()) end
        for _,source in ipairs(m.sources) do emit("I(%s) = %s",source,solution[m.indices[source]]:value()) end
    elseif name==".CURRENT" then local e=self.elements[self:index(args[1])]; emit("I(%s) = %s",e.name,m:current(solution,e):value())
    elseif name==".VOLTAGE" then emit("V(%s,%s) = %s",args[1],args[2],m:voltage(solution,args[1],args[2]):value())
    elseif name==".POWER" then
        local absorbed,delivered,total=zero,zero,zero
        for _,e in ipairs(self.elements) do local power=m:voltage(solution,e.n1,e.n2):mul(m:current(solution,e)); emit("P(%s) = %s",e.name,power:value()); if power.n>0 then absorbed=absorbed:add(power) elseif power.n<0 then delivered=delivered:add(power:neg()) end; total=total:add(power) end
        emit("absorbed = %s",absorbed:value()); emit("delivered = %s",delivered:value()); emit("total = %s",total:value())
    elseif name==".KCL" then
        local sum=zero
        for _,e in ipairs(self.elements) do if e.n1==args[1] or e.n2==args[1] then local current=zero; if e.n1~=e.n2 then current=m:current(solution,e); if e.n2==args[1] then current=current:neg() end end; emit("I(%s) leaving %s = %s",e.name,args[1],current:value()); sum=sum:add(current) end end
        emit("sum = %s",sum:value())
    elseif name==".THEVENIN" or name==".NORTON" or name==".MAXPOWER" then
        local vth=m:voltage(solution,args[1],args[2]); local rth=m:voltage(m:injection(args[1],args[2]),args[1],args[2])
        if name==".NORTON" then if rth.n==0 then fail("zero thevenin resistance") end; emit("In = %s",vth:div(rth):value()); emit("Rn = %s",rth:value())
        elseif name==".MAXPOWER" then if rth.n<=0 then fail("nonpositive thevenin resistance") end; emit("RL = %s",rth:value()); emit("Pmax = %s",vth:mul(vth):div(fraction(4,1):mul(rth)):value())
        else emit("Vth = %s",vth:value()); emit("Rth = %s",rth:value()) end
    elseif name==".TF" then
        local source=self.elements[self:index(args[2])]; local unit=m:alone(source,one); emit("gain = %s",m:potential(unit,args[1]):value())
        if source.kind=="V" then local current=unit[m.indices[source.name]]; if current.n==0 then emit("input resistance = INFINITE") else emit("input resistance = %s",one:neg():div(current):value()) end
        else emit("input resistance = %s",m:voltage(unit,source.n2,source.n1):value()) end
        emit("output resistance = %s",m:potential(m:injection(args[1],"0"),args[1]):value())
    elseif name==".SENS" then
        for _,e in ipairs(self.elements) do
            local rhs=zero_vector(#m.b)
            if e.kind=="R" then local value=m:current(solution,e):div(e.value); m:rhs(rhs,e.n1,value); m:rhs(rhs,e.n2,value:neg())
            elseif e.kind=="I" then m:rhs(rhs,e.n1,one:neg()); m:rhs(rhs,e.n2,one)
            elseif e.kind=="G" or e.kind=="F" then local value=e.kind=="G" and m:voltage(solution,e.c1,e.c2) or solution[m.indices[e.reference]]; m:rhs(rhs,e.n1,value:neg()); m:rhs(rhs,e.n2,value)
            elseif e.kind=="V" then m:rhs(rhs,e.name,one)
            elseif e.kind=="E" then m:rhs(rhs,e.name,m:voltage(solution,e.c1,e.c2))
            else m:rhs(rhs,e.name,solution[m.indices[e.reference]]) end
            emit("dV(%s)/d%s = %s",args[1],e.name,m:potential(solve(m.a,rhs),args[1]):value())
        end
    elseif name==".ZPARAM" then
        local z1,z2=m:injection(args[1],args[2]),m:injection(args[3],args[4])
        emit("z11 = %s",m:voltage(z1,args[1],args[2]):value()); emit("z12 = %s",m:voltage(z2,args[1],args[2]):value()); emit("z21 = %s",m:voltage(z1,args[3],args[4]):value()); emit("z22 = %s",m:voltage(z2,args[3],args[4]):value())
    elseif name==".SUPERPOSITION" then
        local total=zero
        for _,e in ipairs(self.elements) do if independent(e) then local value=m:potential(m:alone(e,e.value),args[1]); emit("%s: V(%s) = %s",e.name,args[1],value:value()); total=total:add(value) end end
        emit("total: V(%s) = %s",args[1],total:value())
    end
    return lines
end
local circuit=setmetatable({elements={}},Circuit)
local line_number=0
for line in io.lines() do
    line_number=line_number+1
    if line==".END" then break end
    if line:sub(1,1)~="*" then
        local ok,result=pcall(function() if line:sub(1,1)=="." then return circuit:command(words(line)) else circuit:add(words(line)); return {} end end)
        if ok then for _,text in ipairs(result) do io.write(text,"\n") end
        else if type(result)~="table" or not result.reason then error(result,0) end; io.write(string.format("error: line %d: %s\n",line_number,result.reason)) end
    end
end
